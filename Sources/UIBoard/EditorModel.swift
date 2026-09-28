import AppKit
import Observation
import UIBoardCore

enum Prefs {
    static let workspacePath = "workspacePath"
    static let adbPath = "adbPath"
    static let lastDeviceSerial = "lastDeviceSerial"
    static let defaultWorkspace = "~/UIReview"

    static var workspaceURL: URL {
        let path = UserDefaults.standard.string(forKey: workspacePath) ?? defaultWorkspace
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var adbOverride: String? {
        let path = UserDefaults.standard.string(forKey: adbPath) ?? ""
        return path.isEmpty ? nil : path
    }
}

struct Replacement {
    var runtime: CGImage?
    var facts: Task<DeviceFacts, Never>?
}

@MainActor
@Observable
final class EditorModel {
    var runtime: CGImage?
    var marks: [Mark] = []
    var refs: [CGImage] = []
    var figmaURL = ""
    var selected: Int?
    var focusRequest: Int?
    var draft: Mark?

    var devices: [AdbDevice] = []
    var selectedSerial = UserDefaults.standard.string(forKey: Prefs.lastDeviceSerial)
    var isCapturing = false
    var isExporting = false

    var pendingReplacement: Replacement?
    var exportedURL: URL?
    var lastExport: URL?
    var errorMessage: String?
    var adbMissing = false
    var toast: String?

    private var facts: DeviceFacts?
    private var factsTask: Task<DeviceFacts, Never>?
    private var factsToken = UUID()
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var renderCache: (runtime: CGImage, rects: [CGRect], highlight: Int?, image: CGImage?)?

    var isFetchingFacts: Bool { factsTask != nil }
    var canExport: Bool { runtime != nil && !marks.isEmpty && !isExporting }
    var selectedDevice: AdbDevice? { devices.first { $0.id == selectedSerial } }

    var rendered: CGImage? {
        guard let runtime else { return nil }
        let shown = draft.map { marks + [$0] } ?? marks
        let rects = shown.map(\.rect)
        if let cache = renderCache, cache.runtime === runtime, cache.rects == rects, cache.highlight == selected {
            return cache.image
        }
        let image = AnnotationRenderer.render(runtime: runtime, marks: shown, highlight: selected)
        renderCache = (runtime, rects, selected, image)
        return image
    }

    // MARK: Runtime & references

    func request(_ replacement: Replacement) {
        if marks.isEmpty { apply(replacement) } else { pendingReplacement = replacement }
    }

    func apply(_ replacement: Replacement) {
        pendingReplacement = nil
        if replacement.runtime == nil {
            refs = []
            figmaURL = ""
        }
        runtime = replacement.runtime
        marks = []
        selected = nil
        draft = nil
        facts = nil
        factsToken = UUID()
        factsTask = replacement.facts
        guard let task = replacement.facts else { return }
        let token = factsToken
        Task {
            let value = await task.value
            guard token == factsToken else { return }
            facts = value
            factsTask = nil
        }
    }

    func newReview() {
        request(Replacement())
    }

    func setRuntime(_ data: Data) {
        do { request(Replacement(runtime: try ImageIngest.decode(data))) } catch { report(error) }
    }

    func addRefs(_ items: [Data]) {
        do { refs += try items.map(ImageIngest.decode) } catch { report(error) }
    }

    func paste(_ data: Data) {
        if runtime == nil {
            setRuntime(data)
        } else {
            addRefs([data])
            show("Added as reference \(refs.count)")
        }
    }

    func importRuntime() {
        if let data = ImageSource.open(multiple: false).first { setRuntime(data) }
    }

    // MARK: Marks

    func commit(_ mark: Mark) {
        marks.append(mark)
        draft = nil
        selected = marks.count - 1
        focusRequest = marks.count - 1
    }

    func delete(at index: Int) {
        guard marks.indices.contains(index) else { return }
        marks.remove(at: index)
        selected = nil
    }

    // MARK: Devices

    func adb(prompt: Bool) -> Adb? {
        guard let url = Adb.locate(override: Prefs.adbOverride) else {
            if prompt { adbMissing = true }
            return nil
        }
        return Adb(executable: url)
    }

    func refreshDevices(prompt: Bool) async {
        guard let adb = adb(prompt: prompt) else { return }
        do {
            devices = try await adb.devices()
        } catch {
            devices = []
            if prompt { report(error) }
        }
        let online = devices.filter(\.isOnline)
        if selectedSerial == nil, online.count == 1 { select(online[0].id) }
    }

    func select(_ serial: String) {
        selectedSerial = serial
        UserDefaults.standard.set(serial, forKey: Prefs.lastDeviceSerial)
    }

    func capture() async {
        guard !isCapturing, let adb = adb(prompt: true) else { return }
        if selectedDevice?.isOnline != true { await refreshDevices(prompt: true) }
        guard let device = selectedDevice, device.isOnline else {
            errorMessage = "No online device selected. Connect a device and pick it from the device menu."
            return
        }
        isCapturing = true
        defer { isCapturing = false }
        do {
            let image = try ImageIngest.decode(try await adb.screencap(serial: device.id))
            request(Replacement(runtime: image, facts: Task { await adb.facts(serial: device.id, model: device.model) }))
        } catch {
            report(error)
        }
    }

    // MARK: Export

    func export() async {
        guard canExport else { return }
        if let empty = marks.firstIndex(where: { $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            selected = empty
            focusRequest = empty
            show("Describe #\(empty + 1) before exporting")
            return
        }
        isExporting = true
        defer { isExporting = false }
        let token = factsToken
        if let task = factsTask {
            let value = await task.value
            guard token == factsToken else { return }
            facts = value
            factsTask = nil
        }
        guard let runtime else { return }
        let review = Review(runtime: runtime, facts: facts, marks: marks, refs: refs,
                            figmaURL: figmaURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let workspace = Prefs.workspaceURL
        do {
            let url = try await Task.detached { try ReviewExporter.export(review, workspace: workspace, now: Date()) }.value
            exportedURL = url
            lastExport = url
        } catch {
            report(error)
        }
    }

    func openWorkspace() {
        let url = Prefs.workspaceURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            report(error)
        }
    }

    // MARK: Keyboard

    func consumes(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let editing = window.firstResponder is NSText
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "v" {
            if editing && ImageSource.pasteboardHasText { return false }
            guard let data = ImageSource.pasteboardImage() else { return false }
            paste(data)
            return true
        }
        if flags.isDisjoint(with: [.command, .option, .control, .shift]), !editing,
           event.keyCode == 51 || event.keyCode == 117, let selected {
            delete(at: selected)
            return true
        }
        return false
    }

    // MARK: Feedback

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

extension AdbDevice {
    var name: String { (model ?? id).replacingOccurrences(of: "_", with: " ") }
    var menuTitle: String { isOnline ? "\(name) · \(id)" : "\(name) · \(id) — \(state)" }
}
