import Foundation

struct JiraSearchResponse: Codable, Sendable {
    let issues: [JiraIssue]
    let total: Int?
    let maxResults: Int?
    let startAt: Int?
}

struct JiraIssue: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let key: String
    let fields: JiraIssueFields

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JiraIssue, rhs: JiraIssue) -> Bool {
        lhs.id == rhs.id
    }
}

struct JiraIssueFields: Codable, Sendable {
    let summary: String
    let status: JiraStatus?
    let priority: JiraPriority?
    let assignee: JiraUser?
    let project: JiraProject?
    let issuetype: JiraIssueType?
    let timetracking: JiraTimeTracking?
}

struct JiraStatus: Codable, Sendable {
    let name: String
    let statusCategory: JiraStatusCategory?
}

struct JiraStatusCategory: Codable, Sendable {
    let key: String
    let name: String
    let colorName: String?
}

struct JiraPriority: Codable, Sendable {
    let name: String
    let iconUrl: String?
}

struct JiraUser: Codable, Sendable {
    let displayName: String
    let emailAddress: String?
}

struct JiraProject: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let key: String
    let name: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: JiraProject, rhs: JiraProject) -> Bool {
        lhs.id == rhs.id
    }
}

struct JiraIssueType: Codable, Sendable {
    let name: String
    let iconUrl: String?
}

struct JiraTransitionsResponse: Codable, Sendable {
    let transitions: [JiraTransition]
}

struct JiraTransition: Codable, Sendable {
    let id: String
    let name: String
    let to: JiraTransitionStatus
}

struct JiraTransitionStatus: Codable, Sendable {
    let id: String
    let name: String
    let statusCategory: JiraStatusCategory?
}

struct JiraTimeTracking: Codable, Sendable {
    let originalEstimate: String?
    let remainingEstimate: String?
    let timeSpent: String?
    let originalEstimateSeconds: Int?
    let remainingEstimateSeconds: Int?
    let timeSpentSeconds: Int?
}

extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    var shortDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
