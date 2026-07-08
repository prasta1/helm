import Foundation
import SwiftData

/// A timeline entry attached to a deal and/or contact: a note, a task, a logged
/// call/email, or a meeting. Activities can originate from the user, from a
/// Granola meeting import, from Google Calendar, or from an AI action.
@Model
final class Activity {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var body: String
    var date: Date
    var dueDate: Date?
    var isCompleted: Bool
    var sourceRaw: String
    /// Identifier from the originating system (e.g. Google event id) for dedupe.
    var externalID: String?

    var deal: Deal?
    var contact: Contact?

    init(
        id: UUID = UUID(),
        kind: ActivityKind = .note,
        title: String = "",
        body: String = "",
        date: Date = .now,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        source: ActivitySource = .manual,
        externalID: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.date = date
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.sourceRaw = source.rawValue
        self.externalID = externalID
    }

    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var source: ActivitySource {
        get { ActivitySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
