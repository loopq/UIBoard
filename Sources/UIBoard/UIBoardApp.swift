import AppKit
import SwiftUI
import UIBoardCore

@main
struct UIBoardApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = EditorModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("UIBoard", id: "main") {
            EditorView()
                .environment(model)
                .labelStyle(.titleAndIcon)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { UIBoardCommands(model: model) }

        Window("History", id: "history") {
            HistoryView().environment(model)
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: EditorModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let count = model?.dirtyCount, count > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit UIBoard?"
        alert.informativeText = count == 1
            ? "1 tab has annotations that haven't been exported."
            : "\(count) tabs have annotations that haven't been exported."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit").hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

struct UIBoardCommands: Commands {
    let model: EditorModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Screenshots…") { model.importImages(to: .newBoard) }
                .keyboardShortcut("o")
            Divider()
            Button("Capture to New Tab") { Task { await model.capture(to: .newBoard) } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Capture into This Board") { Task { await model.capture(to: .currentBoard) } }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Refresh Devices") { Task { await model.refreshDevices(prompt: true) } }
                .keyboardShortcut("r")
            Divider()
            Button("Export This Tab") { Task { await model.export() } }
                .keyboardShortcut("e")
                .disabled(!model.canExport)
            Button("Open UIReview Folder") { model.openWorkspace() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { model.requestCloseCurrent() }
                .keyboardShortcut("w")
        }
        CommandGroup(before: .windowList) {
            Button("Previous Tab") { model.selectAdjacent(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Tab") { model.selectAdjacent(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Divider()
            Button("History") { openWindow(id: "history") }
                .keyboardShortcut("y")
            Divider()
        }
    }
}
