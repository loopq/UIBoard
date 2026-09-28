import AppKit
import ImageIO
import SwiftUI
import UIBoardCore

struct HistoryView: View {
    @Environment(EditorModel.self) private var model
    @State private var days: [HistoryDay] = []

    var body: some View {
        Group {
            if days.isEmpty {
                ContentUnavailableView("No exports yet", systemImage: "clock", description: Text("Exported reviews appear here."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Text(day.date).font(.system(size: 13, weight: .bold))
                                    CountBadge(count: day.items.count)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 120), spacing: 24)], alignment: .leading, spacing: 24) {
                                    ForEach(day.items) { HistoryCell(item: $0) }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task(id: model.lastExport) {
            days = HistoryScanner.scan(workspace: Prefs.workspaceURL)
        }
    }
}

private struct HistoryCell: View {
    let item: HistoryItem
    @State private var thumbnail: CGImage?
    @State private var hovering = false

    private var annotated: URL { item.dir.appendingPathComponent("annotated.png") }

    private var timeLabel: String {
        let parts = item.time.split(separator: "-")
        let clock = parts.prefix(3).joined(separator: ":")
        return parts.count > 3 ? "\(clock) (\(parts[3]))" : clock
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.canvas
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 120, height: 267)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hovering ? Color.accentColor : Color.shotline, lineWidth: hovering ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 4) {
                        action("doc.on.doc", "Copy path") { copyToPasteboard(item.dir.path) }
                        action("folder", "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.dir]) }
                    }
                    .padding(6)
                }
            }
            Text(timeLabel).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(annotated) }
        .help(item.dir.tildePath)
        .task(id: item.dir) {
            let url = annotated
            thumbnail = await Task.detached { Self.loadThumbnail(url) }.value
        }
    }

    private func action(_ symbol: String, _ label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.96)).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .help(label)
        .accessibilityLabel(label)
    }

    nonisolated private static func loadThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 534,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
