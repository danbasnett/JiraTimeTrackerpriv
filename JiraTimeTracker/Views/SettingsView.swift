import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var baseURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    #if os(macOS)
    @State private var pushTestResult: String?
    @State private var pushTestSuccess: Bool = false
    @State private var isTestingPush: Bool = false
    #endif

    private var isFormValid: Bool {
        !baseURL.isEmpty && !email.isEmpty && !apiToken.isEmpty
    }

    var body: some View {
        Form {
            Section("Jira Cloud Instance") {
                TextField("Instance URL", text: $baseURL, prompt: Text("company.atlassian.net"))
                #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()
            }

            Section("Credentials") {
                TextField("Email", text: $email, prompt: Text("you@company.com"))
                    .textContentType(.emailAddress)
                #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                #endif
                    .autocorrectionDisabled()

                SecureField("API Token", text: $apiToken, prompt: Text("Your Jira API token"))
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
                .fontWeight(.semibold)
            }

            if appState.isConfigured {
                Section {
                    Button("Disconnect", role: .destructive) {
                        appState.clearCredentials()
                    }
                }
            }

            #if os(iOS)
            Section("Live Activity") {
                if !appState.pushTokenStatus.isEmpty {
                    Label(appState.pushTokenStatus, systemImage: appState.pushTokenStatus.contains("registered") ? "checkmark.circle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(appState.pushTokenStatus.contains("registered") ? .green : appState.pushTokenStatus.contains("DISABLED") ? .red : .secondary)
                }
            }
            #endif

            #if os(macOS)
            Section("Live Activity Push (iPhone)") {
                HStack {
                    Button("Test Push") {
                        testPush()
                    }
                    .disabled(isTestingPush)

                    if isTestingPush {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let result = pushTestResult {
                    Label(result, systemImage: pushTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(pushTestSuccess ? .green : .red)
                        .font(.caption)
                }

                Text("Starts Live Activities on your iPhone when you start a timer on Mac. Open the iPhone app at least once to register its push token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get an API token:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("1. Go to id.atlassian.net/manage-profile/security/api-tokens")
                        .font(.caption)
                    Text("2. Click 'Create API token'")
                        .font(.caption)
                    Text("3. Copy the token and paste it above")
                        .font(.caption)
                }
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

    #if os(macOS)
    private func testPush() {
        isTestingPush = true
        pushTestResult = nil
        Task {
            let token = await CloudKitService.shared.fetchPushToStartToken()
            guard let token else {
                pushTestSuccess = false
                pushTestResult = "No push token found — open the iPhone app first"
                isTestingPush = false
                return
            }

            await APNSService.shared.sendStartLiveActivity(
                pushToken: token,
                issueKey: "TEST-1",
                issueSummary: "Test Live Activity",
                startTime: Date()
            )

            if let err = await APNSService.shared.lastError {
                pushTestSuccess = false
                pushTestResult = err
            } else {
                pushTestSuccess = true
                pushTestResult = "Push sent! Check your iPhone lock screen"
            }
            isTestingPush = false
        }
    }
    #endif

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
