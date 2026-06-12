import SwiftUI

struct MenuBarTimerView: View {
    @Environment(AppState.self) private var appState
    @Environment(UpdateChecker.self) private var updateChecker
    @State private var menuBarSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            timerSection
                .padding(12)

            Divider()

            filterSection
                .padding(12)

            Divider()

            taskSection

            Divider()

            footerSection
                .padding(8)
        }
        .frame(width: 360)
        .onAppear {
            appState.errorMessage = nil
            if appState.isConfigured {
                Task { await appState.refreshData() }
            }
        }
    }

    // MARK: - Timer Section

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let issue = appState.activeTimerIssue, let _ = appState.activeTimerStart {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isTimerPaused ? .orange : .red)
                        .frame(width: 7, height: 7)
                        .shadow(color: (appState.isTimerPaused ? Color.orange : Color.red).opacity(0.5), radius: 3)

                    Text(issue.key)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    if appState.isTimerPaused {
                        Text("PAUSED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    if appState.isTimerPaused {
                        Text(timerElapsedWhilePaused)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    } else if let effectiveStart = appState.effectiveTimerStart {
                        Text(effectiveStart, style: .timer)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
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

                HStack(spacing: 6) {
                    // Adjust time menus
                    Menu {
                        Button("+ 1 min") { appState.addTime(minutes: 1) }
                        Button("+ 5 min") { appState.addTime(minutes: 5) }
                        Button("+ 15 min") { appState.addTime(minutes: 15) }
                        Button("+ 30 min") { appState.addTime(minutes: 30) }
                        Button("+ 60 min") { appState.addTime(minutes: 60) }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Menu {
                        let elapsed = appState.effectiveElapsedSeconds
                        Button("− 1 min") { appState.subtractTime(minutes: 1) }
                            .disabled(elapsed < 60)
                        Button("− 5 min") { appState.subtractTime(minutes: 5) }
                            .disabled(elapsed < 300)
                        Button("− 15 min") { appState.subtractTime(minutes: 15) }
                            .disabled(elapsed < 900)
                        Button("− 30 min") { appState.subtractTime(minutes: 30) }
                            .disabled(elapsed < 1800)
                        Button("− 60 min") { appState.subtractTime(minutes: 60) }
                            .disabled(elapsed < 3600)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()

                    Button("Discard") {
                        appState.discardTimer()
                        appState.errorMessage = nil
                    }
                    .controlSize(.small)

                    Button {
                        if appState.isTimerPaused {
                            appState.resumeTimer()
                        } else {
                            appState.pauseTimer()
                        }
                    } label: {
                        Label(
                            appState.isTimerPaused ? "Resume" : "Pause",
                            systemImage: appState.isTimerPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)

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

                // Error shown inline within the timer section
                if let error = appState.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            appState.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
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
            }
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(spacing: 8) {
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
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

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
                            ForEach(appState.filteredIssues.prefix(50)) { issue in
                                menuIssueRow(issue)
                                if issue.id != appState.filteredIssues.prefix(50).last?.id {
                                    Divider()
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 100, maxHeight: 500)
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
                                .background(statusColor(status).opacity(0.15), in: Capsule())
                                .foregroundStyle(statusColor(status))
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
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 2) {
            if updateChecker.updateAvailable {
                Button {
                    Task { await updateChecker.downloadAndInstall() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                        if updateChecker.isDownloading {
                            Text("Downloading...")
                                .font(.caption)
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Install v\(updateChecker.latestVersion)")
                                .font(.caption)
                            Spacer()
                            Image(systemName: "arrow.down.to.line")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(updateChecker.isDownloading)
                .padding(.bottom, 4)
            }

            HStack(spacing: 0) {
                footerButton("Open App", icon: "macwindow") {
                    NSApplication.shared.activate()
                    if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }

                footerButton(
                    updateChecker.isChecking ? "Checking..." : "Updates",
                    icon: "arrow.triangle.2.circlepath"
                ) {
                    Task { await updateChecker.checkForUpdates() }
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
                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.clear), in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
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
            .background(isActive ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
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

    private var timerElapsedWhilePaused: String {
        guard let start = appState.activeTimerStart else { return "0:00" }
        var totalPause = appState.timerAccumulatedPause
        if let pauseStart = appState.timerPauseStart {
            totalPause += Date().timeIntervalSince(pauseStart)
        }
        let elapsed = Date().timeIntervalSince(start) - totalPause
        let secs = max(0, Int(elapsed))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func stopAndLog() {
        Task {
            do {
                _ = try await appState.stopAndLogTimer()
                appState.errorMessage = nil
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}
