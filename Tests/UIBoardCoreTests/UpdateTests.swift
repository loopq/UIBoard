import Foundation
import XCTest
@testable import UIBoardCore

final class UpdateTests: XCTestCase {
    func testIsNewerOrdersOnlyStrictThreePartVersions() {
        XCTAssertTrue(Updates.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(Updates.isNewer("0.1.1", than: "0.1.0"))
        XCTAssertTrue(Updates.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(Updates.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(Updates.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(Updates.isNewer("0.1.0", than: "0.2.0"))
        for other in ["dev", "0.1", "", "0.2.0-beta", "v0.2.0", "0..1", "1.2.3.4", "-1.0.0"] {
            XCTAssertFalse(Updates.isNewer("9.9.9", than: other), other)
            XCTAssertFalse(Updates.isNewer(other, than: "0.0.1"), other)
        }
    }

    func testLatestReadsVersionPageAndAssetFromGitHubPayload() async throws {
        let feed = try XCTUnwrap(Bundle.module.url(forResource: "release-latest", withExtension: "json",
                                                   subdirectory: "Fixtures"))
        let release = try await UpdateImplementation.latest(from: feed)
        XCTAssertEqual(release, Release(
            version: "1.0.0",
            page: URL(string: "https://github.com/loopq/UIBoard/releases/tag/v1.0.0")!,
            asset: URL(string: "https://github.com/loopq/UIBoard/releases/download/v1.0.0/UIBoard.zip")!
        ))
    }

    func testLatestRejectsReleaseWithoutAppZip() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: fixture("release-latest", extension: "json")) as? [String: Any])
        payload["assets"] = []
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try UpdateImplementation.release(from: data)) { error in
            XCTAssertEqual(error as? UIBoardError, .updateFailed("Release v1.0.0 has no UIBoard.zip."))
        }
    }

    func testInstallReplacesAppWithDownloadedRelease() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.1.0")
        let build = try makeApp(in: root.appendingPathComponent("build"), version: "0.2.0")

        try await Updates.install(publish(build, as: "0.2.0", in: root), over: target)

        XCTAssertEqual(version(of: target), "0.2.0")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path),
                       ["UIBoard.app"])
    }

    func testInstallRejectsMismatchedOrTamperedDownloadAndKeepsTarget() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try makeApp(in: root.appendingPathComponent("Applications"), version: "0.1.0")

        let wrongVersion = try makeApp(in: root.appendingPathComponent("a"), version: "0.2.0")
        let otherApp = try makeApp(in: root.appendingPathComponent("b"), id: "com.example.other", version: "0.2.0")
        let tampered = try makeApp(in: root.appendingPathComponent("c"), version: "0.2.0")
        let executable = try FileHandle(forWritingTo: tampered.appendingPathComponent("Contents/MacOS/UIBoard"))
        try executable.seekToEnd()
        try executable.write(contentsOf: Data("tampered".utf8))
        try executable.close()

        let cases: [(app: URL, version: String, reason: String)] = [
            (wrongVersion, "0.3.0", "The download is version 0.2.0, expected 0.3.0."),
            (otherApp, "0.2.0", "The download is not a UIBoard app."),
            (tampered, "0.2.0", "failed strict validation"),
        ]
        for (index, item) in cases.enumerated() {
            let release = try publish(item.app, as: item.version, in: root.appendingPathComponent("release-\(index)"))
            do {
                try await Updates.install(release, over: target)
                XCTFail("installed a bad download: \(item.reason)")
            } catch let UIBoardError.updateFailed(message) {
                XCTAssertTrue(message.contains(item.reason), message)
            }
            XCTAssertEqual(version(of: target), "0.1.0", item.reason)
        }
    }

    // MARK: Helpers

    private func makeApp(in directory: URL, id: String = "com.loopq.uiboard", version: String) throws -> URL {
        let app = directory.appendingPathComponent("UIBoard.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                        to: macOS.appendingPathComponent("UIBoard"))
        let info: [String: Any] = [
            "CFBundleIdentifier": id,
            "CFBundleExecutable": "UIBoard",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try shell("/usr/bin/codesign", "--force", "-s", "-", app.path)
        return app
    }

    /// Zips the app the way scripts/release.sh does and points the release at it with a file:// URL.
    private func publish(_ app: URL, as version: String, in directory: URL) throws -> Release {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appendingPathComponent("UIBoard.zip")
        try shell("/usr/bin/ditto", "-c", "-k", "--keepParent", app.path, zip.path)
        return Release(version: version, page: URL(string: "https://example.com/release")!, asset: zip)
    }

    private func version(of app: URL) -> String? {
        let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        return info?["CFBundleShortVersionString"] as? String
    }

    private func shell(_ tool: String, _ args: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(args.joined(separator: " "))")
    }
}
