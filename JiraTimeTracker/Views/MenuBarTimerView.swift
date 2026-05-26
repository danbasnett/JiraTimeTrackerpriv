import SwiftUI

#if os(macOS)
struct MenuBarTimerView: View {
    @Environment(AppState.self) private var appState
    @State private var showError: Bool = false
    @State private var errorText: String = ""
    @State private var menuBarSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let issue = appState.activeTimerIssue, let start = appState.activeTimerStart {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Tracking Time")
                            .font(.headline)
                    }

                    Text("\(issue.key): \(issue.fields.summary)")
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)

                    Text(start, style: .timer)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.medium)
                        .monospacedDigit()

                    TextField("Work description (optional)", text: Binding(
                        get: { appState.workDescription },
                        set: { appState.workDescription = $0 }
                    ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(2...4)

                    HStack(spacing: 8) {
                        Button("Discard") {
                            appState.discardTimer()
                        }
                        .controlSize(.small)

                        Button {
                            stopAndLog()
                        } label: {
                            if appState.isLoggingTime {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Stop & Log")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                        .disabled(appState.isLoggingTime)
                    }
                }

                if let success = appState.successMessage {
                    Divider()
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else {
                Label("No active timer", systemImage: "clock")
                    .foregroundStyle(.secondary)

                if let success = appState.successMessage {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Divider()

            menuBarFilters

            if appState.isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !appState.filteredIssues.isEmpty {
                Divider()

                HStack {
                    Text("Tasks (\(appState.filteredIssues.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await appState.fetchIssues() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isLoading)
                }

                List(appState.filteredIssues.prefix(20)) { issue in
                    Button {
                        if appState.isTimerRunning {
                            appState.discardTimer()
                        }
                        appState.startTimer(for: issue)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appState.activeTimerIssue?.id == issue.id ? "stop.circle.fill" : "play.circle")
                                .foregroundStyle(appState.activeTimerIssue?.id == issue.id ? .red : .green)
                                .font(.body)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(issue.key)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    if let status = issue.fields.status {
                                        Text(status.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(issue.fields.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(appState.filteredIssues.prefix(20).count) * 38, 600))
            } else if !appState.issues.isEmpty {
                Text("No tasks match filters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !appState.isLoading && appState.isConfigured {
                Divider()
                Button {
                    Task { await appState.refreshData() }
                } label: {
                    Label("Load Tasks", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button {
                NSApplication.shared.activate()
                if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open JiraTimeTracker", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Button {
                appState.showSettings = true
                NSApplication.shared.activate()
                if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            if appState.isConfigured {
                Task { await appState.refreshData() }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorText)
        }
    }

    private var menuBarFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search issues", text: $menuBarSearchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit {
                        appState.searchText = menuBarSearchText
                        Task { await appState.fetchIssues() }
                    }
                if !menuBarSearchText.isEmpty {
                    Button {
                        menuBarSearchText = ""
                        appState.searchText = ""
                        Task { await appState.fetchIssues() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Category", selection: Binding(
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

            HStack(spacing: 6) {
                if !appState.availableStatuses.isEmpty {
                    Picker("Status", selection: Binding(
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
                    .controlSize(.small)
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
                            Text(project.key).tag(project.key)
                        }
                    }
                    .controlSize(.small)
                }
            }

            Toggle(isOn: Binding(
                get: { appState.assignedToMe },
                set: { newValue in
                    appState.assignedToMe = newValue
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }
            )) {
                Text("Assigned to me")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
        }
    }

    private func stopAndLog() {
        Task {
            do {
                _ = try await appState.stopAndLogTimer()
            } catch {
                errorText = error.localizedDescription
                showError = true
            }
        }
    }
}
#endif
