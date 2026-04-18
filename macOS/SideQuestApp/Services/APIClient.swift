import Foundation
import os.log

enum APIError: Error {
    case networkError
    case networkTimeout
    case serverError
    case decodingError
    case invalidURL
}

actor APIClient {
    private let apiBaseURL: URL
    private let bearerToken: String

    init(apiBaseURL: String, bearerToken: String) {
        self.apiBaseURL = URL(string: apiBaseURL)
            ?? URL(string: "https://api.trysidequest.ai")!
        self.bearerToken = bearerToken
    }

    // Accessors for EventSyncManager
    func getBaseURL() -> URL {
        return apiBaseURL
    }

    func getBearerToken() -> String {
        return bearerToken
    }

    func fetchQuest() async throws -> QuestData {
        // Construct /quest endpoint URL
        let questURL = apiBaseURL.appendingPathComponent("quest")

        // Create request with bearer token
        var request = URLRequest(url: questURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0  // 5s timeout for responsiveness

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                ErrorHandler.logNetworkError(NSError(domain: "InvalidResponse", code: -1), endpoint: "/quest")
                throw APIError.serverError
            }

            guard httpResponse.statusCode == 200 else {
                ErrorHandler.logNetworkError(NSError(domain: "HTTPError", code: httpResponse.statusCode), endpoint: "/quest")
                throw APIError.serverError
            }

            // Decode quest data
            let decoder = JSONDecoder()
            let quest = try decoder.decode(QuestData.self, from: data)
            return quest

        } catch URLError.timedOut {
            ErrorHandler.logNetworkError(URLError(.timedOut), endpoint: "/quest")
            throw APIError.networkTimeout
        } catch is DecodingError {
            ErrorHandler.logDecodingError(NSError(domain: "DecodingError", code: -1), type: "QuestData")
            throw APIError.decodingError
        } catch {
            ErrorHandler.logNetworkError(error, endpoint: "/quest")
            throw APIError.networkError
        }
    }
}