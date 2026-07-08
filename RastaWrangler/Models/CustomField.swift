import Foundation
import SwiftData

/// Defines a user-created custom field (e.g. "Job URL", "Salary range",
/// "Referred by") that can be attached to deals or contacts. This is the
/// mechanism that lets the CRM grow with the user's needs.
@Model
final class CustomFieldDefinition {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var entityRaw: String
    /// Options for single-select fields.
    var options: [String]
    var sortOrder: Int
    /// When set, the field only applies to deals within a specific pipeline.
    /// `nil` means it applies globally to all entities of its type.
    var pipeline: Pipeline?

    init(
        id: UUID = UUID(),
        name: String,
        type: CustomFieldType = .text,
        entity: CustomFieldEntity = .deal,
        options: [String] = [],
        sortOrder: Int = 0,
        pipeline: Pipeline? = nil
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.entityRaw = entity.rawValue
        self.options = options
        self.sortOrder = sortOrder
        self.pipeline = pipeline
    }

    var type: CustomFieldType {
        get { CustomFieldType(rawValue: typeRaw) ?? .text }
        set { typeRaw = newValue.rawValue }
    }

    var entity: CustomFieldEntity {
        get { CustomFieldEntity(rawValue: entityRaw) ?? .deal }
        set { entityRaw = newValue.rawValue }
    }
}

/// The stored value of a custom field for a particular deal or contact. Values
/// are kept as strings and interpreted according to the definition's type.
@Model
final class CustomFieldValue {
    @Attribute(.unique) var id: UUID
    /// Links back to the `CustomFieldDefinition` this value belongs to.
    var definitionID: UUID
    var value: String

    var deal: Deal?
    var contact: Contact?

    init(
        id: UUID = UUID(),
        definitionID: UUID,
        value: String = ""
    ) {
        self.id = id
        self.definitionID = definitionID
        self.value = value
    }

    // MARK: Typed accessors

    var boolValue: Bool {
        get { value == "true" }
        set { value = newValue ? "true" : "false" }
    }

    var doubleValue: Double? {
        get { Double(value) }
        set { value = newValue.map { String($0) } ?? "" }
    }

    var dateValue: Date? {
        get {
            guard let interval = TimeInterval(value) else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set { value = newValue.map { String($0.timeIntervalSince1970) } ?? "" }
    }
}
