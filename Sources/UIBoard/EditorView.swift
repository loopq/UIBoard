import AppKit
import SwiftUI
import UIBoardCore

struct EditorView: View {
    @Environment(EditorModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var monitor: Any?

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            CanvasView()
            Divider()
            InspectorView()
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowAccessor { model.window = $0 })
        .toolbar { toolbar }
        .task { await model.refreshDevices(prompt: false) }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
                MainActor.assumeIsolated { model.consumes(event) } ? nil : event
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        .alert(model.pendingReplacement?.runtime == nil ? "Discard this review?" : "Replace screenshot?",
               isPresented: Binding(get: { model.pendingReplacement != nil }, set: { if !$0 { model.pendingReplacement = nil } }),
               presenting: model.pendingReplacement) { replacement in
            Button("Cancel", role: .cancel) {}
            Button(replacement.runtime == nil ? "Discard" : "Replace", role: .destructive) { model.apply(replacement) }
        } message: { _ in
            Text("This will clear \(model.marks.count) annotations.")
        }
        .alert("adb not found", isPresented: $model.adbMissing) {
            Button("Open Settings") { openSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Install Android platform-tools, or choose the adb binary in Settings.")
        }
        .alert("UIBoard", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
               presenting: model.errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: Binding(get: { model.exportedURL != nil }, set: { if !$0 { model.exportedURL = nil } })) {
            if let url = model.exportedURL {
                ExportSheet(url: url,
                            onCopy: { model.exportedURL = nil; model.show("Path copied") },
                            onClose: { model.exportedURL = nil })
            }
        }
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
            Button { Task { await model.capture() } } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            }
            .help("Capture from device (⌘⇧A)")
            .disabled(model.isCapturing)
            Button { model.importRuntime() } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import a screenshot (⌘O)")
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
            .help("Export (⌘E)")
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
