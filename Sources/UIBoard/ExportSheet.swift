import AppKit
import SwiftUI

struct ExportSheet: View {
    let url: URL
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white, .green)
            Text("Exported")
                .font(.system(size: 13, weight: .bold))
                .padding(.top, 12)
            Text(url.tildePath)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(.top, 8)
            HStack(spacing: 8) {
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    onClose()
                }
                Button("Copy Path") {
                    copyToPasteboard(url.path)
                    onCopy()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 440)
        .onExitCommand(perform: onClose)
    }
}
