import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isConfigured {
            TaskListView()
        } else {
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    VStack(spacing: 8) {
                        Text("Welcome to JiraTimeTracker")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Track time on Jira issues right from your Mac menu bar.\nConnect your Jira Cloud account to get started.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }

                    Spacer()

                    SettingsView()
                        .frame(maxWidth: 500)

                    Spacer()
                }
            }
        }
    }
}
