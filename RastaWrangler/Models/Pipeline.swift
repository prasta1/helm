import Foundation
import SwiftData

/// A pipeline is a board (e.g. "Job Search", "Peregrine Prospects") made up of
/// ordered stages that deals move through. Pipelines are fully user editable so
/// the CRM can evolve over time.
@Model
final class Pipeline {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var iconSystemName: String
    var colorHex: String
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Stage.pipeline)
    var stages: [Stage]

    @Relationship(deleteRule: .cascade, inverse: \Deal.pipeline)
    var deals: [Deal]

    init(
        id: UUID = UUID(),
        name: String,
        kind: PipelineKind = .custom,
        iconSystemName: String? = nil,
        colorHex: String = "#3B82F6",
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.iconSystemName = iconSystemName ?? kind.systemImage
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.stages = []
        self.deals = []
    }

    var kind: PipelineKind {
        get { PipelineKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    /// Stages sorted by their explicit order.
    var orderedStages: [Stage] {
        stages.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total value of all open deals in this pipeline.
    var openValue: Double {
        deals
            .filter { $0.status == .open }
            .reduce(0) { $0 + ($1.amount ?? 0) }
    }
}
