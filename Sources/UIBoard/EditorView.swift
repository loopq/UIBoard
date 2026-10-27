import AppKit
import SwiftUI
import UIBoardCore

struct EditorView: View {
    @Environment(EditorModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if !model.boards.isEmpty { TabBarView() }
            HStack(spacing: 0) {
                CanvasView()
                Divider()
                InspectorView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowAccessor { model.window = $0 })
        .toolbar { toolbar }
        .task { await model.refreshDevices(prompt: false) }
        .task { await model.checkForUpdates(manual: false) }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
                MainActor.assumeIsolated { model.consumes(event) } ? nil : event
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        .modifier(EditorAlerts())
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                if model.devices.isEmpty {
                    Text("No devices")
                }
                ForEach(model.devices) { device in
                    Toggle(device.menuTitle, isOn: Binding(get: { model.selectedSerial == device.id },
                                                           set: { if $0 { model.select(device.id) } }))
                        .disabled(!device.isOnline)
                }
                Divider()
                Button("Refresh") { Task { await model.refreshDevices(prompt: true) } }
            } label: {
                Label(model.selectedDevice?.name ?? model.selectedSerial ?? "No Device",
                      systemImage: model.selectedDevice?.isOnline == true ? "iphone" : "iphone.slash")
            }
            .help("Device")
            Menu {
                Button("New Tab  ⌘⇧A") { Task { await model.capture(to: .newBoard) } }
                Button("Add to This Board  ⌘⌥A") {
                    let destination = model.here
                    Task { await model.capture(to: destination) }
                }
            } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            } primaryAction: {
                Task { await model.capture(to: .newBoard) }
            }
            .help("Capture to a new tab (⌘⇧A) · add to this board (⌘⌥A)")
            .disabled(model.isCapturing)
            Button { model.importImages(to: .newBoard) } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import screenshots into new tabs (⌘O)")
            if model.isCapturing || model.isFetchingFacts {
                ProgressView().controlSize(.small)
            }
        }
        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            Button { openWindow(id: "history") } label: {
                Label("History", systemImage: "clock")
            }
            .help("History (⌘Y)")
            Button { Task { await model.export() } } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExport)
            .help("Export this tab (⌘E)")
        }
    }
}

private struct EditorAlerts: ViewModifier {
    @Environment(EditorModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert(removalTitle, isPresented: removalBinding, presenting: model.pendingRemoval) { removal in
                Button("Cancel", role: .cancel) {}
                Button(removalAction(removal), role: .destructive) { model.confirm(removal) }
            } message: { removal in
                Text(removalMessage(removal))
            }
            .alert(updateTitle, isPresented: updateBinding, presenting: model.updatePrompt) { prompt in
                switch prompt {
                case let .available(release):
                    Button("Install and Relaunch") { Task { await model.installUpdate(release) } }
                        .keyboardShortcut(.defaultAction)
                    Button("Release Notes") { NSWorkspace.shared.open(release.page) }
                    Button("Later", role: .cancel) {}
                case let .failed(release, _):
                    Button("Open Release Page") { NSWorkspace.shared.open(release.page) }
                    Button("Cancel", role: .cancel) {}
                }
            } message: { prompt in
                Text(updateMessage(prompt))
            }
            .alert("adb not found", isPresented: $model.adbMissing) {
                Button("Open Settings") { openSettings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Install Android platform-tools, or choose the adb binary in Settings.")
            }
            .alert("UIBoard", isPresented: errorBinding, presenting: model.errorMessage) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: exportBinding) {
                if let url = model.exportedURL {
                    ExportSheet(url: url,
                                onCopy: { model.exportedURL = nil; model.show("Path copied") },
                                onClose: { model.exportedURL = nil })
                }
            }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })
    }

    private var updateBinding: Binding<Bool> {
        Binding(get: { model.updatePrompt != nil }, set: { if !$0 { model.updatePrompt = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var exportBinding: Binding<Bool> {
        Binding(get: { model.exportedURL != nil }, set: { if !$0 { model.exportedURL = nil } })
    }

    private var removalTitle: String {
        switch model.pendingRemoval {
        case let .frame(_, index): return "Remove frame \(Frame.label(at: index))?"
        case let .boards(ids) where ids.count > 1: return "Close \(ids.count) tabs?"
        default: return "Close this tab?"
        }
    }

    private var updateTitle: String {
        switch model.updatePrompt {
        case let .available(release): "UIBoard \(release.version) is available"
        case let .failed(release, _): "Couldn't install UIBoard \(release.version)"
        case nil: ""
        }
    }

    private func updateMessage(_ prompt: UpdatePrompt) -> String {
        switch prompt {
        case .available: "You have \(model.appVersion). UIBoard will quit and reopen."
        case let .failed(_, reason): reason
        }
    }

    private func removalAction(_ removal: PendingRemoval) -> String {
        if case .frame = removal { return "Remove" }
        return "Close"
    }

    private func removalMessage(_ removal: PendingRemoval) -> String {
        switch removal {
        case let .boards(ids):
            let dirty = model.boards.filter { ids.contains($0.id) && $0.isDirty }
            if ids.count == 1 { return "Its \(dirty.first?.marks.count ?? 0) annotations haven't been exported." }
            return dirty.count == 1
                ? "1 tab has annotations that haven't been exported."
                : "\(dirty.count) tabs have annotations that haven't been exported."
        case let .frame(board, index):
            let count = model.boards.first { $0.id == board }?.marks.filter { $0.frame == index }.count ?? 0
            return "Its \(count) annotations will be deleted."
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
