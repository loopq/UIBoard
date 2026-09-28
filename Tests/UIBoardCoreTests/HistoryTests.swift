import Foundation
import XCTest
@testable import UIBoardCore

final class HistoryTests: XCTestCase {
    func testScanFiltersIncompleteAndInvalidDirectoriesAndSortsDescending() throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        try makeReview(workspace, day: "2026-09-27", time: "08-00-00")
        try makeReview(workspace, day: "2026-09-28", time: "09-00-00")
        try makeReview(workspace, day: "2026-09-28", time: "09-00-00-2")
        try makeReview(workspace, day: "2026-09-28", time: "09-00-00-10")
        try makeReview(workspace, day: "2026-09-28", time: ".09-00-01.tmp")
        try makeDirectory(workspace, day: "2026-09-28", time: "10-00-00")
        try makeReview(workspace, day: "2026-09-28", time: "bad-name")
        try makeReview(workspace, day: "not-a-date", time: "11-00-00")

        let result = HistoryScanner.scan(workspace: workspace)
        XCTAssertEqual(result.map(\.date), ["2026-09-28", "2026-09-27"])
        XCTAssertEqual(result[0].items.map(\.time), ["09-00-00-10", "09-00-00-2", "09-00-00"])
        XCTAssertEqual(result[1].items.map(\.time), ["08-00-00"])
    }

    private func makeReview(_ workspace: URL, day: String, time: String) throws {
        let directory = try makeDirectory(workspace, day: day, time: time)
        try Data("review".utf8).write(to: directory.appendingPathComponent("review.md"))
    }

    @discardableResult
    private func makeDirectory(_ workspace: URL, day: String, time: String) throws -> URL {
        let directory = workspace.appendingPathComponent(day).appendingPathComponent(time)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
