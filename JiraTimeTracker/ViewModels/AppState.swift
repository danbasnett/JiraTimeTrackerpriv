import Foundation
import SwiftUI
import WidgetKit

@Observable
final class AppState {
    // MARK: - Configuration

    var jiraBaseURL: String = ""
    var jiraEmail: String = ""
    var jiraAPIToken: String = ""
    var isConfigured: Bool { !jiraBaseURL.isEmpty && !jiraEmail.isEmpty && !jiraAPIToken.isEmpty }

    // MARK: - Data

    var issues: [JiraIssue] = []
    var projects: [JiraProject] = []
    var currentUser: JiraUser?

    // MARK: - Search & Filter

    var searchText: String = ""
    var selectedProjectKey: String?
    var statusFilter: StatusFilter = .open
    var selectedStatusName: String?
    var assignedToMe: Bool = true

    enum StatusFilter: String, CaseIterable {
        case open = "Open"
        case all = "All"
        case done = "Done"
    }

    var availableStatuses: [String] {
        let names = Set(issues.compactMap { $0.fields.status?.name })
        return names.sorted()
    }

    var filteredIssues: [JiraIssue] {
        guard let statusName = selectedStatusName, !statusName.isEmpty else {
            return issues
        }
        return issues.filter { $0.fields.status?.name == statusName }
    }

    // MARK: - Timer

    var activeTimerIssue: JiraIssue?
    var activeTimerStart: Date?
    var timerPauseStart: Date?
    var timerAccumulatedPause: TimeInterval = 0
    var isTimerRunning: Bool { activeTimerIssue != nil && activeTimerStart != nil }
    var isTimerPaused: Bool { timerPauseStart != nil }

    /// The effective start date shifted forward by total pause time, for use with `Text(date, style: .timer)`
    var effectiveTimerStart: Date? {
        guard let start = activeTimerStart else { return nil }
        var totalPause = timerAccumulatedPause
        if let pauseStart = timerPauseStart {
            totalPause += Date().timeIntervalSince(pauseStart)
        }
        return start.addingTimeInterval(totalPause)
    }

    /// Current effective elapsed seconds (accounting for pauses)
    var effectiveElapsedSeconds: Int {
        guard let start = activeTimerStart else { return 0 }
        var totalPause = timerAccumulatedPause
        if let pauseStart = timerPauseStart {
            totalPause += Date().timeIntervalSince(pauseStart)
        }
        return max(0, Int(Date().timeIntervalSince(start) - totalPause))
    }

    // MARK: - Settings

    var autoTransitionOnStart: Bool = UserDefaults.standard.bool(forKey: "autoTransitionOnStart")

    // MARK: - UI State

    var isLoading: Bool = false
    var isLoggingTime: Bool = false
    var errorMessage: String?
    var successMessage: String?
    var showSettings: Bool = false
    var workDescription: String = ""

    // MARK: - Private

    private var apiClient: JiraAPIClient?

    init() {
        loadCredentials()
        loadTimerState()
        loadFilterState()
    }

    // MARK: - Credentials

    func loadCredentials() {
        jiraBaseURL = KeychainService.load(key: "jira_base_url") ?? ""
        jiraEmail = KeychainService.load(key: "jira_email") ?? ""
        jiraAPIToken = KeychainService.load(key: "jira_api_token") ?? ""
        if isConfigured {
            configureClient()
        }
    }

    func saveCredentials() throws {
        try KeychainService.save(key: "jira_base_url", value: jiraBaseURL)
        try KeychainService.save(key: "jira_email", value: jiraEmail)
        try KeychainService.save(key: "jira_api_token", value: jiraAPIToken)
        configureClient()
    }

    func clearCredentials() {
        KeychainService.delete(key: "jira_base_url")
        KeychainService.delete(key: "jira_email")
        KeychainService.delete(key: "jira_api_token")
        jiraBaseURL = ""
        jiraEmail = ""
        jiraAPIToken = ""
        apiClient = nil
        issues = []
        projects = []
        currentUser = nil
    }

    private func configureClient() {
        apiClient = JiraAPIClient(
            baseURL: jiraBaseURL,
            email: jiraEmail,
            apiToken: jiraAPIToken
        )
    }

    // MARK: - API Calls

    func fetchIssues() async {
        guard let client = apiClient else { return }
        isLoading = true
        errorMessage = nil
        do {
            let jql = buildJQL()
            let response = try await client.searchIssues(jql: jql)
            issues = response.issues
            syncSharedIssueData()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func fetchProjects() async {
        guard let client = apiClient else { return }
        do {
            projects = try await client.getProjects()
        } catch {
            // Non-critical
        }
    }

    func testConnection() async -> Bool {
        guard let client = apiClient else { return false }
        do {
            currentUser = try await client.getCurrentUser()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func testCredentials(baseURL: String, email: String, apiToken: String) async -> Result<JiraUser, Error> {
        let client = JiraAPIClient(baseURL: baseURL, email: email, apiToken: apiToken)
        do {
            let user = try await client.getCurrentUser()
            return .success(user)
        } catch {
            return .failure(error)
        }
    }

    func refreshData() async {
        async let issuesFetch: () = fetchIssues()
        async let projectsFetch: () = fetchProjects()
        _ = await (issuesFetch, projectsFetch)
    }

    // MARK: - JQL Builder

    private func buildJQL() -> String {
        var conditions: [String] = []

        if let projectKey = selectedProjectKey, !projectKey.isEmpty {
            conditions.append("project = \(projectKey)")
        }

        switch statusFilter {
        case .open:
            conditions.append("statusCategory != Done")
        case .done:
            conditions.append("statusCategory = Done")
        case .all:
            break
        }

        if assignedToMe {
            conditions.append("assignee = currentUser()")
        }

        if !searchText.isEmpty {
            let escaped = searchText.replacingOccurrences(of: "\"", with: "\\\\\"")
            conditions.append("summary ~ \"\(escaped)\"")
        }

        var jql = conditions.joined(separator: " AND ")
        jql += " ORDER BY updated DESC"
        return jql
    }

    // MARK: - Timer

    func startTimer(for issue: JiraIssue) {
        activeTimerIssue = issue
        activeTimerStart = Date()
        timerPauseStart = nil
        timerAccumulatedPause = 0
        saveTimerState()
        successMessage = nil
        WidgetCenter.shared.reloadAllTimelines()

        // Auto-transition "To Do" issues to "In Progress" if enabled
        if autoTransitionOnStart,
           let statusCategory = issue.fields.status?.statusCategory?.key,
           statusCategory == "new" {
            Task {
                await autoTransitionToInProgress(issueKey: issue.key)
            }
        }
    }

    private func autoTransitionToInProgress(issueKey: String) async {
        guard let client = apiClient else { return }
        do {
            let transitions = try await client.getTransitions(issueKey: issueKey)
            // Find a transition whose target status category is "indeterminate" (In Progress)
            if let inProgressTransition = transitions.first(where: { $0.to.statusCategory?.key == "indeterminate" }) {
                try await client.transitionIssue(issueKey: issueKey, transitionId: inProgressTransition.id)
                // Refresh issues to show updated status
                await fetchIssues()
            }
        } catch {
            // Non-critical — don't show error for auto-transition failure
        }
    }

    func pauseTimer() {
        guard isTimerRunning, !isTimerPaused else { return }
        timerPauseStart = Date()
        saveTimerState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func resumeTimer() {
        guard let pauseStart = timerPauseStart else { return }
        timerAccumulatedPause += Date().timeIntervalSince(pauseStart)
        timerPauseStart = nil
        saveTimerState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Subtract minutes from the active timer by increasing the accumulated pause.
    /// Returns false if it would make the timer go negative.
    func subtractTime(minutes: Int) {
        guard isTimerRunning else { return }
        let secondsToSubtract = TimeInterval(minutes * 60)
        guard effectiveElapsedSeconds >= Int(secondsToSubtract) else { return }
        timerAccumulatedPause += secondsToSubtract
        saveTimerState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Add minutes to the active timer by moving the start time backwards.
    func addTime(minutes: Int) {
        guard isTimerRunning, activeTimerStart != nil else { return }
        activeTimerStart = activeTimerStart!.addingTimeInterval(-TimeInterval(minutes * 60))
        saveTimerState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func stopAndLogTimer() async throws -> Int {
        guard let issue = activeTimerIssue, let start = activeTimerStart else {
            throw TimerError.noActiveTimer
        }

        // If paused, finalize the current pause interval
        var totalPause = timerAccumulatedPause
        if let pauseStart = timerPauseStart {
            totalPause += Date().timeIntervalSince(pauseStart)
        }

        let elapsed = Int(Date().timeIntervalSince(start) - totalPause)
        guard elapsed >= 60 else {
            throw TimerError.tooShort
        }

        isLoggingTime = true
        defer { isLoggingTime = false }

        let comment = workDescription.isEmpty ? nil : workDescription
        try await apiClient?.logWork(
            issueKey: issue.key,
            timeSpentSeconds: elapsed,
            comment: comment,
            started: start
        )

        let duration = TimeInterval(elapsed).shortDuration
        successMessage = "Logged \(duration) to \(issue.key)"

        workDescription = ""
        activeTimerIssue = nil
        activeTimerStart = nil
        timerPauseStart = nil
        timerAccumulatedPause = 0
        clearTimerState()
        WidgetCenter.shared.reloadAllTimelines()

        return elapsed
    }

    func discardTimer() {
        activeTimerIssue = nil
        activeTimerStart = nil
        timerPauseStart = nil
        timerAccumulatedPause = 0
        clearTimerState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Timer Persistence

    private func saveTimerState() {
        guard let issue = activeTimerIssue, let start = activeTimerStart else { return }
        let defaults = UserDefaults.standard
        defaults.set(issue.key, forKey: "activeTimerIssueKey")
        defaults.set(issue.fields.summary, forKey: "activeTimerIssueSummary")
        defaults.set(start.timeIntervalSince1970, forKey: "activeTimerStart")
        defaults.set(timerAccumulatedPause, forKey: "activeTimerAccumulatedPause")
        if let pauseStart = timerPauseStart {
            defaults.set(pauseStart.timeIntervalSince1970, forKey: "activeTimerPauseStart")
        } else {
            defaults.removeObject(forKey: "activeTimerPauseStart")
        }
        SharedData.saveTimerState(SharedTimerData(
            issueKey: issue.key,
            issueSummary: issue.fields.summary,
            startTime: start,
            isPaused: isTimerPaused,
            accumulatedPauseTime: timerAccumulatedPause,
            pauseStart: timerPauseStart
        ))
    }

    private func loadTimerState() {
        let defaults = UserDefaults.standard
        guard let issueKey = defaults.string(forKey: "activeTimerIssueKey"),
              let summary = defaults.string(forKey: "activeTimerIssueSummary"),
              defaults.double(forKey: "activeTimerStart") > 0 else {
            return
        }
        let start = Date(timeIntervalSince1970: defaults.double(forKey: "activeTimerStart"))
        activeTimerIssue = JiraIssue(
            id: issueKey,
            key: issueKey,
            fields: JiraIssueFields(
                summary: summary,
                status: nil,
                priority: nil,
                assignee: nil,
                project: nil,
                issuetype: nil,
                timetracking: nil
            )
        )
        activeTimerStart = start
        timerAccumulatedPause = defaults.double(forKey: "activeTimerAccumulatedPause")
        let pauseEpoch = defaults.double(forKey: "activeTimerPauseStart")
        timerPauseStart = pauseEpoch > 0 ? Date(timeIntervalSince1970: pauseEpoch) : nil
    }

    private func clearTimerState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "activeTimerIssueKey")
        defaults.removeObject(forKey: "activeTimerIssueSummary")
        defaults.removeObject(forKey: "activeTimerStart")
        defaults.removeObject(forKey: "activeTimerAccumulatedPause")
        defaults.removeObject(forKey: "activeTimerPauseStart")
        SharedData.saveTimerState(nil)
    }

    private func syncSharedIssueData() {
        SharedData.saveIssueCount(issues.count)
        let recent = issues.prefix(5).map { issue in
            SharedIssueData(
                key: issue.key,
                summary: issue.fields.summary,
                statusName: issue.fields.status?.name
            )
        }
        SharedData.saveRecentIssues(Array(recent))
    }

    // MARK: - Filter Persistence

    func saveFilterState() {
        let defaults = UserDefaults.standard
        defaults.set(statusFilter.rawValue, forKey: "filter_statusFilter")
        defaults.set(selectedProjectKey ?? "", forKey: "filter_projectKey")
        defaults.set(selectedStatusName ?? "", forKey: "filter_statusName")
        defaults.set(assignedToMe, forKey: "filter_assignedToMe")
    }

    private func loadFilterState() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "filter_statusFilter"),
           let filter = StatusFilter(rawValue: raw) {
            statusFilter = filter
        }
        let projectKey = defaults.string(forKey: "filter_projectKey") ?? ""
        selectedProjectKey = projectKey.isEmpty ? nil : projectKey
        let statusName = defaults.string(forKey: "filter_statusName") ?? ""
        selectedStatusName = statusName.isEmpty ? nil : statusName
        if defaults.object(forKey: "filter_assignedToMe") != nil {
            assignedToMe = defaults.bool(forKey: "filter_assignedToMe")
        }
    }

    enum TimerError: LocalizedError {
        case noActiveTimer
        case tooShort

        var errorDescription: String? {
            switch self {
            case .noActiveTimer: return "No active timer"
            case .tooShort: return "Time must be at least 1 minute to log"
            }
        }
    }
}
