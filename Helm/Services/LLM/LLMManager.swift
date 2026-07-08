import Foundation

/// Resolves the correct `LLMService` for the current configuration and exposes a
/// single entry point the rest of the app can call.
struct LLMManager {
    let config: LLMConfig

    private var service: LLMService {
        switch config.provider {
        case .anthropic:
            return AnthropicService(config: config)
        case .openAI, .custom:
            // Custom endpoints are assumed OpenAI-compatible.
            return OpenAIService(config: config)
        }
    }

    func complete(messages: [LLMMessage], maxTokens: Int = 1024, temperature: Double = 0.4) async throws -> String {
        try await service.complete(messages: messages, maxTokens: maxTokens, temperature: temperature)
    }
}
