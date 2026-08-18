import Foundation

/// Thin async client for DeepSeek's OpenAI-compatible Chat Completions endpoint.
/// Key/model are injected from Info.plist (from gitignored Secrets.xcconfig); when
/// absent the client reports `notConfigured` and callers use the local fallback line.
enum DeepSeekClient {
    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private static let defaultModel = "deepseek-v4-flash"

    struct Config {
        let apiKey: String
        let model: String
    }

    enum ClientError: Error {
        case notConfigured
        case badResponse(Int)
        case emptyContent
    }

    static func loadConfig() -> Config? {
        let info = Bundle.main.infoDictionary
        let rawKey = (info?["DEEPSEEK_API_KEY"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Empty or an unresolved build-setting placeholder ("$(...)") means "not configured".
        guard !rawKey.isEmpty, !rawKey.hasPrefix("$(") else { return nil }

        let rawModel = (info?["DEEPSEEK_MODEL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (rawModel.isEmpty || rawModel.hasPrefix("$(")) ? defaultModel : rawModel
        return Config(apiKey: rawKey, model: model)
    }

    static var isConfigured: Bool { loadConfig() != nil }

    static func generateLine(
        selected: String,
        others: [String],
        languageCode: String
    ) async throws -> String {
        guard let config = loadConfig() else { throw ClientError.notConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatRequest(
            model: config.model,
            temperature: 1.3,
            maxTokens: 60,
            stream: false,
            messages: [
                .init(role: "system", content: SceneLine.systemPrompt(languageCode: languageCode)),
                .init(role: "user", content: SceneLine.userPrompt(selected: selected, others: others))
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badResponse(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content ?? ""
        let cleaned = SceneLine.sanitize(content)
        guard !cleaned.isEmpty else { throw ClientError.emptyContent }
        return cleaned
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let temperature: Double
        let maxTokens: Int
        let stream: Bool
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, temperature, stream, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
