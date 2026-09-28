import Foundation

enum AdbParsers {
    static func devices(_ data: Data) -> [AdbDevice] {
        lines(data).dropFirst().compactMap { line in
            let fields = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return nil }
            let model = fields.dropFirst(2)
                .first(where: { $0.hasPrefix("model:") })
                .map { String($0.dropFirst("model:".count)) }
            return AdbDevice(id: fields[0], model: model, state: fields[1])
        }
    }

    static func density(_ data: Data) -> Int? {
        let values = lines(data).compactMap { line -> (override: Bool, value: Int)? in
            let isOverride = line.contains("Override density:")
            guard isOverride || line.contains("Physical density:") else { return nil }
            guard let value = line.split(separator: ":").last.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else {
                return nil
            }
            return (isOverride, value)
        }
        return values.first(where: \.override)?.value ?? values.first?.value
    }

    static func activity(_ data: Data) -> String? {
        for line in lines(data) {
            for field in line.split(whereSeparator: \Character.isWhitespace) {
                let token = field.trimmingCharacters(in: CharacterSet(charactersIn: "{}[](),"))
                if token.contains("/") { return token }
            }
        }
        return nil
    }

    static func hierarchy(_ data: Data) -> Data? {
        let closing = Data("</hierarchy>".utf8)
        guard let range = data.range(of: closing) else { return nil }
        return data[data.startIndex..<range.upperBound]
    }

    private static func lines(_ data: Data) -> [Substring] {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
    }
}

struct AdbImplementation {
    let executable: URL

    static func locate(override: String?) -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var paths: [String] = []
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paths.append((override as NSString).expandingTildeInPath)
        }
        if let androidHome = environment["ANDROID_HOME"], !androidHome.isEmpty {
            paths.append(URL(fileURLWithPath: androidHome).appendingPathComponent("platform-tools/adb").path)
        }
        paths += [
            ("~/Library/Android/sdk/platform-tools/adb" as NSString).expandingTildeInPath,
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
        return paths.lazy
            .map { URL(fileURLWithPath: $0) }
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    func devices() async throws -> [AdbDevice] {
        let result = try await checkedRun(args: ["devices", "-l"], timeout: 5)
        return AdbParsers.devices(result)
    }

    func screencap(serial: String) async throws -> Data {
        let data = try await checkedRun(args: ["-s", serial, "exec-out", "screencap", "-p"], timeout: 10)
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { throw UIBoardError.notPNG }
        return data
    }

    func facts(serial: String, model: String?) async -> DeviceFacts {
        async let density = optional(args: ["-s", serial, "shell", "wm", "density"], timeout: 3, parser: AdbParsers.density)
        async let activity = optional(
            args: ["-s", serial, "shell", "dumpsys activity activities | grep -E 'topResumedActivity|mResumedActivity'"],
            timeout: 5,
            parser: AdbParsers.activity
        )
        async let hierarchy = optional(
            args: ["-s", serial, "exec-out", "uiautomator", "dump", "/dev/tty"],
            timeout: 8,
            parser: AdbParsers.hierarchy
        )
        return await DeviceFacts(
            serial: serial,
            model: model,
            densityDpi: density,
            activity: activity,
            hierarchyXML: hierarchy
        )
    }

    private func checkedRun(args: [String], timeout: TimeInterval) async throws -> Data {
        let result = try await ProcessRunner.run(executable: executable, args: args, timeout: timeout)
        guard result.status == 0 else {
            throw UIBoardError.processFailed(
                status: result.status,
                stderr: String(decoding: result.stderr, as: UTF8.self)
            )
        }
        return result.stdout
    }

    private func optional<T>(
        args: [String],
        timeout: TimeInterval,
        parser: @escaping (Data) -> T?
    ) async -> T? {
        do {
            return parser(try await checkedRun(args: args, timeout: timeout))
        } catch {
            return nil
        }
    }
}
