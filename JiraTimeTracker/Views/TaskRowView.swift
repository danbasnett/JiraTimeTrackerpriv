import SwiftUI

struct TaskRowView: View {
    let issue: JiraIssue
    let isTimerRunning: Bool
    let onStartTimer: () -> Void
    let onStopTimer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Play/stop button
            Button {
                if isTimerRunning {
                    onStopTimer()
                } else {
                    onStartTimer()
                }
            } label: {
                Image(systemName: isTimerRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isTimerRunning ? .red : .accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Key + metadata row
                HStack(spacing: 6) {
                    Text(issue.key)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if let issueType = issue.fields.issuetype {
                        Text(issueType.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let priority = issue.fields.priority {
                        priorityBadge(priority.name)
                    }

                    Spacer()

                    if let timeSpent = issue.fields.timetracking?.timeSpent {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(timeSpent)
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }

                // Summary
                Text(issue.fields.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Status badge
                if let status = issue.fields.status {
                    statusBadge(status)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: JiraStatus) -> some View {
        Text(status.name)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.12))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: JiraStatus) -> Color {
        switch status.statusCategory?.key {
        case "new": return .blue
        case "indeterminate": return .orange
        case "done": return .green
        default: return .secondary
        }
    }

    private func priorityBadge(_ name: String) -> some View {
        let (icon, color) = priorityInfo(name)
        return Image(systemName: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }

    private func priorityInfo(_ name: String) -> (String, Color) {
        switch name.lowercased() {
        case "highest", "critical", "blocker":
            return ("chevron.up.2", .red)
        case "high":
            return ("chevron.up", .orange)
        case "medium":
            return ("equal", .yellow)
        case "low":
            return ("chevron.down", .blue)
        case "lowest":
            return ("chevron.down.2", .gray)
        default:
            return ("minus", .secondary)
        }
    }
}
