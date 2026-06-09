import SwiftUI

struct TaskListView: View {
    @Environment(AppState.self) private var appState
    @State private var showStopConfirmation = false
    @State private var pendingTimerIssue: JiraIssue?

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            VStack(spacing: 0) {
                ActiveTimerView()

                if let success = appState.successMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(success)
                            .font(.callout)
                        Spacer()
                        Button {
                            withAnimation { appState.successMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.08))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                filterBar

                if appState.isLoading && appState.issues.isEmpty {
                    Spacer()
                    ProgressView("Loading issues...")
                    Spacer()
                } else if appState.issues.isEmpty {
                    ContentUnavailableView {
                        Label("No Issues", systemImage: "tray")
                    } description: {
                        Text("No issues match your current filters")
                    } actions: {
                        Button("Refresh") {
                            Task { await appState.fetchIssues() }
                        }
                    }
                } else {
                    issueList
                }
            }
            .navigationTitle("Tasks")
            .searchable(text: $appState.searchText, prompt: "Search issues")
            .onSubmit(of: .search) {
                Task { await appState.fetchIssues() }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        appState.showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await appState.fetchIssues() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                }
            }
            .sheet(isPresented: $appState.showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    appState.showSettings = false
                                }
                            }
                        }
                }
                .frame(width: 420, height: 560)
            }
            .alert("Error", isPresented: .init(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )) {
                Button("OK") { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
            .confirmationDialog(
                "Timer Running",
                isPresented: $showStopConfirmation,
                presenting: pendingTimerIssue
            ) { issue in
                Button("Stop & Log Current, Start New") {
                    Task {
                        _ = try? await appState.stopAndLogTimer()
                        appState.startTimer(for: issue)
                    }
                }
                Button("Discard Current, Start New", role: .destructive) {
                    appState.discardTimer()
                    appState.startTimer(for: issue)
                }
                Button("Cancel", role: .cancel) {
                    pendingTimerIssue = nil
                }
            } message: { _ in
                Text("You have an active timer. What would you like to do?")
            }
            .task {
                if appState.isConfigured && appState.issues.isEmpty {
                    await appState.refreshData()
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                filterChip(
                    "Open",
                    icon: "circle",
                    isSelected: appState.statusFilter == .open
                ) {
                    appState.statusFilter = .open
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }

                filterChip(
                    "Done",
                    icon: "checkmark.circle",
                    isSelected: appState.statusFilter == .done
                ) {
                    appState.statusFilter = .done
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }

                filterChip(
                    "All",
                    icon: "tray.full",
                    isSelected: appState.statusFilter == .all
                ) {
                    appState.statusFilter = .all
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }

                Divider()
                    .frame(height: 16)

                filterChip(
                    "Assigned to me",
                    icon: "person",
                    isSelected: appState.assignedToMe
                ) {
                    appState.assignedToMe.toggle()
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }

                Spacer()

                if !appState.issues.isEmpty {
                    Text("\(appState.filteredIssues.count) issue\(appState.filteredIssues.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                if !appState.projects.isEmpty {
                    Menu {
                        Button {
                            appState.selectedProjectKey = nil
                            appState.saveFilterState()
                            Task { await appState.fetchIssues() }
                        } label: {
                            HStack {
                                Text("All Projects")
                                if appState.selectedProjectKey == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Divider()
                        ForEach(appState.projects) { project in
                            Button {
                                appState.selectedProjectKey = project.key
                                appState.saveFilterState()
                                Task { await appState.fetchIssues() }
                            } label: {
                                HStack {
                                    Text("\(project.key) — \(project.name)")
                                    if appState.selectedProjectKey == project.key {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(projectLabel)
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.selectedProjectKey != nil ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                        .foregroundStyle(appState.selectedProjectKey != nil ? Color.accentColor : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if !appState.availableStatuses.isEmpty {
                    Menu {
                        Button {
                            appState.selectedStatusName = nil
                            appState.saveFilterState()
                        } label: {
                            HStack {
                                Text("All Statuses")
                                if appState.selectedStatusName == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Divider()
                        ForEach(appState.availableStatuses, id: \.self) { status in
                            Button {
                                appState.selectedStatusName = status
                                appState.saveFilterState()
                            } label: {
                                HStack {
                                    Text(status)
                                    if appState.selectedStatusName == status {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.caption2)
                            Text(statusLabel)
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.selectedStatusName != nil ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                        .foregroundStyle(appState.selectedStatusName != nil ? Color.accentColor : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("Clear")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func filterChip(_ title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? icon + ".fill" : icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var projectLabel: String {
        if let key = appState.selectedProjectKey {
            return key
        }
        return "Project"
    }

    private var statusLabel: String {
        if let name = appState.selectedStatusName {
            return name
        }
        return "Status"
    }

    private var hasActiveFilters: Bool {
        appState.selectedProjectKey != nil || appState.selectedStatusName != nil
    }

    private func clearFilters() {
        appState.selectedProjectKey = nil
        appState.selectedStatusName = nil
        appState.saveFilterState()
        Task { await appState.fetchIssues() }
    }

    // MARK: - Issue List

    private var issueList: some View {
        List(appState.filteredIssues) { issue in
            TaskRowView(
                issue: issue,
                isTimerRunning: appState.activeTimerIssue?.id == issue.id,
                onStartTimer: {
                    handleStartTimer(for: issue)
                },
                onStopTimer: {
                    Task {
                        do {
                            _ = try await appState.stopAndLogTimer()
                        } catch {
                            appState.errorMessage = error.localizedDescription
                        }
                    }
                }
            )
        }
        .listStyle(.plain)
        .refreshable {
            await appState.fetchIssues()
        }
    }

    private func handleStartTimer(for issue: JiraIssue) {
        if appState.isTimerRunning {
            pendingTimerIssue = issue
            showStopConfirmation = true
        } else {
            appState.startTimer(for: issue)
        }
    }
}
