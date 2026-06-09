import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var baseURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    @State private var showUninstallConfirmation: Bool = false

    private var isFormValid: Bool {
        !baseURL.isEmpty && !email.isEmpty && !apiToken.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Instance URL", text: $baseURL, prompt: Text("company.atlassian.net"))
                    .autocorrectionDisabled()
            } header: {
                Text("Jira Cloud Instance")
            } footer: {
                Text("Enter just the domain, e.g. **company.atlassian.net**")
            }

            Section("Credentials") {
                TextField("Email", text: $email, prompt: Text("you@company.com"))
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("API Token", text: $apiToken, prompt: Text("Your Jira API token"))
            }

            Section {
                Link(destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!) {
                    HStack {
                        Label("Create an API Token", systemImage: "key.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Sign in to your Atlassian account")
                    Text("2. Click \"Create API token\"")
                    Text("3. Copy the token and paste it above")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Need a token?")
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!isFormValid || isTesting)

                if let result = testResult {
                    Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testSuccess ? .green : .red)
                        .font(.callout)
                }
            }

            Section {
                Button("Save & Connect") {
                    save()
                }
                .disabled(!isFormValid)
                .keyboardShortcut(.return, modifiers: .command)
                .fontWeight(.semibold)
            }

            if appState.isConfigured {
                Section {
                    Button("Disconnect", role: .destructive) {
                        appState.clearCredentials()
                        baseURL = ""
                        email = ""
                        apiToken = ""
                        testResult = nil
                    }
                }
            }

            Section {
                Button("Uninstall JiraTimeTracker...", role: .destructive) {
                    showUninstallConfirmation = true
                }
                Text("Removes all saved data, moves the app to Trash, and quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            baseURL = appState.jiraBaseURL
            email = appState.jiraEmail
            apiToken = appState.jiraAPIToken
        }
        .confirmationDialog(
            "Uninstall JiraTimeTracker?",
            isPresented: $showUninstallConfirmation
        ) {
            Button("Uninstall & Quit", role: .destructive) {
                performUninstall()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your saved credentials, app data, and move the app to Trash. This cannot be undone.")
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            let result = await AppState.testCredentials(
                baseURL: baseURL,
                email: email,
                apiToken: apiToken
            )
            isTesting = false
            switch result {
            case .success(let user):
                testSuccess = true
                testResult = "Connected as \(user.displayName)"
            case .failure(let error):
                testSuccess = false
                testResult = error.localizedDescription
            }
        }
    }

    private func performUninstall() {
        appState.clearCredentials()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "activeTimerIssueKey")
        defaults.removeObject(forKey: "activeTimerIssueSummary")
        defaults.removeObject(forKey: "activeTimerStart")
        defaults.removeObject(forKey: "filter_statusFilter")
        defaults.removeObject(forKey: "filter_projectKey")
        defaults.removeObject(forKey: "filter_statusName")
        defaults.removeObject(forKey: "filter_assignedToMe")

        SharedData.saveTimerState(nil)
        if let groupDefaults = SharedData.defaults {
            groupDefaults.removeObject(forKey: "activeTimer")
            groupDefaults.removeObject(forKey: "recentIssues")
            groupDefaults.removeObject(forKey: "openIssueCount")
            groupDefaults.synchronize()
        }

        let appPath = Bundle.main.bundlePath
        let escaped = appPath.replacingOccurrences(of: "'", with: "'\\''")
        let script = "sleep 1 && osascript -e 'tell application \"Finder\" to delete POSIX file \"\(escaped)\"' 2>/dev/null || rm -rf '\(escaped)'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func save() {
        appState.jiraBaseURL = baseURL
        appState.jiraEmail = email
        appState.jiraAPIToken = apiToken
        do {
            try appState.saveCredentials()
            appState.showSettings = false
            Task {
                await appState.refreshData()
            }
        } catch {
            testResult = "Failed to save: \(error.localizedDescription)"
            testSuccess = false
        }
    }
}
