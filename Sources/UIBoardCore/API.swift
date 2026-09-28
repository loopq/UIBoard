import CoreGraphics
import Foundation

public enum ImageIngest {
    public static func decode(_ data: Data) throws -> CGImage {
        throw UIBoardError.notImplemented
    }

    public static func png(_ image: CGImage) throws -> Data {
        throw UIBoardError.notImplemented
    }
}

public enum AnnotationRenderer {
    public static func render(runtime: CGImage, marks: [Mark], highlight: Int?) -> CGImage? {
        nil
    }
}

public enum Crop {
    public static func rect(for mark: Mark, in size: CGSize) -> CGRect {
        .zero
    }
}

public enum ReviewMarkdown {
    public static func render(_ review: Review, created: Date, hits: [[ViewHit]]) -> String {
        ""
    }
}

public enum ReviewExporter {
    public static func export(_ review: Review, workspace: URL, now: Date) throws -> URL {
        throw UIBoardError.notImplemented
    }
}

public enum HitTest {
    public static func views(for rect: CGRect, hierarchyXML: Data) -> [ViewHit] {
        []
    }
}

public struct Adb {
    public let executable: URL

    public static func locate(override: String?) -> URL? {
        nil
    }

    public init(executable: URL) {
        self.executable = executable
    }

    public func devices() async throws -> [AdbDevice] {
        throw UIBoardError.notImplemented
    }

    public func screencap(serial: String) async throws -> Data {
        throw UIBoardError.notImplemented
    }

    public func facts(serial: String, model: String?) async -> DeviceFacts {
        DeviceFacts(serial: serial, model: model)
    }
}

public enum HistoryScanner {
    public static func scan(workspace: URL) -> [HistoryDay] {
        []
    }
}
