import SwiftUI

struct TaskRowView: View {
    let issue: JiraIssue
    let isTimerRunning: Bool
    let onStartTimer: () -> Void
    let onStopTimer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(issue.key)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)

                    if let priority = issue.fields.priority {
                        priorityBadge(priority.name)
                    }

                    if let issueType = issue.fields.issuetype {
                        Text(issueType.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(issue.fields.summary)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let status = issue.fields.status {
                        statusBadge(status)
                    }
                    if let timeSpent = issue.fields.timetracking?.timeSpent {
                        Label(timeSpent, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                if isTimerRunning {
                    onStopTimer()
                } else {
                    onStartTimer()
                }
            } label: {
                Image(systemName: isTimerRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isTimerRunning ? .red : .green)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: JiraStatus) -> some View {
        Text(status.name)
            .font(.caption2)
            .fontWeight(.medium)
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
