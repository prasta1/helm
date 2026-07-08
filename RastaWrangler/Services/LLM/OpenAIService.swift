import Foundation

/// Calls the OpenAI Chat Completions API, or any OpenAI-compatible endpoint
/// (Ollama, LM Studio, vLLM, OpenRouter, …) via a custom base URL.
struct OpenAIService: LLMService {
    let config: LLMConfig
    var session: URLSession = .shared

    /// Defaults to OpenAI; overridden by `config.baseURL` for custom providers.
    private var baseURL: String {
        let base = config.baseURL?.trimmingCharacters(in: .whitespaces)
        if let base, !base.isEmpty {
            return base.hasSuffix("/") ? String(base.dropLast()) : base
        }
        return "https://api.openai.com/v1"
    }

    func complete(messages: [LLMMessage], maxTokens: Int, temperature: Double) async throws -> String {
        // Custom/local endpoints may not require a key; hosted OpenAI does.
        if config.provider == .openAI && config.apiKey.isEmpty {
            throw LLMError.missingAPIKey
        }
        guard let url = URL(string: baseURL + "/chat/completions") else { throw LLMError.invalidURL }

        let payload: [String: Any] = [
            "model": config.model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try AnthropicService.validate(response: response, data: data)

        // Response shape: { choices: [ { message: { content: "..." } } ] }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw LLMError.decoding("Unexpected OpenAI response shape.")
        }
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }
}
