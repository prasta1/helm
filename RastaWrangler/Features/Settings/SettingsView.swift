import SwiftUI
import SwiftData

/// App settings: appearance, LLM provider + keys, Google Calendar, Granola, and
/// custom-field management.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    // Secrets are edited via local state and committed to the Keychain, so we
    // don't hit the Keychain on every keystroke.
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var customKey = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        @Bindable var settings = settings

        return Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            aiSection(settings: settings)

            Section("Google Calendar") {
                TextField("OAuth Client ID", text: $settings.googleClientID)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Text("Create an OAuth client (iOS type) for bundle id com.rastawrangler.app in Google Cloud Console, enable the Calendar API, then sign in from the Calendar tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Granola") {
                #if os(macOS)
                Button("Re-select Granola Cache…") {
                    settings.granolaBookmark = nil
                }
                Text(settings.granolaBookmark == nil
                     ? "You'll be asked to grant access on your next import."
                     : "Access granted. Import from the Meetings tab.")
                    .font(.caption).foregroundStyle(.secondary)
                #else
                Text("Automatic Granola import is available in the macOS app. On this device, add meetings manually or sync from your Mac via iCloud.")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            }

            Section("Customization") {
                NavigationLink {
                    CustomFieldsSettingsView()
                } label: {
                    Label("Custom Fields", systemImage: "slider.horizontal.3")
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Data", value: "Stored on device (SwiftData)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            anthropicKey = settings.anthropicAPIKey
            openAIKey = settings.openAIAPIKey
            customKey = settings.customAPIKey
        }
    }

    // MARK: AI section

    @ViewBuilder
    private func aiSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings

        Section("AI Provider") {
            Picker("Provider", selection: $settings.llmProvider) {
                ForEach(LLMProviderKind.allCases) { Text($0.title).tag($0) }
            }

            switch settings.llmProvider {
            case .anthropic:
                TextField("Model", text: $settings.anthropicModel)
                SecureField("API Key", text: $anthropicKey)
                    .onSubmit { settings.anthropicAPIKey = anthropicKey }
                    .onChange(of: anthropicKey) { settings.anthropicAPIKey = anthropicKey }
            case .openAI:
                TextField("Model", text: $settings.openAIModel)
                SecureField("API Key", text: $openAIKey)
                    .onChange(of: openAIKey) { settings.openAIAPIKey = openAIKey }
            case .custom:
                TextField("Base URL", text: $settings.customBaseURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                TextField("Model", text: $settings.customModel)
                SecureField("API Key (optional)", text: $customKey)
                    .onChange(of: customKey) { settings.customAPIKey = customKey }
            }

            Button {
                testConnection()
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "bolt.horizontal")
                    if isTesting { Spacer(); ProgressView() }
                }
            }
            .disabled(isTesting)

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult.hasPrefix("✅") ? Theme.Palette.green : Theme.Palette.red)
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let assistant = AIAssistant(manager: LLMManager(config: settings.activeLLMConfig))
        Task {
            do {
                _ = try await assistant.ask("Reply with just the word: connected.")
                testResult = "✅ Connected successfully."
            } catch {
                testResult = "❌ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppSettings())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
