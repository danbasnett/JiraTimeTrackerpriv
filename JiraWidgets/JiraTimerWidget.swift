import SwiftUI
import WidgetKit
import AppIntents
import CloudKit
import ActivityKit

struct RefreshTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Timer"

    func perform() async throws -> some IntentResult {
        let database = CKContainer(identifier: "iCloud.danbasnett.JiraTimeTracker").privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "activeTimer")
        do {
            let record = try await database.record(for: recordID)
            if let isActive = record["isActive"] as? Int64, isActive == 1,
               let issueKey = record["issueKey"] as? String,
               let issueSummary = record["issueSummary"] as? String,
               let startTime = record["startTime"] as? Date {
                let timer = SharedTimerData(issueKey: issueKey, issueSummary: issueSummary, startTime: startTime)
                SharedData.saveTimerState(timer)
            } else {
                SharedData.saveTimerState(nil)
            }
        } catch {
            // CloudKit unavailable, keep local state
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let timerData: SharedTimerData?
}

struct TimerProvider: TimelineProvider {
    private let database = CKContainer(identifier: "iCloud.danbasnett.JiraTimeTracker").privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "activeTimer")

    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, timerData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        let local = SharedData.loadTimerState()
        if local != nil || context.isPreview {
            completion(TimerEntry(date: .now, timerData: local))
        } else {
            Task {
                let data = await fetchFromCloudKit()
                completion(TimerEntry(date: .now, timerData: data))
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let localData = SharedData.loadTimerState()

        if localData != nil {
            let entry = TimerEntry(date: .now, timerData: localData)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        } else {
            Task {
                let cloudData = await fetchFromCloudKit()
                if let cloud = cloudData {
                    SharedData.saveTimerState(cloud)
                }
                let entry = TimerEntry(date: .now, timerData: cloudData)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now)!
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            }
        }
    }

    private func fetchFromCloudKit() async -> SharedTimerData? {
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

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: TimerEntry

    var body: some View {
        Group {
            if let timer = entry.timerData {
                activeTimerContent(timer)
            } else {
                idleContent
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private func activeTimerContent(_ timer: SharedTimerData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text("Tracking")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Spacer()
                Button(intent: RefreshTimerIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(timer.issueKey)
                .font(family == .systemSmall ? .headline : .title3)
                .fontWeight(.bold)
                .minimumScaleFactor(0.7)

            Text(timer.issueSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 3 : 4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(timer.startTime, style: .timer)
                .font(.system(family == .systemSmall ? .title3 : .title2, design: .monospaced))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }

    private var idleContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: family == .systemSmall ? 24 : 30))
                .foregroundStyle(.secondary)
            Text("No Active Timer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(intent: RefreshTimerIntent()) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JiraTimerWidget: Widget {
    let kind = "JiraTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerProvider()) { entry in
            TimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Jira Timer")
        .description("Shows your active time tracking session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if os(iOS)
struct TimerLiveActivityView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("Tracking")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }

                Text(context.attributes.issueKey)
                    .font(.headline)
                    .fontWeight(.bold)

                Text(context.attributes.issueSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(context.attributes.startTime, style: .timer)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.red)
        }
        .padding()
    }
}

struct JiraTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            TimerLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.issueKey)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(context.attributes.issueSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startTime, style: .timer)
                        .font(.system(.title3, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text(context.attributes.issueKey)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            } compactTrailing: {
                Text(context.attributes.startTime, style: .timer)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.red)
            } minimal: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}
#endif
