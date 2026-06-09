import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var baseURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false

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
                Link(destination: URL(string: "https://id.atlassian.net/manage-profile/security/api-tokens")!) {
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
