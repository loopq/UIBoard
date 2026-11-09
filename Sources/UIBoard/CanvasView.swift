import AppKit
import SwiftUI
import UIBoardCore

enum MarkGeometry {
    static let clickSlop: CGFloat = 4

    static func pixel(_ point: CGPoint, scale: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(x: min(max((point.x / scale).rounded(), 0), size.width),
                y: min(max((point.y / scale).rounded(), 0), size.height))
    }

    static func rect(from start: CGPoint, to end: CGPoint, scale: CGFloat, size: CGSize) -> CGRect {
        let a = pixel(start, scale: scale, size: size)
        guard hypot(end.x - start.x, end.y - start.y) >= clickSlop else { return CGRect(origin: a, size: .zero) }
        let b = pixel(end, scale: scale, size: size)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: max(abs(b.x - a.x), 1), height: max(abs(b.y - a.y), 1))
    }
}

struct CanvasView: View {
    @Environment(EditorModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            Color.canvas
            if let board = model.current {
                BoardView(board: board)
            } else {
                EmptyDropZone()
            }
        }
        .overlay(alignment: .bottom) { toast }
        .overlay { if dropTargeted { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) } }
        .onDrop(of: ImageSource.dropTypes, isTargeted: $dropTargeted) { providers in
            let destination = model.here
            Task { model.drop(await ImageSource.load(providers), to: destination) }
            return true
        }
    }

    @ViewBuilder private var toast: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 20)
                .transition(.opacity)
        }
    }
}

/// One mapping between board pixels and view points, shared by frames, the add slot, guides and rulers.
/// Frames sit at `BoardLayout.offsets` horizontally and at their preview-only shift vertically.
struct BoardGeometry {
    static let space = "board"
    static let header: CGFloat = 26   // frame header (20) + spacing (6) above each frame
    static let ruler: CGFloat = 18

    let scale: CGFloat
    let origin: CGPoint   // view position of board pixel (0, 0)
    let frames: [CGRect]  // board pixels
    let slot: CGRect      // board pixels

    init(board: Board, size: CGSize, rulers: Bool) {
        let sizes = board.frames.map(\.size)
        let gap = BoardLayout.gap(for: sizes)
        let content = BoardLayout.size(for: sizes)
        frames = zip(board.frames, BoardLayout.offsets(for: sizes)).map { frame, offset in
            CGRect(origin: CGPoint(x: offset.x, y: board.shifts[frame.id] ?? 0), size: frame.size)
        }
        slot = CGRect(x: content.width + gap, y: 0, width: (sizes.map(\.width).max() ?? 0) * 0.35, height: content.height)
        let bounds = frames.reduce(slot) { $0.union($1) }
        let inset = rulers ? Self.ruler : 0
        let room = CGSize(width: size.width - inset - 48, height: size.height - inset - 48 - Self.header)
        scale = max(min(room.width / bounds.width, room.height / bounds.height), 0.01)
        origin = CGPoint(x: inset + (size.width - inset - bounds.width * scale) / 2 - bounds.minX * scale,
                         y: inset + Self.header + (size.height - inset - Self.header - bounds.height * scale) / 2
                             - bounds.minY * scale)
    }

    func view(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    func board(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    func value(_ axis: Guide.Axis, at point: CGPoint) -> CGFloat {
        let p = board(point)
        return (axis == .x ? p.x : p.y).rounded()
    }

    func position(_ axis: Guide.Axis, of value: CGFloat) -> CGFloat {
        axis == .x ? origin.x + value * scale : origin.y + value * scale
    }

    func onRuler(_ axis: Guide.Axis, at point: CGPoint) -> Bool {
        (axis == .x ? point.x : point.y) < Self.ruler
    }

    /// Insertion index for frame `index` once its center has moved by `dx` board pixels.
    func target(moving index: Int, by dx: CGFloat) -> Int {
        let center = frames[index].midX + dx
        return frames.indices.filter { $0 != index && frames[$0].midX < center }.count
    }
}

private struct BoardView: View {
    @Environment(EditorModel.self) private var model
    let board: Board

    var body: some View {
        GeometryReader { geo in
            let geometry = BoardGeometry(board: board, size: geo.size, rulers: model.showsRulers)
            let slot = geometry.view(geometry.slot)
            ZStack(alignment: .topLeading) {
                ForEach(Array(board.frames.enumerated()), id: \.element.id) { index, frame in
                    FrameColumn(index: index, frame: frame, removable: board.frames.count > 1, geometry: geometry)
                }
                AddFrameSlot()
                    .frame(width: slot.width, height: slot.height)
                    .offset(x: slot.minX, y: slot.minY)
                if model.showsRulers {
                    ForEach(board.guides) { guide in
                        GuideLine(guide: guide, geometry: geometry, size: geo.size)
                    }
                    Ruler(top: true, geometry: geometry, size: geo.size)
                    Ruler(top: false, geometry: geometry, size: geo.size)
                    Rectangle().fill(Color.panel).frame(width: BoardGeometry.ruler, height: BoardGeometry.ruler)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .coordinateSpace(name: BoardGeometry.space)
        }
        .clipped()
    }
}

/// Header + screenshot. Dragging the header moves the column. One drag, one intent: if the drop changes the order,
/// the frames are reordered (exported) and the vertical movement is dropped, so a reorder never leaves a stray
/// few-pixel offset; otherwise the vertical movement shifts the frame (preview only). Double-click resets the shift.
private struct FrameColumn: View {
    @Environment(EditorModel.self) private var model
    let index: Int
    let frame: BoardFrame
    let removable: Bool
    let geometry: BoardGeometry
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        let rect = geometry.view(geometry.frames[index])
        VStack(spacing: 6) {
            FrameHeader(index: index, removable: removable)
                .frame(width: rect.width, height: BoardGeometry.header - 6)
                .cursor(.openHand)
                .gesture(move)
                .onTapGesture(count: 2) { model.resetShift(frame.id) }
                .help("Drag to reorder or shift up/down for comparison · double-click to realign")
            FrameCanvas(index: index, frame: frame, scale: geometry.scale)
        }
        .offset(x: rect.minX + drag.width, y: rect.minY - BoardGeometry.header + drag.height)
        .shadow(color: .black.opacity(drag == .zero ? 0 : 0.25), radius: 10)
        .zIndex(drag == .zero ? 0 : 1)
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(BoardGeometry.space))
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let target = geometry.target(moving: index, by: value.translation.width / geometry.scale)
                if target != index {
                    model.moveFrame(index, to: target)
                } else {
                    model.shiftFrame(frame.id, by: value.translation.height / geometry.scale)
                }
            }
    }
}

/// Guides span the whole canvas. Drag to move; drop on the ruler to delete.
private struct GuideLine: View {
    @Environment(EditorModel.self) private var model
    let guide: Guide
    let geometry: BoardGeometry
    let size: CGSize

    var body: some View {
        let vertical = guide.axis == .x
        let position = geometry.position(guide.axis, of: guide.value)
        Color.clear
            .frame(width: vertical ? 7 : size.width, height: vertical ? size.height : 7)
            .overlay { Rectangle().fill(Color.guide).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1) }
            .overlay(alignment: .topLeading) {
                Text(verbatim: "\(vertical ? "X" : "Y") \(Int(guide.value))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Color.guide, in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    .offset(x: vertical ? 6 : BoardGeometry.ruler + 4, y: vertical ? BoardGeometry.ruler + 4 : -10)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .offset(x: vertical ? position - 3 : 0, y: vertical ? 0 : position - 3)
            .cursor(vertical ? .resizeLeftRight : .resizeUpDown)
            .gesture(GuideDrag.gesture(guide.id, guide.axis, geometry, model))
            .accessibilityLabel("Guide \(vertical ? "x" : "y") \(Int(guide.value))")
    }
}

/// Drag out of the top ruler for a horizontal guide, out of the left ruler for a vertical one.
private struct Ruler: View {
    @Environment(EditorModel.self) private var model
    let top: Bool
    let geometry: BoardGeometry
    let size: CGSize
    @State private var next = UUID()

    private static let minLabelGap: CGFloat = 50

    var body: some View {
        let thickness = BoardGeometry.ruler
        Canvas { context, extent in draw(&context, extent) }
            .frame(width: top ? size.width : thickness, height: top ? thickness : size.height)
            .background(Color.panel)
            .overlay(alignment: top ? .bottom : .trailing) {
                Rectangle().fill(Color.shotline).frame(width: top ? nil : 1, height: top ? 1 : nil)
            }
            .contentShape(Rectangle())
            .cursor(top ? .resizeUpDown : .resizeLeftRight)
            .gesture(GuideDrag.gesture(next, top ? .y : .x, geometry, model) { next = UUID() })
            .help("Drag out a guide · drag a guide back here to remove it")
    }

    /// Smallest 1/2/5×10ⁿ board-pixel step whose labels are at least `minLabelGap` points apart.
    static func step(for scale: CGFloat) -> CGFloat {
        var unit: CGFloat = 1
        while true {
            for multiple: CGFloat in [1, 2, 5] where multiple * unit * scale >= minLabelGap { return multiple * unit }
            unit *= 10
        }
    }

    private func draw(_ context: inout GraphicsContext, _ extent: CGSize) {
        let axis: Guide.Axis = top ? .x : .y
        let step = Self.step(for: geometry.scale)
        let first = (geometry.value(axis, at: .zero) / step).rounded(.down) * step
        let last = geometry.value(axis, at: CGPoint(x: extent.width, y: extent.height))
        let thickness = BoardGeometry.ruler
        var ticks = Path()
        for major in stride(from: first, through: last, by: step) {
            for (value, length) in [(major, thickness * 0.6), (major + step / 2, thickness * 0.3)] {
                let p = geometry.position(axis, of: value)
                ticks.move(to: top ? CGPoint(x: p, y: thickness - length) : CGPoint(x: thickness - length, y: p))
                ticks.addLine(to: top ? CGPoint(x: p, y: thickness) : CGPoint(x: thickness, y: p))
            }
            let label = context.resolve(Text(verbatim: "\(Int(major))").font(.system(size: 9)).foregroundColor(.secondary))
            let p = geometry.position(axis, of: major)
            if top {
                context.draw(label, at: CGPoint(x: p + 3, y: 1), anchor: .topLeading)
            } else {
                var rotated = context
                rotated.translateBy(x: 1, y: p - 3)
                rotated.rotate(by: .degrees(-90))
                rotated.draw(label, at: .zero, anchor: .topLeading)
            }
        }
        context.stroke(ticks, with: .color(.secondary), lineWidth: 1)
    }
}

/// Shared by rulers (new guide) and guides (move): the guide follows the pointer and is deleted if dropped on its ruler.
private enum GuideDrag {
    @MainActor
    static func gesture(_ id: UUID, _ axis: Guide.Axis, _ geometry: BoardGeometry, _ model: EditorModel,
                        ended: @escaping () -> Void = {}) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(BoardGeometry.space))
            .onChanged { model.place(Guide(id: id, axis: axis, value: geometry.value(axis, at: $0.location))) }
            .onEnded {
                if geometry.onRuler(axis, at: $0.location) { model.removeGuide(id) }
                ended()
            }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onContinuousHover { phase in
            if case .active = phase { cursor.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct FrameHeader: View {
    @Environment(EditorModel.self) private var model
    let index: Int
    let removable: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(Frame.label(at: index))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.ctrl))
            if removable && hovering {
                Button { model.requestRemoveFrame(index) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove frame \(Frame.label(at: index))")
                .accessibilityLabel("Remove frame \(Frame.label(at: index))")
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct FrameCanvas: View {
    @Environment(EditorModel.self) private var model
    let index: Int
    let frame: BoardFrame
    let scale: CGFloat

    var body: some View {
        Image(decorative: model.rendered(frame: index) ?? frame.image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: frame.size.width * scale, height: frame.size.height * scale)
            .overlay(Rectangle().strokeBorder(Color.shotline, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if model.draft == nil { model.window?.makeFirstResponder(nil) }
                        let rect = MarkGeometry.rect(from: value.startLocation, to: value.location, scale: scale, size: frame.size)
                        model.draft = rect.size == .zero ? nil : Mark(rect: rect, frame: index)
                    }
                    .onEnded { value in
                        let rect = MarkGeometry.rect(from: value.startLocation, to: value.location, scale: scale, size: frame.size)
                        model.commit(Mark(rect: rect, frame: index))
                    }
            )
            .accessibilityLabel("Frame \(Frame.label(at: index)). Click to pin, drag to frame.")
    }
}

private struct AddFrameSlot: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Menu {
            Button("Capture from Device") {
                let destination = model.here
                Task { await model.capture(to: destination) }
            }
            Button("Import…") { model.importImages(to: model.here) }
            Button("Paste Image") { model.pasteFrame() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 18))
                Text("Add frame").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.dash, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Add a frame to this board (⌘⌥A captures from device)")
        .accessibilityLabel("Add frame")
    }
}

private struct EmptyDropZone: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "photo")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop a screenshot")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 16)
            VStack(spacing: 8) {
                hint("⌘V", "to paste")
                hint("⌘⇧A", "to capture from device")
                hint("⌘O", "to import a review")
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: 440, maxHeight: 560)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.dash, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .padding(24)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.card))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.cardline))
            Text(text).foregroundStyle(.secondary)
        }
    }
}
