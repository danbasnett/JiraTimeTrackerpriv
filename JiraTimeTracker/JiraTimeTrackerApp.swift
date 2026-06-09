import SwiftUI

@main
struct JiraTimeTrackerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }

        MenuBarExtra {
            MenuBarTimerView()
                .environment(appState)
        } label: {
            Image(systemName: appState.isTimerRunning ? "clock.fill" : "clock")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
