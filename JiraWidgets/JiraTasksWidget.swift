import SwiftUI
import WidgetKit

struct TasksEntry: TimelineEntry {
    let date: Date
    let issueCount: Int
    let recentIssues: [SharedIssueData]
    let timerData: SharedTimerData?
}

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: .now, issueCount: 0, recentIssues: [], timerData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        let entry = TasksEntry(
            date: .now,
            issueCount: SharedData.loadIssueCount(),
            recentIssues: SharedData.loadRecentIssues(),
            timerData: SharedData.loadTimerState()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let entry = TasksEntry(
            date: .now,
            issueCount: SharedData.loadIssueCount(),
            recentIssues: SharedData.loadRecentIssues(),
            timerData: SharedData.loadTimerState()
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct TasksWidgetSmallView: View {
    var entry: TasksEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Spacer()
            }

            Text("\(entry.issueCount)")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)

            Text("Open Tasks")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let timer = entry.timerData {
                Divider()
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 4, height: 4)
                    Text(timer.issueKey)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct TasksWidgetMediumView: View {
    var entry: TasksEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(entry.issueCount)")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                Text("Open Tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 80)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if entry.recentIssues.isEmpty {
                    Text("No recent issues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                } else {
                    ForEach(entry.recentIssues.prefix(4), id: \.key) { issue in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(issue.key)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Text(issue.summary)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct TasksWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: TasksEntry

    var body: some View {
        switch family {
        case .systemMedium:
            TasksWidgetMediumView(entry: entry)
        default:
            TasksWidgetSmallView(entry: entry)
        }
    }
}

struct JiraTasksWidget: Widget {
    let kind = "JiraTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Jira Tasks")
        .description("Shows your open Jira tasks and active timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
