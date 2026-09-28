import CoreGraphics
import Foundation

public struct Mark: Equatable {
    public var rect: CGRect
    public var note: String

    public init(rect: CGRect, note: String = "") {
        self.rect = rect
        self.note = note
    }

    public var isPin: Bool { rect.size == .zero }
}

public struct DeviceFacts: Equatable {
    public var serial: String
    public var model: String?
    public var densityDpi: Int?
    public var activity: String?
    public var hierarchyXML: Data?

    public init(serial: String, model: String? = nil, densityDpi: Int? = nil, activity: String? = nil, hierarchyXML: Data? = nil) {
        self.serial = serial
        self.model = model
        self.densityDpi = densityDpi
        self.activity = activity
        self.hierarchyXML = hierarchyXML
    }
}

public struct Review {
    public var runtime: CGImage
    public var facts: DeviceFacts?
    public var marks: [Mark]
    public var refs: [CGImage]
    public var figmaURL: String

    public init(runtime: CGImage, facts: DeviceFacts? = nil, marks: [Mark] = [], refs: [CGImage] = [], figmaURL: String = "") {
        self.runtime = runtime
        self.facts = facts
        self.marks = marks
        self.refs = refs
        self.figmaURL = figmaURL
    }

    public var pixelSize: CGSize { CGSize(width: runtime.width, height: runtime.height) }
}

public struct AdbDevice: Equatable, Identifiable {
    public var id: String
    public var model: String?
    public var state: String

    public init(id: String, model: String?, state: String) {
        self.id = id
        self.model = model
        self.state = state
    }

    public var isOnline: Bool { state == "device" }
}

public struct ViewHit: Equatable {
    public var resourceId: String
    public var className: String
    public var bounds: CGRect

    public init(resourceId: String, className: String, bounds: CGRect) {
        self.resourceId = resourceId
        self.className = className
        self.bounds = bounds
    }
}

public struct HistoryItem: Equatable, Identifiable {
    public var time: String
    public var dir: URL

    public init(time: String, dir: URL) {
        self.time = time
        self.dir = dir
    }

    public var id: URL { dir }
}

public struct HistoryDay: Equatable, Identifiable {
    public var date: String
    public var items: [HistoryItem]

    public init(date: String, items: [HistoryItem]) {
        self.date = date
        self.items = items
    }

    public var id: String { date }
}

public enum Palette {
    public static let rgb: [UInt32] = [0xFF3B30, 0x0A84FF, 0xAF52DE, 0xFF9500, 0x34C759, 0xFF2D55]

    public static func rgb(at index: Int) -> UInt32 { rgb[index % rgb.count] }
}

public enum UIBoardError: Error, Equatable, LocalizedError {
    case notImplemented
    case imageDecodeFailed
    case imageEncodeFailed
    case notPNG
    case processFailed(status: Int32, stderr: String)
    case timeout(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented: "Not implemented yet."
        case .imageDecodeFailed: "The image could not be decoded."
        case .imageEncodeFailed: "The image could not be encoded as PNG."
        case .notPNG: "adb did not return a PNG screenshot. Is the device unlocked?"
        case let .processFailed(status, stderr): "Command failed (\(status)): \(stderr)"
        case let .timeout(command): "Timed out: \(command)"
        case let .exportFailed(reason): "Export failed: \(reason)"
        }
    }
}
