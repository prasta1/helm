import Foundation
import SwiftData

/// Owns the app's `ModelContainer` and the schema (the full list of `@Model`
/// types). Centralizing this makes it easy to switch to CloudKit sync later or
/// spin up an in-memory container for previews and tests.
enum PersistenceController {

    /// All persisted model types. Add new `@Model` types here.
    static let schema = Schema([
        Pipeline.self,
        Stage.self,
        Deal.self,
        Contact.self,
        Organization.self,
        Activity.self,
        CustomFieldDefinition.self,
        CustomFieldValue.self,
        MeetingNote.self,
    ])

    /// The shared, on-disk container used by the running app.
    ///
    /// To enable iCloud sync across your Mac and iOS devices, add an iCloud
    /// container to the target's capabilities and change `cloudKitDatabase` to
    /// `.automatic` (or `.private("iCloud.com.rastawrangler.app")`). It's kept
    /// local by default so the project builds and runs with no provisioning.
    static func makeSharedContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            SeedData.seedIfNeeded(container.mainContext)
            return container
        } catch {
            // A schema migration failure shouldn't hard-crash a personal app in
            // the field; fall back to an in-memory store so the user can still
            // launch and export/recover.
            assertionFailure("Failed to create persistent container: \(error). Falling back to in-memory.")
            return makeInMemoryContainer()
        }
    }

    /// An ephemeral container for SwiftUI previews and unit tests.
    static func makeInMemoryContainer(seeded: Bool = true) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // In-memory containers should never fail; a crash here is a programmer
        // error worth surfacing loudly.
        let container = try! ModelContainer(for: schema, configurations: configuration)
        if seeded {
            SeedData.seedIfNeeded(container.mainContext, includeSampleContent: true)
        }
        return container
    }
}
