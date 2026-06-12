import SwiftUI

@main
struct JiraTimeTrackerApp: App {
    @State private var appState = AppState()
    @State private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(updateChecker)
                .task {
                    await updateChecker.checkForUpdates()
                }
        }

        MenuBarExtra {
            MenuBarTimerView()
                .environment(appState)
                .environment(updateChecker)
        } label: {
            Image(systemName: appState.isTimerRunning ? "clock.fill" : "clock")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(updateChecker)
        }
    }
}
