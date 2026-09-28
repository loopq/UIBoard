import CoreGraphics
import Foundation
import XCTest
@testable import UIBoardCore

final class BoardTests: XCTestCase {
    func testBoardLayoutPlacesFramesSideBySideTopAligned() {
        let sizes = [CGSize(width: 1080, height: 2400), CGSize(width: 1440, height: 3120)]
        XCTAssertEqual(BoardLayout.gap(for: sizes), 86)
        XCTAssertEqual(BoardLayout.offsets(for: sizes), [CGPoint(x: 0, y: 0), CGPoint(x: 1166, y: 0)])
        XCTAssertEqual(BoardLayout.size(for: sizes), CGSize(width: 2606, height: 3120))
        XCTAssertEqual(BoardLayout.size(for: [sizes[0]]), sizes[0])
    }

    func testComposePlacesFrameBAtItsOffsetAndFillsGaps() throws {
        let a = solidImage(width: 100, height: 200, rgb: 0xFF0000)
        let b = solidImage(width: 100, height: 100, rgb: 0x0000FF)
        let board = try XCTUnwrap(BoardComposer.compose([a, b]))
        XCTAssertEqual(board.width, 206)
        XCTAssertEqual(board.height, 200)
        XCTAssertEqual(pixel(board, x: 50, y: 150), [255, 0, 0, 255])
        XCTAssertEqual(pixel(board, x: 150, y: 50), [0, 0, 255, 255])
        XCTAssertEqual(pixel(board, x: 103, y: 50), [0xE5, 0xE5, 0xEA, 255])
        XCTAssertEqual(pixel(board, x: 150, y: 150), [0xE5, 0xE5, 0xEA, 255])
        XCTAssertTrue(BoardComposer.compose([a]) === a)
    }

    func testRendererDrawsOnlyTheRequestedFrameWithGlobalNumbering() throws {
        let marks = [
            Mark(rect: CGRect(x: 96, y: 412, width: 888, height: 180), frame: 0),
            Mark(rect: CGRect(x: 540, y: 1200, width: 0, height: 0), frame: 1),
        ]
        let white = solidImage(width: 1080, height: 2400, rgb: 0xFFFFFF)
        let frameB = try XCTUnwrap(AnnotationRenderer.render(runtime: white, marks: marks, frame: 1, highlight: nil))
        XCTAssertEqual(pixel(frameB, x: 96, y: 500), [255, 255, 255, 255])
        XCTAssertEqual(pixel(frameB, x: 616, y: 1104), [0x0A, 0x84, 0xFF, 255])
        let frameA = try XCTUnwrap(AnnotationRenderer.render(runtime: white, marks: marks, frame: 0, highlight: nil))
        XCTAssertEqual(pixel(frameA, x: 616, y: 1104), [255, 255, 255, 255])
        XCTAssertNotEqual(pixel(frameA, x: 96, y: 500), [255, 255, 255, 255])
    }

    func testMarkdownV2MatchesGoldenByteForByte() throws {
        let (review, created) = try goldenV2()
        let oldTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        defer { NSTimeZone.default = oldTimeZone }
        let hits = review.marks.map { mark in
            review.frames[mark.frame].facts?.hierarchyXML.map { HitTest.views(for: mark.rect, hierarchyXML: $0) } ?? []
        }
        let actual = Data(ReviewMarkdown.render(review, created: created, hits: hits).utf8)
        XCTAssertEqual(String(decoding: actual, as: UTF8.self), String(decoding: try fixture("golden-review-v2", extension: "md"), as: UTF8.self))
    }

    func testMultiFrameExportWritesBoardFilesAndPerFrameHierarchy() throws {
        let (review, created) = try goldenV2()
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let directory = try ReviewExporter.export(review, workspace: workspace, now: created)
        let names = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertEqual(names, ["review.md", "runtime.png", "annotated.png", "crops", "ref-1.png", "hierarchy-A.xml"])
        let crops = try Set(FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("crops").path))
        XCTAssertEqual(crops, ["1.png", "2.png", "3.png"])
        let runtime = try ImageIngest.decode(Data(contentsOf: directory.appendingPathComponent("runtime.png")))
        XCTAssertEqual(CGSize(width: runtime.width, height: runtime.height), CGSize(width: 2225, height: 2400))
        let markdown = try String(contentsOf: directory.appendingPathComponent("review.md"), encoding: .utf8)
        XCTAssertTrue(markdown.hasPrefix("---\nformat: uiboard-review/2\n"))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path)
        XCTAssertFalse(siblings.contains { $0.hasSuffix(".tmp") })
    }

    private func goldenV2() throws -> (Review, Date) {
        struct Input: Decodable {
            struct Facts: Decodable {
                let serial: String
                let model: String
                let densityDpi: Int
                let activity: String
                let hierarchy: String
            }
            struct InputFrame: Decodable {
                let size: [Int]
                let facts: Facts?
            }
            struct InputMark: Decodable {
                let frame: Int
                let rect: [Double]
                let note: String
            }
            let created: String
            let frames: [InputFrame]
            let figmaURL: String
            let refs: Int
            let marks: [InputMark]
        }
        let input = try JSONDecoder().decode(Input.self, from: fixture("golden-input-v2", extension: "json"))
        let frames = try input.frames.map { frame in
            Frame(
                image: solidImage(width: frame.size[0], height: frame.size[1]),
                facts: try frame.facts.map { facts in
                    DeviceFacts(
                        serial: facts.serial,
                        model: facts.model,
                        densityDpi: facts.densityDpi,
                        activity: facts.activity,
                        hierarchyXML: try fixture(facts.hierarchy.replacingOccurrences(of: ".xml", with: ""), extension: "xml")
                    )
                }
            )
        }
        let marks = input.marks.map {
            Mark(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]), note: $0.note, frame: $0.frame)
        }
        let review = Review(frames: frames, marks: marks,
                            refs: (0..<input.refs).map { _ in solidImage(width: 10, height: 10) },
                            figmaURL: input.figmaURL)
        return (review, try XCTUnwrap(ISO8601DateFormatter().date(from: input.created)))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }
}
