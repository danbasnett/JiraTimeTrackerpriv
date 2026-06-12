import SwiftUI
import WidgetKit

struct TimerEntry: TimelineEntry {
    let date: Date
    let timerData: SharedTimerData?
}

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, timerData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(TimerEntry(date: .now, timerData: SharedData.loadTimerState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let data = SharedData.loadTimerState()
        let entry = TimerEntry(date: .now, timerData: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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
        let accentColor: Color = timer.isPaused ? .orange : .red

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(timer.isPaused ? "Paused" : "Tracking")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)
                Spacer()
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

            if timer.isPaused {
                // Show frozen elapsed time
                Text(formattedElapsed(timer))
                    .font(.system(family == .systemSmall ? .title3 : .title2, design: .monospaced))
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            } else {
                // Show the effective start (shifted by accumulated pause) for live timer
                Text(timer.startTime.addingTimeInterval(timer.accumulatedPauseTime), style: .timer)
                    .font(.system(family == .systemSmall ? .title3 : .title2, design: .monospaced))
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }

    private func formattedElapsed(_ timer: SharedTimerData) -> String {
        var totalPause = timer.accumulatedPauseTime
        if let pauseStart = timer.pauseStart {
            totalPause += Date().timeIntervalSince(pauseStart)
        }
        let elapsed = max(0, Date().timeIntervalSince(timer.startTime) - totalPause)
        let secs = Int(elapsed)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: family == .systemSmall ? 24 : 30))
                .foregroundStyle(.secondary)
            Text("No Active Timer")
                .font(.caption)
                .foregroundStyle(.secondary)
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
