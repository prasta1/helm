import SwiftUI
import SwiftData

/// Editor for a single contact, including linked deals, custom fields, and an
/// AI prep brief.
struct ContactDetailView: View {
    @Bindable var contact: Contact
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var fieldDefinitions: [CustomFieldDefinition]
    @State private var showingBrief = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: Theme.Spacing.sm) {
                        AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 72)
                        Text(contact.name).font(.title3.weight(.semibold))
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                TextField("Name", text: $contact.name)
                TextField("Title", text: $contact.title)
                TextField("Company", text: $contact.company)
                TextField("Email", text: $contact.email)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
                TextField("Phone", text: $contact.phone)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
                TextField("Notes", text: $contact.notes, axis: .vertical)
                    .lineLimit(3...10)
            }

            if !applicableFields.isEmpty {
                Section("Custom Fields") {
                    ForEach(applicableFields) { field in
                        CustomFieldRow(
                            field: field,
                            value: contact.customValues.first { $0.definitionID == field.id },
                            ensureValue: { ensureValue(for: field) }
                        )
                    }
                }
            }

            if !contact.deals.isEmpty {
                Section("Deals") {
                    ForEach(contact.deals) { deal in
                        HStack {
                            Image(systemName: deal.pipeline?.iconSystemName ?? "square.stack")
                                .foregroundStyle(Color(hex: deal.pipeline?.colorHex ?? "#6B7280"))
                            VStack(alignment: .leading) {
                                Text(deal.title)
                                Text(deal.stage?.name ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("AI Assistant") {
                if settings.isLLMConfigured {
                    Button {
                        showingBrief = true
                    } label: {
                        Label("Generate Prep Brief", systemImage: "sparkles")
                    }
                } else {
                    Label("Add an LLM API key in Settings to enable AI actions.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(contact.name.isEmpty ? "Contact" : contact.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { try? modelContext.save(); dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    modelContext.delete(contact)
                    try? modelContext.save()
                    dismiss()
                } label: { Image(systemName: "trash") }
            }
        }
        .sheet(isPresented: $showingBrief) {
            AIResultSheet(title: "Prep Brief") {
                try await AIAssistant(manager: LLMManager(config: settings.activeLLMConfig)).prepBrief(for: contact)
            } onSave: { text in
                contact.notes += (contact.notes.isEmpty ? "" : "\n\n") + text
                try? modelContext.save()
            }
        }
    }

    private var applicableFields: [CustomFieldDefinition] {
        fieldDefinitions
            .filter { $0.entity == .contact }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func ensureValue(for field: CustomFieldDefinition) -> CustomFieldValue {
        if let existing = contact.customValues.first(where: { $0.definitionID == field.id }) {
            return existing
        }
        let value = CustomFieldValue(definitionID: field.id)
        value.contact = contact
        modelContext.insert(value)
        return value
    }
}
