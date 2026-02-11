import Foundation

/// URLSession-based Claude API client
actor ClaudeAPIClient {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Models

    static let haikuModel = "claude-haiku-4-5-20251001"
    static let sonnetModel = "claude-sonnet-4-5-20250929"

    // MARK: - Request/Response Types

    struct MessageRequest: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    struct MessageResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        var text: String {
            content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined()
        }
    }

    struct APIError: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let type: String
            let message: String
        }
    }

    // MARK: - API Call

    /// Send a message to Claude and get the text response
    func sendMessage(
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> String {
        guard let apiKey = KeychainService.getAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        guard let url = URL(string: baseURL) else {
            throw ClaudeAPIError.invalidURL
        }

        let request = MessageRequest(
            model: model,
            max_tokens: maxTokens,
            messages: [.init(role: "user", content: userMessage)]
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw ClaudeAPIError.apiError(
                    status: httpResponse.statusCode,
                    message: apiError.error.message
                )
            }
            throw ClaudeAPIError.httpError(status: httpResponse.statusCode)
        }

        let messageResponse = try JSONDecoder().decode(MessageResponse.self, from: data)
        let text = messageResponse.text
        guard !text.isEmpty else {
            throw ClaudeAPIError.emptyResponse
        }
        return text
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case httpError(status: Int)
    case apiError(status: Int, message: String)
    case jsonParseFailed(raw: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API 키가 설정되지 않았습니다"
        case .invalidURL:
            return "잘못된 API URL"
        case .invalidResponse:
            return "잘못된 응답"
        case .emptyResponse:
            return "빈 응답"
        case .httpError(let status):
            return "HTTP 오류: \(status)"
        case .apiError(_, let message):
            return message
        case .jsonParseFailed(let raw):
            return "JSON 파싱 실패: \(raw.prefix(100))"
        }
    }
}
