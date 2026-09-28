import AppKit
import SwiftUI
import UIBoardCore

struct SettingsView: View {
    @AppStorage(Prefs.workspacePath) private var workspacePath = Prefs.defaultWorkspace
    @AppStorage(Prefs.adbPath) private var adbPath = ""

    var body: some View {
        let detected = Adb.locate(override: nil)
        VStack(alignment: .leading, spacing: 8) {
            Form {
                LabeledContent("Workspace") {
                    HStack(spacing: 12) {
                        path(workspacePath)
                        Button("Choose…") { chooseWorkspace() }
                    }
                }
                LabeledContent("adb") {
                    HStack(spacing: 12) {
                        path(adbPath.isEmpty ? (detected?.tildePath ?? "Not found") : adbPath)
                            .foregroundStyle(adbPath.isEmpty ? .secondary : .primary)
                        if adbPath.isEmpty, detected != nil {
                            Text("Auto-detected")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(rgb: 0x1E8A3C))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(rgb: 0x34C759).opacity(0.15)))
                        }
                        if !adbPath.isEmpty {
                            Button("Reset") { adbPath = "" }
                        }
                        Button("Choose…") { chooseAdb() }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            Text("Keep paths free of spaces — the export path is passed to Claude / Codex as a command argument.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func path(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { workspacePath = url.tildePath }
    }

    private func chooseAdb() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { adbPath = url.path }
    }
}
