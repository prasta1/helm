import Foundation
import Security

/// A tiny wrapper around the Keychain for storing secrets (LLM API keys, OAuth
/// tokens). Works identically on macOS and iOS.
struct KeychainStore {
    static let shared = KeychainStore()

    /// Service namespace under which all items are stored.
    private let service = "com.rastawrangler.app"

    // MARK: String helpers

    func setString(_ value: String?, for key: String) {
        guard let value, !value.isEmpty else {
            delete(key)
            return
        }
        set(Data(value.utf8), for: key)
    }

    func string(for key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Codable helpers

    func setCodable<T: Encodable>(_ value: T?, for key: String) {
        guard let value else { delete(key); return }
        if let data = try? JSONEncoder().encode(value) {
            set(data, for: key)
        }
    }

    func codable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = data(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Raw data

    func set(_ data: Data, for key: String) {
        var query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func data(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// Well-known Keychain keys.
enum KeychainKey {
    static let anthropicAPIKey = "llm.anthropic.apiKey"
    static let openAIAPIKey = "llm.openai.apiKey"
    static let customLLMAPIKey = "llm.custom.apiKey"
    static let googleTokens = "google.oauth.tokens"
}
