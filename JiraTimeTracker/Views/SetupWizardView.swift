import SwiftUI

struct SetupWizardView: View {
    @Environment(AppState.self) private var appState
    @State private var step: SetupStep = .welcome
    @State private var baseURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false

    enum SetupStep: Int, CaseIterable {
        case welcome
        case instance
        case credentials
        case connect
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome:
            return true
        case .instance:
            return !baseURL.isEmpty
        case .credentials:
            return !email.isEmpty && !apiToken.isEmpty
        case .connect:
            return testSuccess
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            Group {
                switch step {
                case .welcome:
                    welcomeStep
                case .instance:
                    instanceStep
                case .credentials:
                    credentialsStep
                case .connect:
                    connectStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            navigationButtons
                .padding(20)
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.element) { index, s in
                if index > 0 {
                    Rectangle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                }

                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal, 60)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Welcome to JiraTimeTracker")
                .font(.title2)
                .fontWeight(.bold)

            Text("Track time on Jira issues right from your Mac menu bar. Let's connect your Jira Cloud account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()
        }
    }

    private var instanceStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Your Jira Instance")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enter the domain of your Jira Cloud instance.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("company.atlassian.net", text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .autocorrectionDisabled()
                .onSubmit { advanceIfPossible() }

            Text("Just the domain — no https:// or trailing paths.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private var credentialsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Your Credentials")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enter your Atlassian email and an API token.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("you@company.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("API Token", text: $apiToken)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { advanceIfPossible() }
            }
            .frame(maxWidth: 300)

            Link(destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!) {
                HStack(spacing: 4) {
                    Text("Create an API token")
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .font(.callout)
            }

            Spacer()
        }
    }

    private var connectStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if isTesting {
                ProgressView()
                    .controlSize(.large)

                Text("Testing connection...")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else if testSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Connected!")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let result = testResult {
                    Text(result)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "network")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Test Connection")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Let's make sure everything works.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button("Test Connection") {
                    testConnection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting)

                if let result = testResult, !testSuccess {
                    Label(result, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .frame(maxWidth: 340)
                }
            }

            Spacer()
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation {
                        if let prev = SetupStep(rawValue: step.rawValue - 1) {
                            step = prev
                        }
                    }
                }
            }

            Spacer()

            if step == .connect {
                Button("Finish") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!testSuccess)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Continue") {
                    advanceIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
                .keyboardShortcut(.return)
            }
        }
    }

    // MARK: - Actions

    private func advanceIfPossible() {
        guard canAdvance else { return }
        withAnimation {
            if let next = SetupStep(rawValue: step.rawValue + 1) {
                step = next
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        testSuccess = false
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
                testResult = "Signed in as \(user.displayName)"
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
            Task {
                await appState.refreshData()
            }
        } catch {
            testResult = "Failed to save: \(error.localizedDescription)"
            testSuccess = false
        }
    }
}
