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

struct BoardFrame: Identifiable {
    let id = UUID()
    var image: CGImage
    var facts: DeviceFacts?
    var fetchingFacts = false

    var size: CGSize { CGSize(width: image.width, height: image.height) }
}

struct Board: Identifiable {
    let id = UUID()
    let number: Int
    var frames: [BoardFrame] { didSet { exportedURL = nil } }
    var marks: [Mark] = [] { didSet { exportedURL = nil } }
    var refs: [CGImage] = [] { didSet { exportedURL = nil } }
    var figmaURL = "" { didSet { exportedURL = nil } }
    var selected: Int?
    var exportedURL: URL?

    var title: String {
        guard let activity = frames.first?.facts?.activity else { return "Screen \(number)" }
        return String(activity.split(separator: "/").last?.split(separator: ".").last ?? Substring(activity))
    }

    var isDirty: Bool { !marks.isEmpty && exportedURL == nil }
}

enum Destination {
    case newBoard
    case currentBoard
}

enum PendingRemoval {
    case board(UUID)
    case frame(board: UUID, index: Int)
}

@MainActor
@Observable
final class EditorModel {
    var boards: [Board] = []
    var currentID: UUID?
    var focusRequest: Int?
    var draft: Mark?

    var devices: [AdbDevice] = []
    var selectedSerial = UserDefaults.standard.string(forKey: Prefs.lastDeviceSerial)
    var isCapturing = false
    var isExporting = false

    var pendingRemoval: PendingRemoval?
    var exportedURL: URL?
    var lastExport: URL?
    var errorMessage: String?
    var adbMissing = false
    var toast: String?

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var factsTasks: [UUID: Task<DeviceFacts, Never>] = [:]
    @ObservationIgnored private var renderCache: [UUID: (key: RenderKey, image: CGImage?)] = [:]
    @ObservationIgnored private var boardCounter = 0

    private struct RenderKey: Equatable {
        let image: ObjectIdentifier
        let frame: Int
        let geometry: [CGRect]
        let owners: [Int]
        let highlight: Int?
    }

    var currentIndex: Int? { boards.firstIndex { $0.id == currentID } }
    var current: Board? { currentIndex.map { boards[$0] } }
    var isFetchingFacts: Bool { current?.frames.contains(where: \.fetchingFacts) == true }
    var canExport: Bool { current.map { !$0.marks.isEmpty } == true && !isExporting }
    var dirtyCount: Int { boards.filter(\.isDirty).count }
    var selectedDevice: AdbDevice? { devices.first { $0.id == selectedSerial } }

    func updateCurrent(_ body: (inout Board) -> Void) {
        guard let index = currentIndex else { return }
        body(&boards[index])
    }

    func rendered(frame index: Int) -> CGImage? {
        guard let board = current, board.frames.indices.contains(index) else { return nil }
        let frame = board.frames[index]
        let shown = draft.map { board.marks + [$0] } ?? board.marks
        let key = RenderKey(image: ObjectIdentifier(frame.image), frame: index,
                            geometry: shown.map(\.rect), owners: shown.map(\.frame), highlight: board.selected)
        if let cached = renderCache[frame.id], cached.key == key { return cached.image }
        let image = AnnotationRenderer.render(runtime: frame.image, marks: shown, frame: index, highlight: board.selected)
        renderCache[frame.id] = (key, image)
        return image
    }

    // MARK: Boards & frames

    func add(_ images: [(CGImage, Task<DeviceFacts, Never>?)], to destination: Destination) {
        guard !images.isEmpty else { return }
        if destination == .currentBoard, let index = currentIndex {
            let start = boards[index].frames.count
            boards[index].frames += images.map(makeFrame)
            let labels = (start..<boards[index].frames.count).map(Frame.label(at:)).joined(separator: ", ")
            show("Added frame \(labels)")
        } else {
            for image in images {
                boardCounter += 1
                let board = Board(number: boardCounter, frames: [makeFrame(image)])
                boards.append(board)
                currentID = board.id
            }
        }
        draft = nil
    }

    private func makeFrame(_ item: (CGImage, Task<DeviceFacts, Never>?)) -> BoardFrame {
        var frame = BoardFrame(image: item.0)
        guard let task = item.1 else { return frame }
        frame.fetchingFacts = true
        let id = frame.id
        factsTasks[id] = task
        Task {
            let facts = await task.value
            setFacts(facts, frame: id)
        }
        return frame
    }

    private func setFacts(_ facts: DeviceFacts, frame id: UUID) {
        factsTasks[id] = nil
        for b in boards.indices {
            if let f = boards[b].frames.firstIndex(where: { $0.id == id }) {
                boards[b].frames[f].facts = facts
                boards[b].frames[f].fetchingFacts = false
            }
        }
    }

    func open(_ items: [Data], to destination: Destination) {
        do { add(try items.map { (try ImageIngest.decode($0), nil) }, to: destination) } catch { report(error) }
    }

    func addRefs(_ items: [Data]) {
        guard currentIndex != nil else { return open(items, to: .newBoard) }
        do {
            let images = try items.map(ImageIngest.decode)
            updateCurrent { $0.refs += images }
        } catch {
            report(error)
        }
    }

    func paste(_ data: Data) {
        if current == nil {
            open([data], to: .newBoard)
        } else {
            addRefs([data])
            show("Added as reference \(current?.refs.count ?? 0)")
        }
    }

    func importImages(to destination: Destination) {
        open(ImageSource.open(multiple: true), to: destination)
    }

    func pasteFrame() {
        guard let data = ImageSource.pasteboardImage() else { return show("No image on the clipboard") }
        open([data], to: .currentBoard)
    }

    func select(board id: UUID) {
        currentID = id
        draft = nil
    }

    func selectAdjacent(_ step: Int) {
        guard let index = currentIndex, !boards.isEmpty else { return }
        select(board: boards[(index + step + boards.count) % boards.count].id)
    }

    func requestClose(_ id: UUID) {
        guard let board = boards.first(where: { $0.id == id }) else { return }
        if board.isDirty { pendingRemoval = .board(id) } else { close(id) }
    }

    func requestCloseCurrent() {
        if let keyWindow = NSApp.keyWindow, keyWindow !== window {
            keyWindow.performClose(nil)
        } else if let id = currentID {
            requestClose(id)
        }
    }

    func requestRemoveFrame(_ index: Int) {
        guard let board = current else { return }
        if board.marks.contains(where: { $0.frame == index }) {
            pendingRemoval = .frame(board: board.id, index: index)
        } else {
            removeFrame(index, board: board.id)
        }
    }

    func confirm(_ removal: PendingRemoval) {
        pendingRemoval = nil
        switch removal {
        case let .board(id): close(id)
        case let .frame(board, index): removeFrame(index, board: board)
        }
    }

    private func close(_ id: UUID) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        for frame in boards[index].frames {
            renderCache[frame.id] = nil
            factsTasks[frame.id] = nil
        }
        boards.remove(at: index)
        if currentID == id {
            currentID = boards.isEmpty ? nil : boards[min(index, boards.count - 1)].id
        }
        draft = nil
    }

    private func removeFrame(_ index: Int, board id: UUID) {
        guard let b = boards.firstIndex(where: { $0.id == id }), boards[b].frames.indices.contains(index) else { return }
        renderCache[boards[b].frames[index].id] = nil
        boards[b].frames.remove(at: index)
        boards[b].marks = boards[b].marks.compactMap { mark in
            guard mark.frame != index else { return nil }
            var mark = mark
            if mark.frame > index { mark.frame -= 1 }
            return mark
        }
        boards[b].selected = nil
    }

    // MARK: Marks

    func commit(_ mark: Mark) {
        draft = nil
        updateCurrent {
            $0.marks.append(mark)
            $0.selected = $0.marks.count - 1
        }
        focusRequest = (current?.marks.count ?? 1) - 1
    }

    func deleteMark(at index: Int) {
        updateCurrent {
            guard $0.marks.indices.contains(index) else { return }
            $0.marks.remove(at: index)
            $0.selected = nil
        }
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

    func capture(to destination: Destination) async {
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
            add([(image, Task { await adb.facts(serial: device.id, model: device.model) })], to: destination)
        } catch {
            report(error)
        }
    }

    // MARK: Export

    func export() async {
        guard canExport, let board = current else { return }
        if let empty = board.marks.firstIndex(where: { $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            updateCurrent { $0.selected = empty }
            focusRequest = empty
            show("Describe #\(empty + 1) before exporting")
            return
        }
        isExporting = true
        defer { isExporting = false }
        for frame in board.frames {
            if let task = factsTasks[frame.id] { setFacts(await task.value, frame: frame.id) }
        }
        guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        let snapshot = boards[index]
        let review = Review(frames: snapshot.frames.map { Frame(image: $0.image, facts: $0.facts) },
                            marks: snapshot.marks, refs: snapshot.refs,
                            figmaURL: snapshot.figmaURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let workspace = Prefs.workspaceURL
        do {
            let url = try await Task.detached { try ReviewExporter.export(review, workspace: workspace, now: Date()) }.value
            if let i = boards.firstIndex(where: { $0.id == board.id }) { boards[i].exportedURL = url }
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
           event.keyCode == 51 || event.keyCode == 117, let selected = current?.selected {
            deleteMark(at: selected)
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
