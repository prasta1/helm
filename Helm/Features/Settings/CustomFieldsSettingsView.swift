import SwiftUI
import SwiftData

/// Manages user-defined custom fields for deals and contacts — the mechanism
/// that lets the CRM grow with the user's evolving needs.
struct CustomFieldsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomFieldDefinition.sortOrder) private var fields: [CustomFieldDefinition]
    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]

    @State private var editing: CustomFieldDefinition?
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(CustomFieldEntity.allCases) { entity in
                let entityFields = fields.filter { $0.entity == entity }
                if !entityFields.isEmpty {
                    Section("\(entity.title) Fields") {
                        ForEach(entityFields) { field in
                            Button {
                                editing = field
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(field.name).foregroundStyle(.primary)
                                        Text(scopeLabel(field)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Chip(text: field.type.title, color: Theme.Palette.accent)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet { modelContext.delete(entityFields[index]) }
                            try? modelContext.save()
                        }
                    }
                }
            }

            if fields.isEmpty {
                ContentUnavailableView("No Custom Fields", systemImage: "slider.horizontal.3", description: Text("Add fields to capture the details that matter to you."))
            }
        }
        .navigationTitle("Custom Fields")
        .toolbar {
            ToolbarItem {
                Button { showingNew = true } label: { Label("Add Field", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) {
            CustomFieldEditor(field: nil, pipelines: pipelines)
        }
        .sheet(item: $editing) { field in
            CustomFieldEditor(field: field, pipelines: pipelines)
        }
    }

    private func scopeLabel(_ field: CustomFieldDefinition) -> String {
        if let pipeline = field.pipeline { return "Only in \(pipeline.name)" }
        return "All \(field.entity.title.lowercased())s"
    }
}

/// Create / edit a single custom field definition.
private struct CustomFieldEditor: View {
    let field: CustomFieldDefinition?
    let pipelines: [Pipeline]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: CustomFieldType = .text
    @State private var entity: CustomFieldEntity = .deal
    @State private var pipelineID: UUID?
    @State private var optionsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Field Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(CustomFieldType.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Applies To", selection: $entity) {
                        ForEach(CustomFieldEntity.allCases) { Text($0.title).tag($0) }
                    }
                }

                if entity == .deal {
                    Section("Scope") {
                        Picker("Pipeline", selection: $pipelineID) {
                            Text("All pipelines").tag(Optional<UUID>.none)
                            ForEach(pipelines) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                if type == .singleSelect {
                    Section("Options") {
                        TextField("Comma-separated options", text: $optionsText, axis: .vertical)
                            .lineLimit(1...4)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(field == nil ? "New Field" : "Edit Field")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func load() {
        guard let field else { return }
        name = field.name
        type = field.type
        entity = field.entity
        pipelineID = field.pipeline?.id
        optionsText = field.options.joined(separator: ", ")
    }

    private func save() {
        let options = optionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let pipeline = pipelines.first { $0.id == pipelineID }

        if let field {
            field.name = name
            field.type = type
            field.entity = entity
            field.pipeline = entity == .deal ? pipeline : nil
            field.options = options
        } else {
            let new = CustomFieldDefinition(
                name: name,
                type: type,
                entity: entity,
                options: options,
                sortOrder: 0,
                pipeline: entity == .deal ? pipeline : nil
            )
            modelContext.insert(new)
        }
        try? modelContext.save()
        dismiss()
    }
}
