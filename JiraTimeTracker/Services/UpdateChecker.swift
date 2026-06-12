import Foundation
import AppKit

@Observable
final class UpdateChecker {
    var updateAvailable: Bool = false
    var isChecking: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
    var lastCheckResult: String?
    var latestVersion: String = ""
    var releaseURL: String = ""
    var releaseNotes: String = ""

    private let currentVersion: String
    private let repoOwner = "danbasnett"
    private let repoName = "JiraTimeTracker"
    private var zipDownloadURL: String = ""
    private var periodicTask: Task<Void, Never>?

    init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func startPeriodicChecks() {
        periodicTask?.cancel()
        periodicTask = Task {
            // Check immediately on launch
            await checkForUpdates()

            // Then every 15 minutes
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled else { break }
                await checkForUpdates()
            }
        }
    }

    func checkForUpdates() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        await MainActor.run {
            isChecking = true
            lastCheckResult = nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run {
                    isChecking = false
                    lastCheckResult = "Could not check for updates"
                }
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            // Find the .zip asset
            let zipAsset = release.assets?.first(where: { $0.name.hasSuffix(".zip") })

            await MainActor.run {
                isChecking = false
                if isNewer(remote: remoteVersion, current: currentVersion) {
                    latestVersion = remoteVersion
                    releaseURL = release.htmlUrl
                    releaseNotes = release.body ?? ""
                    zipDownloadURL = zipAsset?.browserDownloadUrl ?? ""
                    updateAvailable = true
                    lastCheckResult = nil
                } else {
                    updateAvailable = false
                    lastCheckResult = "You're up to date"
                }
            }
        } catch {
            await MainActor.run {
                isChecking = false
                lastCheckResult = "Could not check for updates"
            }
        }
    }

    func downloadAndInstall() async {
        guard !zipDownloadURL.isEmpty, let url = URL(string: zipDownloadURL) else {
            await MainActor.run {
                lastCheckResult = "No download available"
            }
            return
        }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
            lastCheckResult = nil
        }

        do {
            // Download to temp
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run {
                    isDownloading = false
                    lastCheckResult = "Download failed"
                }
                return
            }

            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory.appendingPathComponent("JiraTimeTrackerUpdate-\(UUID().uuidString)")
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Move downloaded zip
            let zipPath = tempDir.appendingPathComponent("JiraTimeTracker.zip")
            if fm.fileExists(atPath: zipPath.path) {
                try fm.removeItem(at: zipPath)
            }
            try fm.moveItem(at: tempURL, to: zipPath)

            // Remove quarantine attribute from the zip
            let xattrZip = Process()
            xattrZip.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrZip.arguments = ["-d", "com.apple.quarantine", zipPath.path]
            try? xattrZip.run()
            xattrZip.waitUntilExit()

            // Unzip
            let unzipDir = tempDir.appendingPathComponent("extracted")
            try fm.createDirectory(at: unzipDir, withIntermediateDirectories: true)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipPath.path, unzipDir.path]
            try unzip.run()
            unzip.waitUntilExit()

            guard unzip.terminationStatus == 0 else {
                await MainActor.run {
                    isDownloading = false
                    lastCheckResult = "Failed to extract update"
                }
                return
            }

            // Find the .app — check both top level and one level deep
            let newApp: URL? = try {
                let topLevel = try fm.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
                if let app = topLevel.first(where: { $0.lastPathComponent.hasSuffix(".app") }) {
                    return app
                }
                // Check one level deeper (some zips nest in a folder)
                for dir in topLevel where dir.hasDirectoryPath {
                    let nested = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                    if let app = nested.first(where: { $0.lastPathComponent.hasSuffix(".app") }) {
                        return app
                    }
                }
                return nil
            }()

            guard let newApp else {
                await MainActor.run {
                    isDownloading = false
                    lastCheckResult = "Update package invalid"
                }
                return
            }

            // Remove quarantine from extracted app
            let xattrApp = Process()
            xattrApp.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrApp.arguments = ["-r", "-d", "com.apple.quarantine", newApp.path]
            try? xattrApp.run()
            xattrApp.waitUntilExit()

            // Resolve the real app path (handles App Translocation)
            let currentAppPath = resolveAppPath()
            let newAppPath = newApp.path

            let logFile = tempDir.appendingPathComponent("update.log").path
            let pid = ProcessInfo.processInfo.processIdentifier

            let esc = { (s: String) in s.replacingOccurrences(of: "'", with: "'\\''") }

            let script = """
            exec > '\(esc(logFile))' 2>&1
            echo "Update started at $(date)"
            echo "PID to wait for: \(pid)"
            echo "Current app: \(esc(currentAppPath))"
            echo "New app: \(esc(newAppPath))"

            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            echo "App exited, replacing..."

            rm -rf '\(esc(currentAppPath))'
            if [ $? -ne 0 ]; then echo "ERROR: rm failed"; exit 1; fi

            cp -R '\(esc(newAppPath))' '\(esc(currentAppPath))'
            if [ $? -ne 0 ]; then echo "ERROR: cp failed"; exit 1; fi

            echo "Launching updated app..."
            sleep 0.5
            open '\(esc(currentAppPath))'

            echo "Cleaning up temp dir..."
            rm -rf '\(esc(tempDir.path))'
            echo "Done"
            """

            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/bash")
            helper.arguments = ["-c", script]
            try helper.run()

            // Quit the app so the helper can replace it
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            await MainActor.run {
                isDownloading = false
                lastCheckResult = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    /// Resolve the real app bundle path, handling macOS App Translocation.
    /// When an app is opened from a quarantined location, macOS copies it to a
    /// randomized read-only path. We need to find the original location to replace it.
    private func resolveAppPath() -> String {
        let bundlePath = Bundle.main.bundlePath

        // Check if we're in a translocated path
        // Translocated paths look like: /private/var/folders/.../AppTranslocation/.../d/JiraTimeTracker.app
        if bundlePath.contains("/AppTranslocation/") {
            // Try to find the app in /Applications first
            let appName = (bundlePath as NSString).lastPathComponent
            let applicationsPath = "/Applications/\(appName)"
            if FileManager.default.fileExists(atPath: applicationsPath) {
                return applicationsPath
            }
            // Try user Applications
            let userAppsPath = NSHomeDirectory() + "/Applications/\(appName)"
            if FileManager.default.fileExists(atPath: userAppsPath) {
                return userAppsPath
            }
        }

        // Not translocated — use the bundle path as-is
        return bundlePath
    }

    private func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, c.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}

private struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case assets
    }
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}
