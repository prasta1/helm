import SwiftUI
import SwiftData

/// Create or edit a pipeline: its name, color, icon and stages. This is the core
/// of the app's customizability — stages can be added, renamed, recolored,
/// reordered and marked as won/lost terminals.
struct PipelineEditorView: View {
    /// Pass `nil` to create a new pipeline.
    let pipeline: Pipeline?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pipeline.sortOrder) private var allPipelines: [Pipeline]

    @State private var name = ""
    @State private var colorHex = "#3B82F6"
    @State private var iconSystemName = "square.grid.2x2"
    @State private var stages: [StageDraft] = []

    private let iconChoices = ["briefcase", "person.2", "chart.line.uptrend.xyaxis", "heart", "square.grid.2x2", "star", "flag", "target", "building.2", "graduationcap"]
    private let colorChoices = ["#3B82F6", "#8B5CF6", "#1DB954", "#F59E0B", "#E23D3D", "#EC4899", "#14B8A6", "#6B7280"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Pipeline") {
                    TextField("Name", text: $name)

                    HStack {
                        Text("Color")
                        Spacer()
                        ForEach(colorChoices, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }

                    HStack {
                        Text("Icon")
                        Spacer()
                        Picker("Icon", selection: $iconSystemName) {
                            ForEach(iconChoices, id: \.self) { icon in
                                Image(systemName: icon).tag(icon)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Section("Stages") {
                    ForEach($stages) { $stage in
                        StageDraftRow(stage: $stage)
                    }
                    .onDelete { stages.remove(atOffsets: $0) }
                    .onMove { stages.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        stages.append(StageDraft(name: "New Stage", colorHex: "#6B7280"))
                    } label: {
                        Label("Add Stage", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pipeline == nil ? "New Pipeline" : "Edit Pipeline")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || stages.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: Load / save

    private func load() {
        guard let pipeline else {
            if stages.isEmpty {
                stages = [
                    StageDraft(name: "To Do", colorHex: "#6B7280"),
                    StageDraft(name: "In Progress", colorHex: "#3B82F6"),
                    StageDraft(name: "Done", colorHex: "#1DB954", isWon: true),
                ]
            }
            return
        }
        name = pipeline.name
        colorHex = pipeline.colorHex
        iconSystemName = pipeline.iconSystemName
        stages = pipeline.orderedStages.map {
            StageDraft(id: $0.id, name: $0.name, colorHex: $0.colorHex, isWon: $0.isWon, isLost: $0.isLost)
        }
    }

    private func save() {
        let target: Pipeline
        if let pipeline {
            target = pipeline
        } else {
            let order = (allPipelines.map(\.sortOrder).max() ?? -1) + 1
            target = Pipeline(name: name, sortOrder: order)
            modelContext.insert(target)
        }
        target.name = name
        target.colorHex = colorHex
        target.iconSystemName = iconSystemName

        // Reconcile stages: update existing, insert new, delete removed.
        let draftIDs = Set(stages.compactMap(\.existingID))
        for existing in target.stages where !draftIDs.contains(existing.id) {
            modelContext.delete(existing)
        }
        for (index, draft) in stages.enumerated() {
            if let id = draft.existingID, let stage = target.stages.first(where: { $0.id == id }) {
                stage.name = draft.name
                stage.colorHex = draft.colorHex
                stage.sortOrder = index
                stage.isWon = draft.isWon
                stage.isLost = draft.isLost
            } else {
                let stage = Stage(name: draft.name, sortOrder: index, colorHex: draft.colorHex, isWon: draft.isWon, isLost: draft.isLost)
                stage.pipeline = target
                modelContext.insert(stage)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

/// A mutable draft of a stage used while editing.
struct StageDraft: Identifiable {
    let id: UUID
    /// The persisted stage id, if this draft maps to an existing stage.
    var existingID: UUID?
    var name: String
    var colorHex: String
    var isWon: Bool
    var isLost: Bool

    init(id: UUID? = nil, name: String, colorHex: String, isWon: Bool = false, isLost: Bool = false) {
        self.id = UUID()
        self.existingID = id
        self.name = name
        self.colorHex = colorHex
        self.isWon = isWon
        self.isLost = isLost
    }
}

private struct StageDraftRow: View {
    @Binding var stage: StageDraft
    private let colorChoices = ["#6B7280", "#3B82F6", "#8B5CF6", "#F59E0B", "#F97316", "#1DB954", "#E23D3D"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Circle().fill(Color(hex: stage.colorHex)).frame(width: 12, height: 12)
                TextField("Stage name", text: $stage.name)
            }
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(colorChoices, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: stage.colorHex == hex ? 2 : 0))
                        .onTapGesture { stage.colorHex = hex }
                }
                Spacer()
                Toggle("Won", isOn: Binding(
                    get: { stage.isWon },
                    set: { stage.isWon = $0; if $0 { stage.isLost = false } }
                ))
                .toggleStyle(.button)
                .font(.caption)
                Toggle("Lost", isOn: Binding(
                    get: { stage.isLost },
                    set: { stage.isLost = $0; if $0 { stage.isWon = false } }
                ))
                .toggleStyle(.button)
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
