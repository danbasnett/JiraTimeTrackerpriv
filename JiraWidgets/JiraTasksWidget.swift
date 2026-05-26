import SwiftUI
import WidgetKit
import CloudKit

struct TasksEntry: TimelineEntry {
    let date: Date
    let issueCount: Int
    let recentIssues: [SharedIssueData]
    let timerData: SharedTimerData?
}

struct TasksProvider: TimelineProvider {
    private let database = CKContainer(identifier: "iCloud.danbasnett.JiraTimeTracker").privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "activeTimer")

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
        let localTimer = SharedData.loadTimerState()
        if localTimer != nil {
            let entry = TasksEntry(
                date: .now,
                issueCount: SharedData.loadIssueCount(),
                recentIssues: SharedData.loadRecentIssues(),
                timerData: localTimer
            )
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        } else {
            Task {
                let cloudData = await fetchTimerFromCloudKit()
                if let cloud = cloudData {
                    SharedData.saveTimerState(cloud)
                }
                let entry = TasksEntry(
                    date: .now,
                    issueCount: SharedData.loadIssueCount(),
                    recentIssues: SharedData.loadRecentIssues(),
                    timerData: cloudData
                )
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now)!
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            }
        }
    }

    private func fetchTimerFromCloudKit() async -> SharedTimerData? {
        do {
            let record = try await database.record(for: recordID)
            guard let isActive = record["isActive"] as? Int64, isActive == 1,
                  let issueKey = record["issueKey"] as? String,
                  let issueSummary = record["issueSummary"] as? String,
                  let startTime = record["startTime"] as? Date else {
                return nil
            }
            return SharedTimerData(issueKey: issueKey, issueSummary: issueSummary, startTime: startTime)
        } catch {
            return nil
        }
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

struct TasksWidgetRectangularView: View {
    var entry: TasksEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let timer = entry.timerData {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                    Text(timer.issueKey)
                        .fontWeight(.semibold)
                }
                Text(timer.startTime, style: .timer)
                    .font(.headline)
                    .monospacedDigit()
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text("\(entry.issueCount) tasks")
                        .fontWeight(.semibold)
                }
                if let first = entry.recentIssues.first {
                    Text("\(first.key): \(first.summary)")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
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
        #if os(iOS)
        case .accessoryRectangular:
            TasksWidgetRectangularView(entry: entry)
        #endif
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
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
