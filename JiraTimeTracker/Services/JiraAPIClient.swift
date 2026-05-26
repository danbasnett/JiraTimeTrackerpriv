import Foundation

actor JiraAPIClient {
    private let baseURL: String
    private let email: String
    private let apiToken: String

    init(baseURL: String, email: String, apiToken: String) {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http") {
            url = "https://\(url)"
        }
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        self.baseURL = url
        self.email = email
        self.apiToken = apiToken
    }

    private var authHeader: String {
        let credentials = "\(email):\(apiToken)"
        return "Basic \(Data(credentials.utf8).base64EncodedString())"
    }

    private func performRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw JiraError.invalidCredentials
        case 403:
            throw JiraError.forbidden
        case 404:
            throw JiraError.notFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JiraError.apiError(httpResponse.statusCode, message)
        }
    }

    func searchIssues(jql: String, maxResults: Int = 50) async throws -> JiraSearchResponse {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "fields", value: "summary,status,priority,assignee,project,issuetype,timetracking")
        ]
        let queryString = components.percentEncodedQuery ?? ""
        let data = try await performRequest(path: "/rest/api/3/search/jql?\(queryString)")
        do {
            return try await MainActor.run {
                try JSONDecoder().decode(JiraSearchResponse.self, from: data)
            }
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "unreadable"
            throw JiraError.apiError(0, "Decode failed: \(error.localizedDescription)\nResponse: \(raw.prefix(500))")
        }
    }

    func getProjects() async throws -> [JiraProject] {
        let data = try await performRequest(path: "/rest/api/3/project")
        return try await MainActor.run {
            try JSONDecoder().decode([JiraProject].self, from: data)
        }
    }

    func getCurrentUser() async throws -> JiraUser {
        let data = try await performRequest(path: "/rest/api/3/myself")
        return try await MainActor.run {
            try JSONDecoder().decode(JiraUser.self, from: data)
        }
    }

    func logWork(issueKey: String, timeSpentSeconds: Int, comment: String?, started: Date) async throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var bodyDict: [String: Any] = [
            "timeSpentSeconds": timeSpentSeconds,
            "started": formatter.string(from: started)
        ]

        if let comment = comment, !comment.isEmpty {
            bodyDict["comment"] = [
                "type": "doc",
                "version": 1,
                "content": [
                    [
                        "type": "paragraph",
                        "content": [
                            [
                                "type": "text",
                                "text": comment
                            ]
                        ]
                    ]
                ]
            ] as [String: Any]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)
        _ = try await performRequest(path: "/rest/api/3/issue/\(issueKey)/worklog", method: "POST", body: bodyData)
    }
}

enum JiraError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidCredentials
    case forbidden
    case notFound
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Jira URL. Use format: yourcompany.atlassian.net"
        case .invalidResponse:
            return "Invalid response from Jira"
        case .invalidCredentials:
            return "Invalid email or API token"
        case .forbidden:
            return "Access forbidden — check your permissions"
        case .notFound:
            return "Resource not found"
        case .apiError(let code, let msg):
            return "Jira error (\(code)): \(msg)"
        }
    }
}
