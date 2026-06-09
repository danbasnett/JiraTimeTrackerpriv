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
                }
                .frame(minWidth: 450, minHeight: 500)
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

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("Status", selection: Binding(
                get: { appState.statusFilter },
                set: { newValue in
                    appState.statusFilter = newValue
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }
            )) {
                ForEach(AppState.StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            if !appState.availableStatuses.isEmpty {
                Picker("Status Name", selection: Binding(
                    get: { appState.selectedStatusName ?? "" },
                    set: { newValue in
                        appState.selectedStatusName = newValue.isEmpty ? nil : newValue
                        appState.saveFilterState()
                    }
                )) {
                    Text("All Statuses").tag("")
                    ForEach(appState.availableStatuses, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
                .pickerStyle(.menu)
            }

            if !appState.projects.isEmpty {
                Picker("Project", selection: Binding(
                    get: { appState.selectedProjectKey ?? "" },
                    set: { newValue in
                        appState.selectedProjectKey = newValue.isEmpty ? nil : newValue
                        appState.saveFilterState()
                        Task { await appState.fetchIssues() }
                    }
                )) {
                    Text("All Projects").tag("")
                    ForEach(appState.projects) { project in
                        Text(project.name).tag(project.key)
                    }
                }
                .pickerStyle(.menu)
            }

            Spacer()

            Toggle(isOn: Binding(
                get: { appState.assignedToMe },
                set: { newValue in
                    appState.assignedToMe = newValue
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }
            )) {
                Text("Mine")
                    .font(.callout)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
