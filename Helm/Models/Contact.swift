import Foundation
import SwiftData

/// A person tracked in the CRM — a hiring manager, a recruiter, a prospect, a
/// friend. Contacts can be linked to many deals and meetings.
@Model
final class Contact {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String
    var phone: String
    var title: String
    var company: String
    var notes: String
    var avatarColorHex: String
    var createdAt: Date

    var organization: Organization?

    /// Inverse of `Deal.contacts`.
    var deals: [Deal]

    @Relationship(deleteRule: .cascade, inverse: \Activity.contact)
    var activities: [Activity]

    @Relationship(deleteRule: .cascade, inverse: \CustomFieldValue.contact)
    var customValues: [CustomFieldValue]

    @Relationship(inverse: \MeetingNote.contacts)
    var meetings: [MeetingNote]

    init(
        id: UUID = UUID(),
        name: String,
        email: String = "",
        phone: String = "",
        title: String = "",
        company: String = "",
        notes: String = "",
        avatarColorHex: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.title = title
        self.company = company
        self.notes = notes
        self.avatarColorHex = avatarColorHex ?? Contact.paletteColor(for: name)
        self.createdAt = createdAt
        self.deals = []
        self.activities = []
        self.customValues = []
        self.meetings = []
    }

    /// Initials for avatar display.
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    /// A deterministic accent color derived from the contact's name so avatars
    /// stay stable across launches.
    static func paletteColor(for name: String) -> String {
        let palette = ["#EF4444", "#F59E0B", "#10B981", "#3B82F6", "#8B5CF6", "#EC4899", "#14B8A6", "#F97316"]
        let hash = abs(name.hashValue)
        return palette[hash % palette.count]
    }
}
