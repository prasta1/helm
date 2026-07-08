import Foundation
import SwiftData

/// A deal / opportunity — the card that moves across a pipeline board. In a job
/// search pipeline this represents a role you're pursuing; in a prospects
/// pipeline it's a potential client engagement.
@Model
final class Deal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    /// Optional monetary value (salary, contract size, etc.).
    var amount: Double?
    var currencyCode: String
    var statusRaw: String
    /// Manual ordering within a stage column.
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var closeDate: Date?

    var pipeline: Pipeline?
    var stage: Stage?

    @Relationship(inverse: \Contact.deals)
    var contacts: [Contact]

    @Relationship(deleteRule: .cascade, inverse: \Activity.deal)
    var activities: [Activity]

    @Relationship(deleteRule: .cascade, inverse: \CustomFieldValue.deal)
    var customValues: [CustomFieldValue]

    @Relationship(deleteRule: .nullify, inverse: \MeetingNote.deal)
    var meetings: [MeetingNote]

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        amount: Double? = nil,
        currencyCode: String = "USD",
        status: DealStatus = .open,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        closeDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.amount = amount
        self.currencyCode = currencyCode
        self.statusRaw = status.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.closeDate = closeDate
        self.contacts = []
        self.activities = []
        self.customValues = []
        self.meetings = []
    }

    var status: DealStatus {
        get { DealStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var formattedAmount: String? {
        guard let amount else { return nil }
        return amount.formatted(.currency(code: currencyCode))
    }

    /// Open tasks/activities that still need attention.
    var openTasks: [Activity] {
        activities.filter { $0.kind == .task && !$0.isCompleted }
    }

    func touch() {
        updatedAt = .now
    }
}
