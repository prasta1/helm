import SwiftUI
import SwiftData

/// Full editor for a deal: core fields, custom fields, linked contacts, an
/// activity timeline, and AI actions.
struct DealDetailView: View {
    @Bindable var deal: Deal
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var fieldDefinitions: [CustomFieldDefinition]

    @State private var newActivityKind: ActivityKind = .note
    @State private var newActivityText: String = ""
    @State private var aiAction: AIAction?
    @State private var showingContactPicker = false

    var body: some View {
        Form {
            coreSection
            customFieldsSection
            contactsSection
            activitySection
            aiSection
        }
        .formStyle(.grouped)
        .navigationTitle(deal.title.isEmpty ? "Deal" : deal.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save(); dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) { delete() } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(item: $aiAction) { action in
            AIResultSheet(title: action.title, run: { try await action.run(assistant, deal) }) { text in
                addActivity(kind: .note, title: action.title, body: text, source: .ai)
            }
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView(selected: deal.contacts) { picked in
                deal.contacts = picked
                save()
            }
        }
    }

    // MARK: Core

    private var coreSection: some View {
        Section("Details") {
            TextField("Title", text: $deal.title)
            TextField("Notes", text: $deal.details, axis: .vertical)
                .lineLimit(3...8)

            Picker("Stage", selection: stageBinding) {
                ForEach(deal.pipeline?.orderedStages ?? []) { stage in
                    Text(stage.name).tag(Optional(stage.id))
                }
            }

            Picker("Status", selection: Binding(
                get: { deal.status },
                set: { deal.status = $0 }
            )) {
                ForEach(DealStatus.allCases) { Text($0.title).tag($0) }
            }

            HStack {
                Text("Value")
                Spacer()
                TextField("Amount", value: amountBinding, format: .number)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(maxWidth: 120)
                TextField("USD", text: $deal.currencyCode)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
            }

            DatePicker("Close Date", selection: Binding(
                get: { deal.closeDate ?? Date() },
                set: { deal.closeDate = $0 }
            ), displayedComponents: .date)
        }
    }

    private var stageBinding: Binding<UUID?> {
        Binding(
            get: { deal.stage?.id },
            set: { newID in
                deal.stage = deal.pipeline?.stages.first { $0.id == newID }
            }
        )
    }

    /// Non-optional bridge for the amount field (blank/0 clears the value).
    private var amountBinding: Binding<Double> {
        Binding(
            get: { deal.amount ?? 0 },
            set: { deal.amount = $0 == 0 ? nil : $0 }
        )
    }

    // MARK: Custom fields

    private var applicableFields: [CustomFieldDefinition] {
        fieldDefinitions
            .filter { $0.entity == .deal }
            .filter { $0.pipeline == nil || $0.pipeline?.id == deal.pipeline?.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    private var customFieldsSection: some View {
        if !applicableFields.isEmpty {
            Section("Custom Fields") {
                ForEach(applicableFields) { field in
                    CustomFieldRow(
                        field: field,
                        value: deal.customValues.first { $0.definitionID == field.id },
                        ensureValue: { ensureValue(for: field) }
                    )
                }
            }
        }
    }

    private func ensureValue(for field: CustomFieldDefinition) -> CustomFieldValue {
        if let existing = deal.customValues.first(where: { $0.definitionID == field.id }) {
            return existing
        }
        let value = CustomFieldValue(definitionID: field.id)
        value.deal = deal
        modelContext.insert(value)
        return value
    }

    // MARK: Contacts

    private var contactsSection: some View {
        Section {
            ForEach(deal.contacts) { contact in
                HStack {
                    AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 28)
                    VStack(alignment: .leading) {
                        Text(contact.name)
                        if !contact.title.isEmpty {
                            Text(contact.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                deal.contacts.remove(atOffsets: indexSet)
                save()
            }
            Button {
                showingContactPicker = true
            } label: {
                Label("Link Contact", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Contacts")
        }
    }

    // MARK: Activity

    private var activitySection: some View {
        Section("Activity") {
            HStack {
                Picker("", selection: $newActivityKind) {
                    ForEach(ActivityKind.allCases) { kind in
                        Image(systemName: kind.systemImage).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                TextField("Add \(newActivityKind.title.lowercased())…", text: $newActivityText)
                    .onSubmit(commitActivity)

                Button(action: commitActivity) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .disabled(newActivityText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            ForEach(deal.activities.sorted { $0.date > $1.date }) { activity in
                ActivityRow(activity: activity)
            }
            .onDelete { indexSet in
                let sorted = deal.activities.sorted { $0.date > $1.date }
                for index in indexSet { modelContext.delete(sorted[index]) }
                save()
            }
        }
    }

    // MARK: AI

    private var aiSection: some View {
        Section("AI Assistant") {
            if settings.isLLMConfigured {
                ForEach(AIAction.dealActions) { action in
                    Button {
                        aiAction = action
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } else {
                Label("Add an LLM API key in Settings to enable AI actions.", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assistant: AIAssistant {
        AIAssistant(manager: LLMManager(config: settings.activeLLMConfig))
    }

    // MARK: Mutations

    private func commitActivity() {
        let trimmed = newActivityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addActivity(kind: newActivityKind, title: trimmed, body: "", source: .manual)
        newActivityText = ""
    }

    private func addActivity(kind: ActivityKind, title: String, body: String, source: ActivitySource) {
        let activity = Activity(kind: kind, title: title, body: body, source: source)
        activity.deal = deal
        modelContext.insert(activity)
        deal.touch()
        save()
    }

    private func save() {
        deal.touch()
        try? modelContext.save()
    }

    private func delete() {
        modelContext.delete(deal)
        try? modelContext.save()
        dismiss()
    }
}

/// A single AI action bound to a deal.
struct AIAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let run: (AIAssistant, Deal) async throws -> String

    static let dealActions: [AIAction] = [
        AIAction(title: "Suggest Next Steps", systemImage: "list.bullet.clipboard") { assistant, deal in
            try await assistant.suggestNextSteps(for: deal)
        },
        AIAction(title: "Draft Follow-up", systemImage: "envelope.badge") { assistant, deal in
            try await assistant.draftFollowUp(for: deal)
        },
    ]
}
