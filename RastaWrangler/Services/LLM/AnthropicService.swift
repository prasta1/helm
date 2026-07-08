import Foundation

/// Calls the Anthropic Messages API (https://docs.anthropic.com).
struct AnthropicService: LLMService {
    let config: LLMConfig
    var session: URLSession = .shared

    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    func complete(messages: [LLMMessage], maxTokens: Int, temperature: Double) async throws -> String {
        guard !config.apiKey.isEmpty else { throw LLMError.missingAPIKey }
        guard let url = URL(string: endpoint) else { throw LLMError.invalidURL }

        // Anthropic takes the system prompt as a top-level field, and only
        // user/assistant turns in `messages`.
        let systemPrompt = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let turns = messages.filter { $0.role != .system }.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }

        var payload: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": turns,
        ]
        if !systemPrompt.isEmpty {
            payload["system"] = systemPrompt
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        // Response shape: { content: [ { type: "text", text: "..." } ] }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else {
            throw LLMError.decoding("Unexpected Anthropic response shape.")
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(status: http.statusCode, body: body)
        }
    }
}
