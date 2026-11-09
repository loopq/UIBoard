import CoreGraphics
import Foundation
import XCTest
@testable import UIBoardCore

final class ImportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_275_742)

    func testV2RoundTripRestoresFramesFactsMarksRefsAndFigma() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let review = Review(
            frames: [
                Frame(image: solidImage(width: 100, height: 200, rgb: 0xFF0000),
                      facts: DeviceFacts(serial: "37091JEHN", model: "Pixel 7", densityDpi: 420,
                                         activity: "com.example/.MainActivity",
                                         hierarchyXML: try fixture("golden-hierarchy", extension: "xml"))),
                Frame(image: solidImage(width: 120, height: 150, rgb: 0x00FF00)),
                Frame(image: solidImage(width: 100, height: 200, rgb: 0x0000FF), facts: DeviceFacts(serial: "emulator-5554")),
            ],
            marks: [
                Mark(rect: CGRect(x: 10, y: 20, width: 30, height: 40), note: "rect on A", frame: 0),
                Mark(rect: CGRect(x: 120, y: 150, width: 0, height: 0), note: "pin in B's corner\n\n- still the note\n## not a heading", frame: 1),
                Mark(rect: CGRect(x: 50, y: 60, width: 0, height: 0), note: "pin on C", frame: 2),
                Mark(rect: CGRect(x: 0, y: 0, width: 100, height: 200), note: "all of A", frame: 0),
            ],
            refs: [solidImage(width: 20, height: 30), solidImage(width: 40, height: 10)],
            figmaURL: "https://www.figma.com/design/abc/Neku?node-id=128-22976"
        )
        let exported = try ReviewExporter.export(review, workspace: workspace, now: now)

        let loaded = try ReviewImporter.load(exported)

        XCTAssertEqual(loaded.marks, review.marks)
        XCTAssertEqual(loaded.frames.map(\.facts), review.frames.map(\.facts))
        XCTAssertEqual(loaded.frames.map(\.size), review.frames.map(\.size))
        for (actual, expected) in zip(loaded.frames, review.frames) {
            XCTAssertEqual(rgba(actual.image), rgba(expected.image))
        }
        XCTAssertEqual(loaded.refs.map(size), review.refs.map(size))
        XCTAssertEqual(loaded.figmaURL, review.figmaURL)

        let again = try ReviewExporter.export(loaded, workspace: workspace, now: now)
        XCTAssertEqual(try text(again, "review.md"), try text(exported, "review.md"))
    }

    func testV1RoundTripWithAndWithoutFacts() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let facts = DeviceFacts(serial: "6e9b5937", model: "MI 9", densityDpi: 440,
                                activity: "com.example/.ui.search.SearchActivity",
                                hierarchyXML: try fixture("golden-hierarchy", extension: "xml"))
        for facts in [facts, nil] {
            let review = Review(runtime: solidImage(width: 108, height: 234, rgb: 0x336699), facts: facts,
                                marks: [Mark(rect: CGRect(x: 20, y: 48, width: 0, height: 0), note: "字号偏小，加大一号")])
            let exported = try ReviewExporter.export(review, workspace: workspace, now: now)

            let loaded = try ReviewImporter.load(exported)

            XCTAssertEqual(loaded.frames.count, 1)
            XCTAssertEqual(loaded.facts, facts)
            XCTAssertEqual(loaded.marks, review.marks)
            XCTAssertEqual(rgba(loaded.runtime), rgba(review.runtime))
            XCTAssertEqual(try text(ReviewExporter.export(loaded, workspace: workspace, now: now), "review.md"),
                           try text(exported, "review.md"))
        }
    }

    func testDirectoriesFindsTheReviewItselfOrItsDirectChildren() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let review = Review(runtime: solidImage(width: 10, height: 10), marks: [Mark(rect: CGRect(x: 5, y: 5, width: 0, height: 0), note: "pin")])
        let first = try ReviewExporter.export(review, workspace: workspace, now: now)
        let second = try ReviewExporter.export(review, workspace: workspace, now: now.addingTimeInterval(1))
        let day = first.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: day.appendingPathComponent("screenshots"), withIntermediateDirectories: false)

        XCTAssertEqual(ReviewImporter.directories(in: first), [first])
        XCTAssertEqual(ReviewImporter.directories(in: day).map(\.lastPathComponent), [first, second].map(\.lastPathComponent))
        XCTAssertEqual(ReviewImporter.directories(in: workspace), [])
        XCTAssertEqual(ReviewImporter.directories(in: first.appendingPathComponent("runtime.png")), [])
    }

    func testRejectsBrokenOrHostileReviews() throws {
        let edits: [(String, (URL) throws -> Void)] = [
            ("missing review.md", { try FileManager.default.removeItem(at: $0.appendingPathComponent("review.md")) }),
            ("missing runtime.png", { try FileManager.default.removeItem(at: $0.appendingPathComponent("runtime.png")) }),
            ("unknown format", { try self.replace("uiboard-review/2", with: "uiboard-review/9", in: $0) }),
            ("unknown frame", { try self.replace("\n- frame: B", with: "\n- frame: Z", in: $0) }),
            ("rect outside frame", { try self.replace("- rect: 50,60,0,0", with: "- rect: 101,60,0,0", in: $0) }),
            ("negative rect", { try self.replace("- rect: 50,60,0,0", with: "- rect: 50,60,-1,0", in: $0) }),
            ("malformed rect", { try self.replace("- rect: 50,60,0,0", with: "- rect: 50,60,0", in: $0) }),
            ("frame outside runtime", { try self.replace("offset: 106,0", with: "offset: 9999,0", in: $0) }),
            ("path traversal", { try self.replace("hierarchy: hierarchy-A.xml", with: "hierarchy: ../hierarchy-A.xml", in: $0) }),
            ("missing hierarchy", { try FileManager.default.removeItem(at: $0.appendingPathComponent("hierarchy-A.xml")) }),
        ]
        for (name, edit) in edits {
            let workspace = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let review = Review(
                frames: [
                    Frame(image: solidImage(width: 100, height: 200),
                          facts: DeviceFacts(serial: "s", hierarchyXML: try fixture("golden-hierarchy", extension: "xml"))),
                    Frame(image: solidImage(width: 100, height: 200)),
                ],
                marks: [Mark(rect: CGRect(x: 50, y: 60, width: 0, height: 0), note: "pin", frame: 1)]
            )
            let exported = try ReviewExporter.export(review, workspace: workspace, now: now)
            XCTAssertNoThrow(try ReviewImporter.load(exported), name)
            try edit(exported)
            XCTAssertThrowsError(try ReviewImporter.load(exported), name) { error in
                guard case .importFailed = error as? UIBoardError else { return XCTFail("\(name): \(error)") }
            }
        }
    }

    private func replace(_ old: String, with new: String, in directory: URL) throws {
        let url = directory.appendingPathComponent("review.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(markdown.contains(old), "review.md has no “\(old)”")
        try markdown.replacingOccurrences(of: old, with: new).write(to: url, atomically: true, encoding: .utf8)
    }

    private func text(_ directory: URL, _ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    private func size(_ image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}
