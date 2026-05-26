import Foundation
import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

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
    var isTimerRunning: Bool { activeTimerIssue != nil && activeTimerStart != nil }

    // MARK: - UI State

    var isLoading: Bool = false
    var isLoggingTime: Bool = false
    var errorMessage: String?
    var successMessage: String?
    var showSettings: Bool = false
    var workDescription: String = ""
    var pushTokenStatus: String = ""

    // MARK: - Private

    private var apiClient: JiraAPIClient?
    private var syncTask: Task<Void, Never>?

    init() {
        loadCredentials()
        loadTimerState()
        loadFilterState()
        Task { await CloudKitService.shared.setupSubscription() }
        startPeriodicSync()
    }

    func syncFromCloud() async {
        await CloudKitService.shared.syncFromCloud()
        applyRemoteTimerState()
        ensureLiveActivity()
    }

    func startPeriodicSync() {
        PeerSyncService.shared.start { [weak self] timerData in
            self?.handlePeerUpdate(timerData)
        }

        syncTask?.cancel()
        syncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                if !PeerSyncService.shared.isConnected {
                    await CloudKitService.shared.syncFromCloud()
                    applyRemoteTimerState()
                }
            }
        }
    }

    func stopPeriodicSync() {
        syncTask?.cancel()
        syncTask = nil
        PeerSyncService.shared.stop()
    }

    private func handlePeerUpdate(_ timerData: SharedTimerData?) {
        if let timerData {
            activeTimerIssue = JiraIssue(
                id: timerData.issueKey,
                key: timerData.issueKey,
                fields: JiraIssueFields(
                    summary: timerData.issueSummary,
                    status: nil,
                    priority: nil,
                    assignee: nil,
                    project: nil,
                    issuetype: nil,
                    timetracking: nil
                )
            )
            activeTimerStart = timerData.startTime
            saveTimerState()
            startLiveActivity(issueKey: timerData.issueKey, issueSummary: timerData.issueSummary, startTime: timerData.startTime)
        } else {
            activeTimerIssue = nil
            activeTimerStart = nil
            clearTimerState()
            stopLiveActivity()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func applyRemoteTimerState() {
        let timerData = SharedData.loadTimerState()
        if let timerData {
            if activeTimerIssue?.key != timerData.issueKey || activeTimerStart != timerData.startTime {
                activeTimerIssue = JiraIssue(
                    id: timerData.issueKey,
                    key: timerData.issueKey,
                    fields: JiraIssueFields(
                        summary: timerData.issueSummary,
                        status: nil,
                        priority: nil,
                        assignee: nil,
                        project: nil,
                        issuetype: nil,
                        timetracking: nil
                    )
                )
                activeTimerStart = timerData.startTime
                startLiveActivity(issueKey: timerData.issueKey, issueSummary: timerData.issueSummary, startTime: timerData.startTime)
            }
        } else if activeTimerIssue != nil {
            activeTimerIssue = nil
            activeTimerStart = nil
            clearTimerState()
            stopLiveActivity()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func broadcastTimerChange(_ data: SharedTimerData?) {
        PeerSyncService.shared.broadcastTimerState(data)
        Task {
            await CloudKitService.shared.saveTimerState(data)
            if let err = await CloudKitService.shared.lastError {
                errorMessage = err
            }
            #if os(macOS)
            await sendAPNSPush(data)
            #endif
        }
    }

    #if os(macOS)
    private func sendAPNSPush(_ data: SharedTimerData?) async {
        guard let token = await CloudKitService.shared.fetchPushToStartToken() else { return }
        if let data {
            await APNSService.shared.sendStartLiveActivity(
                pushToken: token,
                issueKey: data.issueKey,
                issueSummary: data.issueSummary,
                startTime: data.startTime
            )
        } else {
            await APNSService.shared.sendEndLiveActivity(pushToken: token)
        }
        if let err = await APNSService.shared.lastError {
            errorMessage = err
        }
    }
    #endif

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
            // Non-critical — don't show error for project fetch
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
        saveTimerState()
        successMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
        let data = SharedTimerData(issueKey: issue.key, issueSummary: issue.fields.summary, startTime: activeTimerStart!)
        broadcastTimerChange(data)
        startLiveActivity(issueKey: issue.key, issueSummary: issue.fields.summary, startTime: activeTimerStart!)
    }

    func stopAndLogTimer() async throws -> Int {
        guard let issue = activeTimerIssue, let start = activeTimerStart else {
            throw TimerError.noActiveTimer
        }

        let elapsed = Int(Date().timeIntervalSince(start))
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
        clearTimerState()
        WidgetCenter.shared.reloadAllTimelines()
        broadcastTimerChange(nil)
        stopLiveActivity()

        return elapsed
    }

    func discardTimer() {
        activeTimerIssue = nil
        activeTimerStart = nil
        clearTimerState()
        WidgetCenter.shared.reloadAllTimelines()
        broadcastTimerChange(nil)
        stopLiveActivity()
    }

    // MARK: - Live Activity

    func ensureLiveActivity() {
        #if os(iOS)
        guard let issue = activeTimerIssue, let start = activeTimerStart else {
            stopLiveActivity()
            return
        }
        if Activity<TimerActivityAttributes>.activities.isEmpty {
            startLiveActivity(issueKey: issue.key, issueSummary: issue.fields.summary, startTime: start)
        }
        #endif
    }

    private func startLiveActivity(issueKey: String, issueSummary: String, startTime: Date) {
        #if os(iOS)
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            errorMessage = "Live Activities are disabled in Settings"
            return
        }
        for activity in Activity<TimerActivityAttributes>.activities {
            let state = TimerActivityAttributes.ContentState(isRunning: false)
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
        let attributes = TimerActivityAttributes(
            issueKey: issueKey,
            issueSummary: issueSummary,
            startTime: startTime
        )
        let state = TimerActivityAttributes.ContentState(isRunning: true)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            errorMessage = "Live Activity: \(error.localizedDescription)"
        }
        #endif
    }

    private func stopLiveActivity() {
        #if os(iOS)
        let state = TimerActivityAttributes.ContentState(isRunning: false)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<TimerActivityAttributes>.activities {
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
        #endif
    }

    // MARK: - Timer Persistence

    private func saveTimerState() {
        guard let issue = activeTimerIssue, let start = activeTimerStart else { return }
        let defaults = UserDefaults.standard
        defaults.set(issue.key, forKey: "activeTimerIssueKey")
        defaults.set(issue.fields.summary, forKey: "activeTimerIssueSummary")
        defaults.set(start.timeIntervalSince1970, forKey: "activeTimerStart")
        SharedData.saveTimerState(SharedTimerData(
            issueKey: issue.key,
            issueSummary: issue.fields.summary,
            startTime: start
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
    }

    private func clearTimerState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "activeTimerIssueKey")
        defaults.removeObject(forKey: "activeTimerIssueSummary")
        defaults.removeObject(forKey: "activeTimerStart")
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
