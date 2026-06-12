import Foundation

@Observable
final class UpdateChecker {
    var updateAvailable: Bool = false
    var latestVersion: String = ""
    var releaseURL: String = ""
    var releaseNotes: String = ""

    private let currentVersion: String
    private let repoOwner = "danbasnett"
    private let repoName = "JiraTimeTracker"

    init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            await MainActor.run {
                if isNewer(remote: remoteVersion, current: currentVersion) {
                    latestVersion = remoteVersion
                    releaseURL = release.htmlUrl
                    releaseNotes = release.body ?? ""
                    updateAvailable = true
                } else {
                    updateAvailable = false
                }
            }
        } catch {
            // Silently fail — update check is non-critical
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

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}
