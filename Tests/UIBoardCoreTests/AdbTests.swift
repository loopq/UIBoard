import CoreGraphics
import Foundation
import XCTest
@testable import UIBoardCore

final class AdbTests: XCTestCase {
    func testAdbFixtureParsers() throws {
        XCTAssertEqual(AdbParsers.devices(try fixture("devices-l", extension: "txt", subdirectory: "adb")), [
            AdbDevice(id: "37091JEHN", model: "Pixel_7", state: "device"),
            AdbDevice(id: "emulator-5554", model: "sdk_gphone64_arm64", state: "device"),
            AdbDevice(id: "R5CW30ABCDE", model: nil, state: "unauthorized"),
            AdbDevice(id: "192.168.1.20:5555", model: nil, state: "offline"),
        ])
        XCTAssertEqual(AdbParsers.density(try fixture("wm-density-override", extension: "txt", subdirectory: "adb")), 480)
        XCTAssertEqual(AdbParsers.density(try fixture("wm-density-physical", extension: "txt", subdirectory: "adb")), 420)
        XCTAssertEqual(
            AdbParsers.activity(try fixture("dumpsys-activity", extension: "txt", subdirectory: "adb")),
            "com.stickermobi.avatarmaker/.ui.task.TaskCenterActivity"
        )
        let hierarchy = try XCTUnwrap(AdbParsers.hierarchy(try fixture("uiautomator-tty", extension: "txt", subdirectory: "adb")))
        XCTAssertTrue(String(decoding: hierarchy, as: UTF8.self).hasSuffix("</hierarchy>"))
        XCTAssertFalse(String(decoding: hierarchy, as: UTF8.self).contains("dumped to"))
    }

    func testHitTestRanksFramePinAndExcludesAndroidIds() throws {
        let hierarchy = try fixture("golden-hierarchy", extension: "xml")
        let frame = HitTest.views(for: CGRect(x: 96, y: 412, width: 888, height: 180), hierarchyXML: hierarchy)
        XCTAssertEqual(frame.map(\.resourceId), [
            "com.stickermobi.avatarmaker:id/rewards_tab",
            "com.stickermobi.avatarmaker:id/bonus_tab",
            "com.stickermobi.avatarmaker:id/tab_track",
        ])
        let pin = HitTest.views(for: CGRect(x: 675, y: 2266, width: 0, height: 0), hierarchyXML: hierarchy)
        XCTAssertEqual(pin.first?.resourceId, "com.stickermobi.avatarmaker:id/nav_create_icon")
        XCTAssertTrue(HitTest.views(for: CGRect(x: 900, y: 40, width: 0, height: 0), hierarchyXML: hierarchy).isEmpty)
    }

    func testLocateUsesExecutableOverride() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("adb")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertEqual(Adb.locate(override: executable.path), executable)
        XCTAssertNotEqual(Adb.locate(override: directory.appendingPathComponent("missing").path), directory.appendingPathComponent("missing"))
    }

    func testProcessRunnerDrainsLargeOutput() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: ["-c", "head -c 1200000 /dev/zero; head -c 1200000 /dev/zero >&2"],
            timeout: 5
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.count, 1_200_000)
        XCTAssertEqual(result.stderr.count, 1_200_000)
    }

    func testProcessRunnerTimesOutAndTerminates() async throws {
        let start = Date()
        do {
            _ = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                args: ["5"],
                timeout: 1
            )
            XCTFail("Expected timeout")
        } catch let error as UIBoardError {
            guard case .timeout = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testAdbPublicOperationsAndIndependentFacts() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fakeAdb = directory.appendingPathComponent("fake-adb")
        let script = """
        #!/bin/sh
        case "$*" in
          "devices -l") printf 'List of devices attached\\nserial device model:Pixel_7\\n' ;;
          *"bad"*"screencap -p") printf 'bad screenshot' ;;
          *"screencap -p") printf '\\211PNGpayload' ;;
          *"failure"*"wm density") exit 2 ;;
          *"failure"*"dumpsys activity activities"*) printf 'topResumedActivity=x com.example/.MainActivity y\\n' ;;
          *"failure"*"uiautomator dump /dev/tty") printf '<hierarchy></hierarchy>trailer' ;;
          *"wm density") sleep 1; printf 'Physical density: 420\\nOverride density: 480\\n' ;;
          *"dumpsys activity activities"*) sleep 1; printf 'topResumedActivity=x com.example/.MainActivity y\\n' ;;
          *"uiautomator dump /dev/tty") sleep 1; printf '<hierarchy></hierarchy>trailer' ;;
          *) exit 2 ;;
        esac
        """
        try Data(script.utf8).write(to: fakeAdb)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeAdb.path)

        let adb = Adb(executable: fakeAdb)
        let devices = try await adb.devices()
        let screenshot = try await adb.screencap(serial: "serial")
        XCTAssertEqual(devices, [AdbDevice(id: "serial", model: "Pixel_7", state: "device")])
        XCTAssertTrue(screenshot.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        do {
            _ = try await adb.screencap(serial: "bad")
            XCTFail("Expected non-PNG screenshot error")
        } catch let error as UIBoardError {
            XCTAssertEqual(error, .notPNG)
        }
        let factsStart = Date()
        let facts = await adb.facts(serial: "serial", model: "Pixel_7")
        XCTAssertLessThan(Date().timeIntervalSince(factsStart), 2.5)
        XCTAssertEqual(facts.serial, "serial")
        XCTAssertEqual(facts.model, "Pixel_7")
        XCTAssertEqual(facts.densityDpi, 480)
        XCTAssertEqual(facts.activity, "com.example/.MainActivity")
        XCTAssertEqual(facts.hierarchyXML, Data("<hierarchy></hierarchy>".utf8))

        let partialFacts = await adb.facts(serial: "failure", model: nil)
        XCTAssertNil(partialFacts.densityDpi)
        XCTAssertEqual(partialFacts.activity, "com.example/.MainActivity")
        XCTAssertEqual(partialFacts.hierarchyXML, Data("<hierarchy></hierarchy>".utf8))
    }
}
