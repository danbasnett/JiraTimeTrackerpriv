import SwiftUI
import CloudKit
#if os(iOS)
import ActivityKit
#endif

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await CloudKitService.shared.syncFromCloud()
        NotificationCenter.default.post(name: .cloudKitTimerChanged, object: nil)
        return .newData
    }
}
#elseif os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task {
            await CloudKitService.shared.syncFromCloud()
            NotificationCenter.default.post(name: .cloudKitTimerChanged, object: nil)
        }
    }
}
#endif

@main
struct JiraTimeTrackerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await appState.syncFromCloud()
                    #if os(iOS)
                    observePushToStartToken()
                    #endif
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await appState.syncFromCloud() }
                        appState.ensureLiveActivity()
                    }
                }
        }

        #if os(iOS)
        .backgroundTask(.appRefresh("timer-sync")) {
            await CloudKitService.shared.syncFromCloud()
        }
        #endif

        #if os(macOS)
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
        #endif
    }

    #if os(iOS)
    private func observePushToStartToken() {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        appState.pushTokenStatus = enabled ? "Live Activities enabled, waiting for token…" : "Live Activities DISABLED in Settings"

        if !enabled { return }

        Task {
            for await tokenData in Activity<TimerActivityAttributes>.pushToStartTokenUpdates {
                let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
                await CloudKitService.shared.savePushToStartToken(tokenHex)
                await MainActor.run {
                    appState.pushTokenStatus = "Push token registered (\(tokenHex.prefix(8))…)"
                }
            }
        }
    }
    #endif
}
