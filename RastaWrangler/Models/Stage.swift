import Foundation
import SwiftData

/// A single column within a pipeline. Deals belong to exactly one stage.
@Model
final class Stage {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var colorHex: String
    /// Marks a terminal "won" stage (deals here count as closed-won).
    var isWon: Bool
    /// Marks a terminal "lost" stage.
    var isLost: Bool

    var pipeline: Pipeline?

    @Relationship(deleteRule: .nullify, inverse: \Deal.stage)
    var deals: [Deal]

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        colorHex: String = "#6B7280",
        isWon: Bool = false,
        isLost: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.isWon = isWon
        self.isLost = isLost
        self.deals = []
    }

    /// Deals in this stage sorted by their manual order.
    var orderedDeals: [Deal] {
        deals.sorted { $0.sortOrder < $1.sortOrder }
    }
}
