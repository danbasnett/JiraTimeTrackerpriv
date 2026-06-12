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

            // Find the .app in extracted directory
            let contents = try fm.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.lastPathComponent.hasSuffix(".app") }) else {
                await MainActor.run {
                    isDownloading = false
                    lastCheckResult = "Update package invalid"
                }
                return
            }

            let currentAppPath = Bundle.main.bundlePath
            let newAppPath = newApp.path

            // Build a script that:
            // 1. Waits for this process to exit
            // 2. Replaces the app
            // 3. Relaunches it
            // 4. Cleans up the temp directory
            let pid = ProcessInfo.processInfo.processIdentifier
            let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf '\(currentAppPath.replacingOccurrences(of: "'", with: "'\\''"))'
            cp -R '\(newAppPath.replacingOccurrences(of: "'", with: "'\\''"))' '\(currentAppPath.replacingOccurrences(of: "'", with: "'\\''"))'
            open '\(currentAppPath.replacingOccurrences(of: "'", with: "'\\''"))'
            rm -rf '\(tempDir.path.replacingOccurrences(of: "'", with: "'\\''"))'
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
