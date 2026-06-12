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
    private var pkgDownloadURL: String = ""
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

            // Find the .pkg asset (preferred) or .zip fallback
            let pkgAsset = release.assets?.first(where: { $0.name.hasSuffix(".pkg") })

            await MainActor.run {
                isChecking = false
                if isNewer(remote: remoteVersion, current: currentVersion) {
                    latestVersion = remoteVersion
                    releaseURL = release.htmlUrl
                    releaseNotes = release.body ?? ""
                    pkgDownloadURL = pkgAsset?.browserDownloadUrl ?? ""
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
        guard !pkgDownloadURL.isEmpty, let url = URL(string: pkgDownloadURL) else {
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
            // Download the .pkg to a temp location
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run {
                    isDownloading = false
                    lastCheckResult = "Download failed"
                }
                return
            }

            // Move to a named location so Finder shows the right name
            let fm = FileManager.default
            let downloadsDir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
            let pkgPath = downloadsDir.appendingPathComponent("JiraTimeTracker-\(latestVersion).pkg")

            // Remove any existing file at that path
            if fm.fileExists(atPath: pkgPath.path) {
                try fm.removeItem(at: pkgPath)
            }
            try fm.moveItem(at: tempURL, to: pkgPath)

            // Remove quarantine so Gatekeeper doesn't block it
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-d", "com.apple.quarantine", pkgPath.path]
            try? xattr.run()
            xattr.waitUntilExit()

            // Open the .pkg installer — macOS handles permissions, admin prompt, etc.
            // Then quit so the installer can replace the app in /Applications
            await MainActor.run {
                isDownloading = false
                NSWorkspace.shared.open(pkgPath)
                // Give the installer a moment to launch, then quit
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NSApplication.shared.terminate(nil)
                }
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
