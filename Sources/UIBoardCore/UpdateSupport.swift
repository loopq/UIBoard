import Foundation

enum UpdateImplementation {
    /// Asset name is fixed by scripts/release.sh, so releases/latest/download/UIBoard.zip always resolves.
    static let assetName = "UIBoard.zip"
    static let appName = "UIBoard.app"

    static func feed(repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    static func latest(from feed: URL) async throws -> Release {
        var request = URLRequest(url: feed, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try release(from: try await fetch(request))
    }

    static func release(from data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw UIBoardError.updateFailed("Unexpected response from GitHub.")
        }
        guard let asset = payload.assets.first(where: { $0.name == assetName }) else {
            throw UIBoardError.updateFailed("Release \(payload.tag_name) has no \(assetName).")
        }
        let tag = payload.tag_name
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       page: payload.html_url, asset: asset.browser_download_url)
    }

    /// Strict X.Y.Z. Anything else (local "dev" builds, two-part "0.1", pre-release suffixes) has no order.
    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in part.allSatisfy { ("0"..."9").contains($0) } ? Int(part) : nil }
        return parts.count == 3 && numbers.count == 3 ? numbers : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        return old.lexicographicallyPrecedes(new)
    }

    /// Trust ceiling: HTTPS plus the GitHub repo owner. An ad-hoc signature proves the bundle is intact, not who
    /// built it. Upgrade path: Developer ID + notarization, or an EdDSA signature on the zip checked here.
    static func install(_ release: Release, over app: URL) async throws {
        let fileManager = FileManager.default
        // Same volume as the target, so the final swap is an atomic rename.
        let work = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                       appropriateFor: app, create: true)
        defer { try? fileManager.removeItem(at: work) }

        let zip = work.appendingPathComponent(assetName)
        try await fetch(URLRequest(url: release.asset, timeoutInterval: 120)).write(to: zip)
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        // --noqtn: never carry a quarantine flag onto the installed app (Gatekeeper has no bypass for it on macOS 15).
        try await run("/usr/bin/ditto", ["-x", "-k", "--noqtn", zip.path, extracted.path])
        let staged = extracted.appendingPathComponent(appName)

        let new = info(staged)
        guard let id = new["CFBundleIdentifier"] as? String, id == info(app)["CFBundleIdentifier"] as? String else {
            throw UIBoardError.updateFailed("The download is not a UIBoard app.")
        }
        let version = new["CFBundleShortVersionString"] as? String ?? "unknown"
        guard version == release.version else {
            throw UIBoardError.updateFailed("The download is version \(version), expected \(release.version).")
        }
        try await run("/usr/bin/codesign", ["--verify", "--strict", staged.path])
        _ = try fileManager.replaceItemAt(app, withItemAt: staged)
    }

    /// Reads Info.plist directly: Bundle(url:) caches per path and would keep serving the replaced app's values.
    private static func info(_ app: URL) -> [String: Any] {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dictionary
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UIBoardError.updateFailed("\(request.url?.host ?? "Server") returned HTTP \(http.statusCode).")
        }
        return data
    }

    private static func run(_ tool: String, _ args: [String]) async throws {
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: tool), args: args, timeout: 60)
        guard result.status == 0 else {
            throw UIBoardError.updateFailed(String(decoding: result.stderr, as: UTF8.self))
        }
    }
}
