import SwiftUI

struct ActiveTimerView: View {
    @Environment(AppState.self) private var appState
    @State private var showError: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        if let issue = appState.activeTimerIssue, let _ = appState.activeTimerStart {
            let accentColor: Color = appState.isTimerPaused ? .orange : .red

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Timer display
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 7, height: 7)
                                .shadow(color: accentColor.opacity(0.5), radius: 3)

                            Text(issue.key)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            if appState.isTimerPaused {
                                Text("PAUSED")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                        }

                        Text(issue.fields.summary)
                            .font(.callout)
                            .lineLimit(1)
                    }

                    Spacer()

                    if appState.isTimerPaused {
                        Text(frozenElapsed)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    } else if let effectiveStart = appState.effectiveTimerStart {
                        Text(effectiveStart, style: .timer)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
                }

                TextField("Work description (optional)", text: Binding(
                    get: { appState.workDescription },
                    set: { appState.workDescription = $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .lineLimit(2...3)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    Menu {
                        Button("+ 1 min") { appState.addTime(minutes: 1) }
                        Button("+ 5 min") { appState.addTime(minutes: 5) }
                        Button("+ 15 min") { appState.addTime(minutes: 15) }
                        Button("+ 30 min") { appState.addTime(minutes: 30) }
                        Button("+ 60 min") { appState.addTime(minutes: 60) }
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Menu {
                        Button("− 1 min") { appState.subtractTime(minutes: 1) }
                        Button("− 5 min") { appState.subtractTime(minutes: 5) }
                        Button("− 15 min") { appState.subtractTime(minutes: 15) }
                        Button("− 30 min") { appState.subtractTime(minutes: 30) }
                        Button("− 60 min") { appState.subtractTime(minutes: 60) }
                    } label: {
                        Label("Subtract", systemImage: "minus.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()

                    Button {
                        appState.discardTimer()
                    } label: {
                        Text("Discard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
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
                        .font(.caption)
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
                            Label("Stop & Log", systemImage: "stop.fill")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(appState.isLoggingTime)
                }
                .padding(.top, 8)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.04))
                    .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorText)
            }
        }
    }

    private var frozenElapsed: String {
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
            } catch {
                errorText = error.localizedDescription
                showError = true
            }
        }
    }
}
