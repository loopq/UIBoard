import AppKit
import UIBoardCore

enum UpdatePrompt {
    case available(Release)
    case failed(Release, String)
}

extension EditorModel {
    /// scripts/bundle.sh stamps release builds with X.Y.Z; local builds say "dev" (`swift run` has no Info.plist).
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    var isReleaseBuild: Bool { appVersion.wholeMatch(of: #/\d+\.\d+\.\d+/#) != nil }

    /// Automatic checks run at most once a day, stay silent unless there is an update, and skip dev builds.
    func checkForUpdates(manual: Bool) async {
        guard !isUpdating else { return }
        if !manual {
            let last = UserDefaults.standard.object(forKey: Prefs.lastUpdateCheck) as? Date ?? .distantPast
            guard isReleaseBuild, Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        }
        isUpdating = true
        defer { isUpdating = false }
        do {
            let release = try await Updates.latest(repo: Prefs.updateRepo)
            UserDefaults.standard.set(Date(), forKey: Prefs.lastUpdateCheck)
            if Updates.isNewer(release.version, than: appVersion) {
                updatePrompt = .available(release)
            } else if manual {
                show(isReleaseBuild ? "UIBoard \(appVersion) is up to date"
                                    : "Development build — the latest release is \(release.version)")
            }
        } catch {
            if manual { report(error) }
        }
    }

    func installUpdate(_ release: Release) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        show("Downloading UIBoard \(release.version)…")
        let app = Bundle.main.bundleURL
        do {
            try await Updates.install(release, over: app)
        } catch {
            updatePrompt = .failed(release, error.localizedDescription)
            return
        }
        relaunch(app, version: release.version)
    }

    /// The new bundle is already in place; a detached shell reopens it once this process has exited.
    private func relaunch(_ app: URL, version: String) {
        let installed = "Update installed — reopen UIBoard to use \(version)"
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\"",
                            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        do { try helper.run() } catch { return show(installed) }
        NSApp.terminate(nil)
        // terminate(_:) only returns when quitting was cancelled (unexported annotations); don't reopen later.
        helper.terminate()
        show(installed)
    }
}
