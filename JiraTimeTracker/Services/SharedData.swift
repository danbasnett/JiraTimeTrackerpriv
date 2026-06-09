import Foundation

struct SharedTimerData: Codable {
    let issueKey: String
    let issueSummary: String
    let startTime: Date
}

struct SharedIssueData: Codable {
    let key: String
    let summary: String
    let statusName: String?
}

enum SharedData {
    static let appGroupID = "group.danbasnett.JiraTimeTracker"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func saveTimerState(_ timer: SharedTimerData?) {
        guard let defaults = defaults else { return }
        if let timer = timer {
            if let data = try? JSONEncoder().encode(timer) {
                defaults.set(data, forKey: "activeTimer")
            }
        } else {
            defaults.removeObject(forKey: "activeTimer")
        }
        defaults.synchronize()
    }

    static func loadTimerState() -> SharedTimerData? {
        guard let defaults = defaults,
              let data = defaults.data(forKey: "activeTimer") else { return nil }
        return try? JSONDecoder().decode(SharedTimerData.self, from: data)
    }

    static func saveRecentIssues(_ issues: [SharedIssueData]) {
        guard let defaults = defaults else { return }
        if let data = try? JSONEncoder().encode(issues) {
            defaults.set(data, forKey: "recentIssues")
        }
    }

    static func loadRecentIssues() -> [SharedIssueData] {
        guard let defaults = defaults,
              let data = defaults.data(forKey: "recentIssues") else { return [] }
        return (try? JSONDecoder().decode([SharedIssueData].self, from: data)) ?? []
    }

    static func saveIssueCount(_ count: Int) {
        defaults?.set(count, forKey: "openIssueCount")
    }

    static func loadIssueCount() -> Int {
        defaults?.integer(forKey: "openIssueCount") ?? 0
    }
}
