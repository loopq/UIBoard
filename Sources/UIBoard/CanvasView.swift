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
        GeometryReader { geo in
            ZStack {
                Color.canvas
                if let runtime = model.runtime {
                    shot(runtime, in: geo.size)
                } else {
                    EmptyDropZone()
                }
            }
            .overlay(alignment: .bottom) { toast }
            .overlay { if dropTargeted { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) } }
        }
        .onDrop(of: ImageSource.dropTypes, isTargeted: $dropTargeted) { providers in
            Task { if let data = await ImageSource.load(providers).first { model.setRuntime(data) } }
            return true
        }
    }

    private func shot(_ runtime: CGImage, in available: CGSize) -> some View {
        let size = CGSize(width: runtime.width, height: runtime.height)
        let scale = max(min((available.width - 48) / size.width, (available.height - 48) / size.height), 0.01)
        return Image(decorative: model.rendered ?? runtime, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width * scale, height: size.height * scale)
            .overlay(Rectangle().strokeBorder(Color.shotline, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if model.draft == nil { model.window?.makeFirstResponder(nil) }
                        let rect = MarkGeometry.rect(from: value.startLocation, to: value.location, scale: scale, size: size)
                        model.draft = rect.size == .zero ? nil : Mark(rect: rect)
                    }
                    .onEnded { value in
                        model.commit(Mark(rect: MarkGeometry.rect(from: value.startLocation, to: value.location, scale: scale, size: size)))
                    }
            )
            .accessibilityLabel("Screenshot. Click to pin, drag to frame.")
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
