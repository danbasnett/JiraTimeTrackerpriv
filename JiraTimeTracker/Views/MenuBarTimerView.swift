import SwiftUI

struct MenuBarTimerView: View {
    @Environment(AppState.self) private var appState
    @Environment(UpdateChecker.self) private var updateChecker
    @State private var showError: Bool = false
    @State private var errorText: String = ""
    @State private var menuBarSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Timer section
            timerSection
                .padding(12)

            Divider()

            // Filters
            filterSection
                .padding(12)

            Divider()

            // Task list
            taskSection

            Divider()

            // Footer actions
            footerSection
                .padding(8)
        }
        .frame(width: 340)
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

    // MARK: - Timer Section

    private var timerSection: some View {
        Group {
            if let issue = appState.activeTimerIssue, let start = appState.activeTimerStart {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .shadow(color: .red.opacity(0.5), radius: 3)

                        Text(issue.key)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(start, style: .timer)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }

                    Text(issue.fields.summary)
                        .font(.callout)
                        .lineLimit(2)

                    TextField("Work description (optional)", text: Binding(
                        get: { appState.workDescription },
                        set: { appState.workDescription = $0 }
                    ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .lineLimit(2...3)

                    HStack(spacing: 8) {
                        Spacer()

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
            } else {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.tertiary)
                    Text("No active timer")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let success = appState.successMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button {
                        appState.successMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(spacing: 8) {
            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
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
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Filter chips
            HStack(spacing: 4) {
                menuFilterChip("Open", isSelected: appState.statusFilter == .open) {
                    appState.statusFilter = .open
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }
                menuFilterChip("Done", isSelected: appState.statusFilter == .done) {
                    appState.statusFilter = .done
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }
                menuFilterChip("All", isSelected: appState.statusFilter == .all) {
                    appState.statusFilter = .all
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }

                Spacer()

                menuFilterChip("Mine", isSelected: appState.assignedToMe) {
                    appState.assignedToMe.toggle()
                    appState.saveFilterState()
                    Task { await appState.fetchIssues() }
                }
            }

            // Project & status dropdowns
            if !appState.projects.isEmpty || !appState.availableStatuses.isEmpty {
                HStack(spacing: 4) {
                    if !appState.projects.isEmpty {
                        menuDropdown(
                            label: appState.selectedProjectKey ?? "Project",
                            icon: "folder",
                            isActive: appState.selectedProjectKey != nil
                        ) {
                            Button("All Projects") {
                                appState.selectedProjectKey = nil
                                appState.saveFilterState()
                                Task { await appState.fetchIssues() }
                            }
                            Divider()
                            ForEach(appState.projects) { project in
                                Button("\(project.key) — \(project.name)") {
                                    appState.selectedProjectKey = project.key
                                    appState.saveFilterState()
                                    Task { await appState.fetchIssues() }
                                }
                            }
                        }
                    }

                    if !appState.availableStatuses.isEmpty {
                        menuDropdown(
                            label: appState.selectedStatusName ?? "Status",
                            icon: "line.3.horizontal.decrease",
                            isActive: appState.selectedStatusName != nil
                        ) {
                            Button("All Statuses") {
                                appState.selectedStatusName = nil
                                appState.saveFilterState()
                            }
                            Divider()
                            ForEach(appState.availableStatuses, id: \.self) { status in
                                Button(status) {
                                    appState.selectedStatusName = status
                                    appState.saveFilterState()
                                }
                            }
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Task Section

    private var taskSection: some View {
        Group {
            if appState.isLoading && appState.issues.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if !appState.filteredIssues.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(appState.filteredIssues.count) issue\(appState.filteredIssues.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        Spacer()
                        Button {
                            Task { await appState.fetchIssues() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isLoading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.filteredIssues.prefix(20)) { issue in
                                menuIssueRow(issue)
                                if issue.id != appState.filteredIssues.prefix(20).last?.id {
                                    Divider()
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
            } else if !appState.issues.isEmpty {
                HStack {
                    Spacer()
                    Text("No issues match filters")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else if !appState.isLoading && appState.isConfigured {
                Button {
                    Task { await appState.refreshData() }
                } label: {
                    HStack {
                        Spacer()
                        Label("Load Issues", systemImage: "arrow.clockwise")
                            .font(.caption)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 16)
            }
        }
    }

    private func menuIssueRow(_ issue: JiraIssue) -> some View {
        Button {
            if appState.activeTimerIssue?.id == issue.id {
                stopAndLog()
            } else {
                if appState.isTimerRunning {
                    appState.discardTimer()
                }
                appState.startTimer(for: issue)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: appState.activeTimerIssue?.id == issue.id ? "stop.circle.fill" : "play.circle")
                    .font(.body)
                    .foregroundStyle(appState.activeTimerIssue?.id == issue.id ? .red : .accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(issue.key)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if let status = issue.fields.status {
                            Text(status.name)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(statusColor(status).opacity(0.15))
                                .foregroundStyle(statusColor(status))
                                .clipShape(Capsule())
                        }
                    }

                    Text(issue.fields.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if appState.activeTimerIssue?.id == issue.id {
                Color.red.opacity(0.06)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 2) {
            if updateChecker.updateAvailable {
                Button {
                    if let url = URL(string: updateChecker.releaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Update available: v\(updateChecker.latestVersion)")
                            .font(.caption)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }

            HStack(spacing: 0) {
                footerButton("Open App", icon: "macwindow") {
                    NSApplication.shared.activate()
                    if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }

                footerButton("Settings", icon: "gear") {
                    appState.showSettings = true
                    NSApplication.shared.activate()
                    if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }

                footerButton("Quit", icon: "power") {
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func menuFilterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func menuDropdown<Content: View>(label: String, icon: String, isActive: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.caption2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statusColor(_ status: JiraStatus) -> Color {
        switch status.statusCategory?.key {
        case "new": return .blue
        case "indeterminate": return .orange
        case "done": return .green
        default: return .secondary
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
