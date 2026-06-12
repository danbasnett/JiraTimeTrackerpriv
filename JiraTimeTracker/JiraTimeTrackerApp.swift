import SwiftUI

@main
struct JiraTimeTrackerApp: App {
    @State private var appState = AppState()
    @State private var updateChecker = UpdateChecker()

    private var menuBarIcon: String {
        if appState.isTimerPaused {
            return "pause.circle.fill"
        } else if appState.isTimerRunning {
            return "clock.fill"
        } else {
            return "clock"
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(updateChecker)
                .onAppear {
                    updateChecker.startPeriodicChecks()
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }

        MenuBarExtra {
            MenuBarTimerView()
                .environment(appState)
                .environment(updateChecker)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(updateChecker)
        }
    }

    // MARK: - URL Scheme Handler (jiratimetracker://)

    private func handleURL(_ url: URL) {
        guard url.scheme == "jiratimetracker" else { return }
        let command = url.host ?? ""

        switch command {
        case "pause":
            appState.pauseTimer()
        case "resume":
            appState.resumeTimer()
        case "toggle":
            if appState.isTimerPaused {
                appState.resumeTimer()
            } else if appState.isTimerRunning {
                appState.pauseTimer()
            }
        case "stop":
            Task {
                try? await appState.stopAndLogTimer()
            }
        case "discard":
            appState.discardTimer()
        case "start":
            // Start timer for a specific issue: jiratimetracker://start?issueKey=PROJ-123
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let issueKey = components.queryItems?.first(where: { $0.name == "issueKey" })?.value,
               let issue = appState.issues.first(where: { $0.key == issueKey }) {
                appState.startTimer(for: issue)
            }
        default:
            break
        }
    }
}
