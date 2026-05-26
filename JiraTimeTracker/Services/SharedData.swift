import Foundation
import CloudKit
#if canImport(ActivityKit)
import ActivityKit
#endif

struct SharedTimerData: Codable {
    let issueKey: String
    let issueSummary: String
    let startTime: Date
}

#if os(iOS)
struct TimerActivityAttributes: ActivityAttributes {
    let issueKey: String
    let issueSummary: String
    let startTime: Date

    struct ContentState: Codable, Hashable {
        let isRunning: Bool
    }
}
#endif

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

    static func syncTimerFromCloud() async -> SharedTimerData? {
        let database = CKContainer.default().privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "activeTimer")
        do {
            let record = try await database.record(for: recordID)
            guard let isActive = record["isActive"] as? Int64, isActive == 1,
                  let issueKey = record["issueKey"] as? String,
                  let issueSummary = record["issueSummary"] as? String,
                  let startTime = record["startTime"] as? Date else {
                saveTimerState(nil)
                return nil
            }
            let timer = SharedTimerData(issueKey: issueKey, issueSummary: issueSummary, startTime: startTime)
            saveTimerState(timer)
            return timer
        } catch {
            return loadTimerState()
        }
    }
}
