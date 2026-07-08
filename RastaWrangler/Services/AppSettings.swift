import Foundation
import Observation
import SwiftUI

/// Observable app-wide settings. Non-secret preferences are stored directly in
/// `UserDefaults`; secrets (API keys) live in the Keychain.
///
/// The `UserDefaults`-backed properties are written as computed properties that
/// participate in Observation via `access(keyPath:)` / `withMutation(keyPath:)`,
/// so SwiftUI views update when they change — without relying on `didSet`
/// interacting with the `@Observable` macro.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain = KeychainStore.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: LLM (UserDefaults-backed)

    var llmProvider: LLMProviderKind {
        get {
            access(keyPath: \.llmProvider)
            return LLMProviderKind(rawValue: defaults.string(forKey: Keys.llmProvider) ?? "") ?? .anthropic
        }
        set { withMutation(keyPath: \.llmProvider) { defaults.set(newValue.rawValue, forKey: Keys.llmProvider) } }
    }

    var anthropicModel: String {
        get { access(keyPath: \.anthropicModel); return defaults.string(forKey: Keys.anthropicModel) ?? "claude-sonnet-5" }
        set { withMutation(keyPath: \.anthropicModel) { defaults.set(newValue, forKey: Keys.anthropicModel) } }
    }

    var openAIModel: String {
        get { access(keyPath: \.openAIModel); return defaults.string(forKey: Keys.openAIModel) ?? "gpt-4o" }
        set { withMutation(keyPath: \.openAIModel) { defaults.set(newValue, forKey: Keys.openAIModel) } }
    }

    var customModel: String {
        get { access(keyPath: \.customModel); return defaults.string(forKey: Keys.customModel) ?? "local-model" }
        set { withMutation(keyPath: \.customModel) { defaults.set(newValue, forKey: Keys.customModel) } }
    }

    var customBaseURL: String {
        get { access(keyPath: \.customBaseURL); return defaults.string(forKey: Keys.customBaseURL) ?? "http://localhost:11434/v1" }
        set { withMutation(keyPath: \.customBaseURL) { defaults.set(newValue, forKey: Keys.customBaseURL) } }
    }

    // MARK: Calendar

    var calendarSource: CalendarSourceKind {
        get {
            access(keyPath: \.calendarSource)
            return CalendarSourceKind(rawValue: defaults.string(forKey: Keys.calendarSource) ?? "") ?? .google
        }
        set { withMutation(keyPath: \.calendarSource) { defaults.set(newValue.rawValue, forKey: Keys.calendarSource) } }
    }

    /// Device calendars shown in the week view. `nil` means "all calendars";
    /// a set (possibly empty) means only those calendar identifiers.
    var enabledCalendarIDs: Set<String>? {
        get {
            access(keyPath: \.enabledCalendarIDs)
            guard let array = defaults.array(forKey: Keys.enabledCalendarIDs) as? [String] else { return nil }
            return Set(array)
        }
        set {
            withMutation(keyPath: \.enabledCalendarIDs) {
                if let newValue {
                    defaults.set(Array(newValue), forKey: Keys.enabledCalendarIDs)
                } else {
                    defaults.removeObject(forKey: Keys.enabledCalendarIDs)
                }
            }
        }
    }

    // MARK: Reminders

    /// Where the Tasks quick-add files new items: `nil` = a Helm task (SwiftData);
    /// otherwise the identifier of an Apple Reminders list.
    var quickAddReminderListID: String? {
        get { access(keyPath: \.quickAddReminderListID); return defaults.string(forKey: Keys.quickAddReminderListID) }
        set {
            withMutation(keyPath: \.quickAddReminderListID) {
                if let newValue {
                    defaults.set(newValue, forKey: Keys.quickAddReminderListID)
                } else {
                    defaults.removeObject(forKey: Keys.quickAddReminderListID)
                }
            }
        }
    }

    // MARK: Google

    var googleClientID: String {
        get { access(keyPath: \.googleClientID); return defaults.string(forKey: Keys.googleClientID) ?? "" }
        set { withMutation(keyPath: \.googleClientID) { defaults.set(newValue, forKey: Keys.googleClientID) } }
    }

    // MARK: Granola

    /// Security-scoped bookmark to the Granola cache the user granted access to.
    var granolaBookmark: Data? {
        get { access(keyPath: \.granolaBookmark); return defaults.data(forKey: Keys.granolaBookmark) }
        set { withMutation(keyPath: \.granolaBookmark) { defaults.set(newValue, forKey: Keys.granolaBookmark) } }
    }

    // MARK: Appearance

    var appearance: AppearanceMode {
        get { access(keyPath: \.appearance); return AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system }
        set { withMutation(keyPath: \.appearance) { defaults.set(newValue.rawValue, forKey: Keys.appearance) } }
    }

    // MARK: Secrets (Keychain-backed; read imperatively)

    var anthropicAPIKey: String {
        get { keychain.string(for: KeychainKey.anthropicAPIKey) ?? "" }
        set { keychain.setString(newValue, for: KeychainKey.anthropicAPIKey) }
    }
    var openAIAPIKey: String {
        get { keychain.string(for: KeychainKey.openAIAPIKey) ?? "" }
        set { keychain.setString(newValue, for: KeychainKey.openAIAPIKey) }
    }
    var customAPIKey: String {
        get { keychain.string(for: KeychainKey.customLLMAPIKey) ?? "" }
        set { keychain.setString(newValue, for: KeychainKey.customLLMAPIKey) }
    }

    // MARK: Derived

    /// Whether the currently selected provider has enough config to be used.
    var isLLMConfigured: Bool {
        switch llmProvider {
        case .anthropic: return !anthropicAPIKey.isEmpty
        case .openAI: return !openAIAPIKey.isEmpty
        case .custom: return !customBaseURL.isEmpty
        }
    }

    /// Builds the LLM configuration for the active provider.
    var activeLLMConfig: LLMConfig {
        switch llmProvider {
        case .anthropic:
            return LLMConfig(provider: .anthropic, model: anthropicModel, apiKey: anthropicAPIKey, baseURL: nil)
        case .openAI:
            return LLMConfig(provider: .openAI, model: openAIModel, apiKey: openAIAPIKey, baseURL: nil)
        case .custom:
            return LLMConfig(provider: .custom, model: customModel, apiKey: customAPIKey, baseURL: customBaseURL)
        }
    }

    private enum Keys {
        static let llmProvider = "settings.llm.provider"
        static let anthropicModel = "settings.llm.anthropic.model"
        static let openAIModel = "settings.llm.openai.model"
        static let customModel = "settings.llm.custom.model"
        static let customBaseURL = "settings.llm.custom.baseURL"
        static let calendarSource = "settings.calendar.source"
        static let enabledCalendarIDs = "settings.calendar.enabledIDs"
        static let quickAddReminderListID = "settings.reminders.quickAddListID"
        static let googleClientID = "settings.google.clientID"
        static let granolaBookmark = "settings.granola.bookmark"
        static let appearance = "settings.appearance"
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
