import Foundation
import FoundationModels

/// Resolves the correct `LLMService` for the current configuration and exposes a
/// single entry point the rest of the app can call.
struct LLMManager {
    let config: LLMConfig

    private var service: LLMService {
        switch config.provider {
        case .anthropic:
            return AnthropicService(config: config)
        case .openAI, .custom, .appleIntelligence:
            // Custom endpoints are assumed OpenAI-compatible.
            // Apple Intelligence is handled directly in complete() before this is reached.
            return OpenAIService(config: config)
        }
    }

    func complete(messages: [LLMMessage], maxTokens: Int = 1024, temperature: Double = 0.4) async throws -> String {
        if config.provider == .appleIntelligence {
            if #available(macOS 26.0, iOS 26.0, *) {
                return try await completeWithAppleIntelligence(messages: messages)
            }
            throw LLMError.modelUnavailable
        }
        return try await service.complete(messages: messages, maxTokens: maxTokens, temperature: temperature)
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func completeWithAppleIntelligence(messages: [LLMMessage]) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw LLMError.modelUnavailable
        }
        let systemLines = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
        let userLines   = messages.filter { $0.role != .system }.map(\.content).joined(separator: "\n\n")
        let prompt = systemLines.isEmpty ? userLines : "\(systemLines)\n\n\(userLines)"
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
