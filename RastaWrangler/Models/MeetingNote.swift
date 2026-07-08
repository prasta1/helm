import Foundation
import SwiftData

/// A meeting summary, typically imported from the Granola desktop app but also
/// creatable manually. Can be linked to contacts and a deal, and enriched by
/// the AI assistant.
@Model
final class MeetingNote {
    @Attribute(.unique) var id: UUID
    var title: String
    var summaryMarkdown: String
    var transcript: String
    var date: Date
    var sourceRaw: String
    /// Granola's own identifier (or calendar event id) used to avoid importing
    /// the same meeting twice.
    var externalID: String?
    var attendeesText: String
    var calendarEventID: String?
    var createdAt: Date

    /// Inverse is declared on `Contact.meetings`.
    var contacts: [Contact]

    var deal: Deal?

    init(
        id: UUID = UUID(),
        title: String,
        summaryMarkdown: String = "",
        transcript: String = "",
        date: Date = .now,
        source: ActivitySource = .granola,
        externalID: String? = nil,
        attendeesText: String = "",
        calendarEventID: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summaryMarkdown = summaryMarkdown
        self.transcript = transcript
        self.date = date
        self.sourceRaw = source.rawValue
        self.externalID = externalID
        self.attendeesText = attendeesText
        self.calendarEventID = calendarEventID
        self.createdAt = createdAt
        self.contacts = []
    }

    var source: ActivitySource {
        get { ActivitySource(rawValue: sourceRaw) ?? .granola }
        set { sourceRaw = newValue.rawValue }
    }
}
