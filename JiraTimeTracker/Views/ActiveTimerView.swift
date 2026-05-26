import SwiftUI

struct ActiveTimerView: View {
    @Environment(AppState.self) private var appState
    @State private var showError: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        if let issue = appState.activeTimerIssue, let start = appState.activeTimerStart {
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)

                    Text(issue.key)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(issue.fields.summary)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(start, style: .timer)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                TextField("Work description (optional)", text: Binding(
                    get: { appState.workDescription },
                    set: { appState.workDescription = $0 }
                ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .lineLimit(2...4)

                HStack(spacing: 12) {
                    Spacer()

                    Button {
                        appState.discardTimer()
                    } label: {
                        Label("Discard", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.secondary)

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
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
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
