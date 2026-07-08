import Foundation

/// Configuration for a single LLM request, derived from `AppSettings`.
struct LLMConfig: Equatable {
    var provider: LLMProviderKind
    var model: String
    var apiKey: String
    /// Base URL for custom / OpenAI-compatible endpoints (e.g. Ollama, LM Studio).
    var baseURL: String?
}

/// A chat message in provider-agnostic form.
struct LLMMessage: Equatable {
    enum Role: String { case system, user, assistant }
    var role: Role
    var content: String

    static func system(_ text: String) -> LLMMessage { .init(role: .system, content: text) }
    static func user(_ text: String) -> LLMMessage { .init(role: .user, content: text) }
    static func assistant(_ text: String) -> LLMMessage { .init(role: .assistant, content: text) }
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case emptyResponse
    case http(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key is configured for the selected provider. Add one in Settings."
        case .invalidURL: return "The endpoint URL is invalid."
        case .emptyResponse: return "The model returned an empty response."
        case let .http(status, body): return "Request failed (HTTP \(status)). \(body)"
        case let .decoding(message): return "Couldn't read the model response: \(message)"
        }
    }
}

/// A provider that can complete a chat conversation.
protocol LLMService {
    /// Returns the assistant's completion for the given messages.
    func complete(messages: [LLMMessage], maxTokens: Int, temperature: Double) async throws -> String
}

extension LLMService {
    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, maxTokens: 1024, temperature: 0.4)
    }
}
