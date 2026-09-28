import CoreGraphics
import Foundation

public enum ImageIngest {
    public static func decode(_ data: Data) throws -> CGImage {
        try ImageCodec.decode(data)
    }

    public static func png(_ image: CGImage) throws -> Data {
        try ImageCodec.png(image)
    }
}

public enum AnnotationRenderer {
    public static func render(runtime: CGImage, marks: [Mark], frame: Int = 0, highlight: Int?) -> CGImage? {
        AnnotationDrawing.render(runtime: runtime, marks: marks, frame: frame, highlight: highlight)
    }
}

public enum BoardLayout {
    public static func gap(for sizes: [CGSize]) -> CGFloat {
        round((sizes.map(\.width).max() ?? 0) * 0.06)
    }

    public static func offsets(for sizes: [CGSize]) -> [CGPoint] {
        let gap = gap(for: sizes)
        var x: CGFloat = 0
        return sizes.map { size in
            defer { x += size.width + gap }
            return CGPoint(x: x, y: 0)
        }
    }

    public static func size(for sizes: [CGSize]) -> CGSize {
        let width = sizes.map(\.width).reduce(0, +) + gap(for: sizes) * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }
}

public enum Crop {
    public static func rect(for mark: Mark, in size: CGSize) -> CGRect {
        let pad = round(size.width * 0.1)
        let imageBounds = CGRect(origin: .zero, size: size)
        return mark.rect.insetBy(dx: -pad, dy: -pad).intersection(imageBounds)
    }
}

public enum ReviewMarkdown {
    public static func render(_ review: Review, created: Date, hits: [[ViewHit]]) -> String {
        MarkdownRenderer.render(review, created: created, hits: hits)
    }
}

public enum ReviewExporter {
    public static func export(_ review: Review, workspace: URL, now: Date) throws -> URL {
        try Exporter.export(review, workspace: workspace, now: now)
    }
}

public enum HitTest {
    public static func views(for rect: CGRect, hierarchyXML: Data) -> [ViewHit] {
        HierarchyHitTester.views(for: rect, hierarchyXML: hierarchyXML)
    }
}

public struct Adb {
    public let executable: URL

    public static func locate(override: String?) -> URL? {
        AdbImplementation.locate(override: override)
    }

    public init(executable: URL) {
        self.executable = executable
    }

    public func devices() async throws -> [AdbDevice] {
        try await AdbImplementation(executable: executable).devices()
    }

    public func screencap(serial: String) async throws -> Data {
        try await AdbImplementation(executable: executable).screencap(serial: serial)
    }

    public func facts(serial: String, model: String?) async -> DeviceFacts {
        await AdbImplementation(executable: executable).facts(serial: serial, model: model)
    }
}

public enum HistoryScanner {
    public static func scan(workspace: URL) -> [HistoryDay] {
        HistoryImplementation.scan(workspace: workspace)
    }
}
