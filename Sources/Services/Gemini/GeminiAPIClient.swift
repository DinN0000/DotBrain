import Foundation

/// URLSession-based Google Gemini API client
actor GeminiAPIClient {
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Models

    static let flashModel = "gemini-2.5-flash"
    static let proModel = "gemini-2.5-pro"

    // MARK: - Request/Response Types

    struct GenerateContentRequest: Encodable {
        let contents: [Content]
        let generationConfig: GenerationConfig?

        struct Content: Encodable {
            let parts: [Part]
            let role: String?

            struct Part: Encodable {
                let text: String
            }
        }

        struct GenerationConfig: Encodable {
            let maxOutputTokens: Int?
            let temperature: Double?
        }
    }

    struct GenerateContentResponse: Decodable {
        let candidates: [Candidate]?
        let error: APIError?

        struct Candidate: Decodable {
            let content: Content?

            struct Content: Decodable {
                let parts: [Part]?

                struct Part: Decodable {
                    let text: String?
                }
            }
        }

        struct APIError: Decodable {
            let code: Int?
            let message: String?
            let status: String?
        }

        var text: String {
            candidates?
                .first?
                .content?
                .parts?
                .compactMap { $0.text }
                .joined() ?? ""
        }
    }

    // MARK: - API Call

    /// Send a message to Gemini and get the text response
    func sendMessage(
        model: String,
        maxTokens: Int,
        userMessage: String
    ) async throws -> String {
        guard let apiKey = KeychainService.getGeminiAPIKey() else {
            throw GeminiAPIError.noAPIKey
        }

        let endpoint = "\(baseURL)/\(model):generateContent"

        guard let url = URL(string: endpoint) else {
            throw GeminiAPIError.invalidURL
        }

        let request = GenerateContentRequest(
            contents: [
                .init(
                    parts: [.init(text: userMessage)],
                    role: "user"
                )
            ],
            generationConfig: .init(
                maxOutputTokens: maxTokens,
                temperature: 0.7
            )
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        // Handle HTTP errors first — try to extract error message from response body
        if httpResponse.statusCode != 200 {
            if let geminiResponse = try? JSONDecoder().decode(GenerateContentResponse.self, from: data),
               let error = geminiResponse.error {
                throw GeminiAPIError.apiError(
                    status: error.code ?? httpResponse.statusCode,
                    message: error.message ?? "HTTP \(httpResponse.statusCode)"
                )
            }
            // Fallback: try to read raw error text
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            let preview = String(rawBody.prefix(200))
            print("[GeminiAPI] HTTP \(httpResponse.statusCode): \(preview)")
            throw GeminiAPIError.httpError(status: httpResponse.statusCode)
        }

        let geminiResponse: GenerateContentResponse
        do {
            geminiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            print("[GeminiAPI] JSON 파싱 실패: \(String(rawBody.prefix(300)))")
            throw GeminiAPIError.invalidResponse
        }

        if let error = geminiResponse.error {
            throw GeminiAPIError.apiError(
                status: error.code ?? 0,
                message: error.message ?? "Unknown error"
            )
        }

        let text = geminiResponse.text
        if text.isEmpty {
            throw GeminiAPIError.emptyResponse
        }

        return text
    }
}

// MARK: - Errors

enum GeminiAPIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case httpError(status: Int)
    case apiError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Gemini API 키가 설정되지 않았습니다"
        case .invalidURL:
            return "잘못된 URL"
        case .invalidResponse:
            return "잘못된 응답"
        case .emptyResponse:
            return "빈 응답"
        case .httpError(let status):
            return "HTTP 오류: \(status)"
        case .apiError(_, let message):
            return message
        }
    }
}
