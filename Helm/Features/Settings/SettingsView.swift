import SwiftUI
import SwiftData
import FoundationModels

/// App settings: appearance, LLM provider + keys, calendar source, Google Calendar, Granola, and
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
    @State private var newRepo = ""
    @State private var remindersService = RemindersService()
    @State private var reminderLists: [ReminderList] = []

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

            calendarSection(settings: settings)

            remindersSection(settings: settings)

            githubSection(settings: settings)

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
        .task {
            guard reminderLists.isEmpty else { return }
            if !remindersService.hasFullAccess, !remindersService.isDenied {
                _ = try? await remindersService.requestAccess()
            }
            reminderLists = remindersService.lists()
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
            case .appleIntelligence:
                appleIntelligenceStatus
            }

            if settings.llmProvider != .appleIntelligence {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Label("Test Connection", systemImage: "bolt.horizontal")
                        if isTesting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isTesting)
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult.hasPrefix("✅") ? Theme.Palette.success : Theme.Palette.danger)
            }
        }
    }

    // MARK: Calendar section

    @ViewBuilder
    private func calendarSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings

        Section("Calendar") {
            Picker("Source", selection: $settings.calendarSource) {
                ForEach(CalendarSourceKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if settings.calendarSource == .google {
                TextField("OAuth Client ID", text: $settings.googleClientID)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Text("Create an OAuth client (iOS type) for bundle id com.helm.app in Google Cloud Console, enable the Calendar API, then sign in from the Calendar tab.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Reads calendars already set up on this device (System Settings → Internet Accounts). You'll be asked to allow access the first time you open the Calendar tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Reminders section

    @ViewBuilder
    private func remindersSection(settings: AppSettings) -> some View {
        if !reminderLists.isEmpty {
            Section("Apple Reminders") {
                ForEach(reminderLists) { list in
                    Toggle(isOn: reminderListBinding(for: list.id, settings: settings)) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: list.colorHex))
                                .frame(width: 10, height: 10)
                            Text(list.title)
                        }
                    }
                }
                Text("Hidden lists are excluded from the Tasks view.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func reminderListBinding(for listID: String, settings: AppSettings) -> Binding<Bool> {
        Binding(
            get: {
                guard let enabled = settings.enabledReminderListIDs else { return true }
                return enabled.contains(listID)
            },
            set: { isOn in
                var enabled = settings.enabledReminderListIDs ?? Set(reminderLists.map(\.id))
                if isOn { enabled.insert(listID) } else { enabled.remove(listID) }
                settings.enabledReminderListIDs = enabled
            }
        )
    }

    // MARK: GitHub section

    @ViewBuilder
    private func githubSection(settings: AppSettings) -> some View {
        Section("GitHub") {
            ForEach(settings.trackedGitHubRepos, id: \.self) { repo in
                HStack {
                    Image(systemName: "arrow.triangle.pull")
                        .foregroundStyle(.secondary)
                    Text(repo)
                    Spacer()
                    Button {
                        settings.trackedGitHubRepos.removeAll { $0 == repo }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(repo)")
                }
            }

            HStack {
                TextField("owner/repo", text: $newRepo)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { addRepo(settings: settings) }
                Button("Add") { addRepo(settings: settings) }
                    .disabled(newRepo.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("Add public repos to track open issues and PRs as tasks. No sign-in required.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addRepo(settings: AppSettings) {
        let slug = newRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !settings.trackedGitHubRepos.contains(slug) else { return }
        settings.trackedGitHubRepos.append(slug)
        newRepo = ""
    }

    @ViewBuilder
    private var appleIntelligenceStatus: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                Label("Apple Intelligence is ready on this device.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.success)
                    .font(.caption)
            case .unavailable(.appleIntelligenceNotEnabled):
                Label("Apple Intelligence is not enabled. Turn it on in System Settings → Apple Intelligence & Siri.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Palette.warning)
                    .font(.caption)
            case .unavailable(.modelNotReady):
                Label("Model is downloading. Try again once it finishes.", systemImage: "arrow.down.circle")
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .font(.caption)
            case .unavailable(.deviceNotEligible):
                Label("This device does not support Apple Intelligence.", systemImage: "xmark.circle")
                    .foregroundStyle(Theme.Palette.danger)
                    .font(.caption)
            case .unavailable:
                Label("Apple Intelligence is unavailable.", systemImage: "xmark.circle")
                    .foregroundStyle(Theme.Palette.danger)
                    .font(.caption)
            }
        } else {
            Label("Requires macOS 26 or iOS 26 or later.", systemImage: "xmark.circle")
                .foregroundStyle(Theme.Palette.danger)
                .font(.caption)
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
