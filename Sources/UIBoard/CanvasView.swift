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
            Task { model.open(await ImageSource.load(providers), to: destination) }
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

private struct BoardView: View {
    @Environment(EditorModel.self) private var model
    let board: Board

    private static let headerHeight: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let sizes = board.frames.map(\.size)
            let gap = BoardLayout.gap(for: sizes)
            let slot = (sizes.map(\.width).max() ?? 0) * 0.35
            let content = BoardLayout.size(for: sizes)
            let scale = max(min((geo.size.width - 48) / (content.width + gap + slot),
                                (geo.size.height - 48 - Self.headerHeight) / content.height), 0.01)
            HStack(alignment: .top, spacing: gap * scale) {
                ForEach(Array(board.frames.enumerated()), id: \.element.id) { index, frame in
                    VStack(spacing: 6) {
                        FrameHeader(index: index, removable: board.frames.count > 1)
                            .frame(width: frame.size.width * scale, height: Self.headerHeight - 6)
                        FrameCanvas(index: index, frame: frame, scale: scale)
                    }
                }
                AddFrameSlot()
                    .frame(width: slot * scale, height: content.height * scale)
                    .padding(.top, Self.headerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
