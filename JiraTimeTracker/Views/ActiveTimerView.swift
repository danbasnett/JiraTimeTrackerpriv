import SwiftUI

struct ActiveTimerView: View {
    @Environment(AppState.self) private var appState
    @State private var showError: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        if let issue = appState.activeTimerIssue, let start = appState.activeTimerStart {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Timer display
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 7, height: 7)
                                .shadow(color: .red.opacity(0.5), radius: 3)

                            Text(issue.key)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }

                        Text(issue.fields.summary)
                            .font(.callout)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(start, style: .timer)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.red)
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
                    .fill(.red.opacity(0.04))
                    .strokeBorder(.red.opacity(0.15), lineWidth: 1)
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
