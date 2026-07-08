import Foundation
import SwiftData

/// A company / organization that contacts and deals can be associated with.
@Model
final class Organization {
    @Attribute(.unique) var id: UUID
    var name: String
    var domain: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Contact.organization)
    var contacts: [Contact]

    init(
        id: UUID = UUID(),
        name: String,
        domain: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.notes = notes
        self.createdAt = createdAt
        self.contacts = []
    }
}
