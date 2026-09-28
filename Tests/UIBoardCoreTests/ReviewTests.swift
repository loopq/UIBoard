import CoreGraphics
import Foundation
import XCTest
@testable import UIBoardCore

final class ReviewTests: XCTestCase {
    func testImageRoundTripAndInvalidInput() throws {
        let encoded = try ImageIngest.png(solidImage(width: 12, height: 34))
        XCTAssertTrue(encoded.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let decoded = try ImageIngest.decode(encoded)
        XCTAssertEqual(decoded.width, 12)
        XCTAssertEqual(decoded.height, 34)
        XCTAssertThrowsError(try ImageIngest.decode(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? UIBoardError, .imageDecodeFailed)
        }
    }

    func testCropClampsAllCornersAndPinIsSquare() {
        let size = CGSize(width: 100, height: 200)
        XCTAssertEqual(Crop.rect(for: Mark(rect: CGRect(x: 0, y: 0, width: 5, height: 5)), in: size), CGRect(x: 0, y: 0, width: 15, height: 15))
        XCTAssertEqual(Crop.rect(for: Mark(rect: CGRect(x: 95, y: 0, width: 5, height: 5)), in: size), CGRect(x: 85, y: 0, width: 15, height: 15))
        XCTAssertEqual(Crop.rect(for: Mark(rect: CGRect(x: 0, y: 195, width: 5, height: 5)), in: size), CGRect(x: 0, y: 185, width: 15, height: 15))
        XCTAssertEqual(Crop.rect(for: Mark(rect: CGRect(x: 95, y: 195, width: 5, height: 5)), in: size), CGRect(x: 85, y: 185, width: 15, height: 15))
        XCTAssertEqual(Crop.rect(for: Mark(rect: CGRect(x: 50, y: 100, width: 0, height: 0)), in: size), CGRect(x: 40, y: 90, width: 20, height: 20))
    }

    func testRendererPreservesRuntimePixelSize() throws {
        let runtime = solidImage(width: 320, height: 640)
        let marks = [
            Mark(rect: CGRect(x: 20, y: 30, width: 100, height: 80)),
            Mark(rect: CGRect(x: 300, y: 20, width: 0, height: 0)),
        ]
        let rendered = try XCTUnwrap(AnnotationRenderer.render(runtime: runtime, marks: marks, highlight: 0))
        XCTAssertEqual(rendered.width, runtime.width)
        XCTAssertEqual(rendered.height, runtime.height)
    }

    func testRendererAndCropPreserveTopLeftImageCoordinates() throws {
        let pixels = Data([
            255, 0, 0, 255,
            0, 0, 255, 255,
        ])
        let image = try XCTUnwrap(CGImage(
            width: 1,
            height: 2,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: try XCTUnwrap(CGDataProvider(data: pixels as CFData)),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let rendered = try XCTUnwrap(AnnotationRenderer.render(runtime: image, marks: [], highlight: nil))
        let topCrop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let renderedTopCrop = try XCTUnwrap(rendered.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let bottomCrop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 1, width: 1, height: 1)))
        let renderedBottomCrop = try XCTUnwrap(rendered.cropping(to: CGRect(x: 0, y: 1, width: 1, height: 1)))
        XCTAssertEqual(rgba(renderedTopCrop), rgba(topCrop))
        XCTAssertEqual(rgba(renderedBottomCrop), rgba(bottomCrop))

        let cropPixels = try XCTUnwrap(topCrop.dataProvider?.data) as Data
        XCTAssertEqual(cropPixels.prefix(4), pixels.prefix(4))
    }

    func testRendererPlacesMarkUsingTopLeftCoordinates() throws {
        let rendered = try XCTUnwrap(AnnotationRenderer.render(
            runtime: solidImage(width: 200, height: 200, rgb: 0xFFFFFF),
            marks: [Mark(rect: CGRect(x: 50, y: 20, width: 100, height: 80))],
            highlight: nil
        ))
        let topBorder = try XCTUnwrap(rendered.cropping(to: CGRect(x: 100, y: 20, width: 1, height: 1)))
        let mirroredPosition = try XCTUnwrap(rendered.cropping(to: CGRect(x: 100, y: 179, width: 1, height: 1)))
        XCTAssertNotEqual(rgba(topBorder), [255, 255, 255, 255])
        XCTAssertEqual(rgba(mirroredPosition), [255, 255, 255, 255])
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }

    func testMarkdownMatchesGoldenByteForByte() throws {
        struct Input: Decodable {
            struct Facts: Decodable {
                let serial: String
                let model: String
                let densityDpi: Int
                let activity: String
                let hierarchy: String
            }
            struct InputMark: Decodable {
                let rect: [Double]
                let note: String
            }
            let size: [Int]
            let created: String
            let timeZone: String
            let facts: Facts
            let figmaURL: String
            let refs: Int
            let marks: [InputMark]
        }

        let input = try JSONDecoder().decode(Input.self, from: fixture("golden-input", extension: "json"))
        let oldTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: input.timeZone))
        defer { NSTimeZone.default = oldTimeZone }

        let hierarchy = try fixture("golden-hierarchy", extension: "xml")
        let runtime = solidImage(width: input.size[0], height: input.size[1])
        let marks = input.marks.map {
            Mark(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]), note: $0.note)
        }
        let review = Review(
            runtime: runtime,
            facts: DeviceFacts(
                serial: input.facts.serial,
                model: input.facts.model,
                densityDpi: input.facts.densityDpi,
                activity: input.facts.activity,
                hierarchyXML: hierarchy
            ),
            marks: marks,
            refs: (0..<input.refs).map { _ in solidImage(width: 10, height: 10) },
            figmaURL: input.figmaURL
        )
        let created = try XCTUnwrap(ISO8601DateFormatter().date(from: input.created))
        let hits = marks.map { HitTest.views(for: $0.rect, hierarchyXML: hierarchy) }
        let actual = Data(ReviewMarkdown.render(review, created: created, hits: hits).utf8)
        XCTAssertEqual(actual, try fixture("golden-review", extension: "md"))
    }

    func testMarkdownOmitsUnavailableAndEmptyFrontmatterFields() {
        let review = Review(
            runtime: solidImage(width: 100, height: 200),
            marks: [Mark(rect: CGRect(x: 10, y: 20, width: 30, height: 40), note: "note")]
        )
        let markdown = ReviewMarkdown.render(review, created: Date(timeIntervalSince1970: 0), hits: [[
            ViewHit(resourceId: "ignored", className: "View", bounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
        ]])
        for unavailable in ["source:", "device:", "density:", "activity:", "figma:", "refs:", "- dp:", "- views:"] {
            XCTAssertFalse(markdown.contains(unavailable), "Unexpected field: \(unavailable)")
        }
    }

    func testExporterWritesCompleteDirectoryWithoutTemporaryResidueAndHandlesCollision() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let hierarchy = try fixture("golden-hierarchy", extension: "xml")
        let review = Review(
            runtime: solidImage(width: 1080, height: 2400),
            facts: DeviceFacts(serial: "serial", hierarchyXML: hierarchy),
            marks: [
                Mark(rect: CGRect(x: 96, y: 412, width: 888, height: 180), note: "frame"),
                Mark(rect: CGRect(x: 675, y: 2266, width: 0, height: 0), note: "pin"),
            ],
            refs: [solidImage(width: 20, height: 30)]
        )
        let now = Date(timeIntervalSince1970: 1_790_275_742)
        let first = try ReviewExporter.export(review, workspace: workspace, now: now)
        let second = try ReviewExporter.export(review, workspace: workspace, now: now)
        XCTAssertEqual(second.lastPathComponent, first.lastPathComponent + "-2")

        let expected = [
            "annotated.png", "crops/1.png", "crops/2.png", "hierarchy.xml",
            "ref-1.png", "review.md", "runtime.png",
        ]
        for path in expected {
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.appendingPathComponent(path).path), path)
        }
        let dayEntries = try FileManager.default.contentsOfDirectory(atPath: first.deletingLastPathComponent().path)
        XCTAssertFalse(dayEntries.contains(where: { $0.hasPrefix(".") && $0.hasSuffix(".tmp") }))
    }

    func testExporterFailureDoesNotCreateFinalDirectory() throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: workspace)
        XCTAssertThrowsError(try ReviewExporter.export(
            Review(runtime: solidImage(width: 10, height: 10), marks: [Mark(rect: CGRect(x: 5, y: 5, width: 0, height: 0), note: "pin")]),
            workspace: workspace,
            now: Date()
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), ["not-a-directory"])
    }

    func testExporterCleansTemporaryDirectoryAfterMidExportFailure() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let now = Date(timeIntervalSince1970: 1_790_275_742)
        let review = Review(
            runtime: solidImage(width: 10, height: 10),
            marks: [Mark(rect: CGRect(x: 100, y: 100, width: 0, height: 0), note: "outside")]
        )
        XCTAssertThrowsError(try ReviewExporter.export(review, workspace: workspace, now: now))
        let day = workspace.appendingPathComponent("2026-09-24")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: day.path)) ?? []
        XCTAssertTrue(entries.isEmpty)
    }
}
