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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct UIBoardCommands: Commands {
    let model: EditorModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Review") { model.newReview() }
                .keyboardShortcut("n")
            Button("Import Screenshot…") { model.importRuntime() }
                .keyboardShortcut("o")
            Divider()
            Button("Capture from Device") { Task { await model.capture() } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Refresh Devices") { Task { await model.refreshDevices(prompt: true) } }
                .keyboardShortcut("r")
            Divider()
            Button("Export") { Task { await model.export() } }
                .keyboardShortcut("e")
                .disabled(!model.canExport)
            Button("Open UIReview Folder") { model.openWorkspace() }
        }
        CommandGroup(before: .windowList) {
            Button("History") { openWindow(id: "history") }
                .keyboardShortcut("y")
            Divider()
        }
    }
}
