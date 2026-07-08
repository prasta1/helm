# Deliverable model — design

**Date:** 2026-07-08
**Status:** Approved design, pre-implementation

## Goal

Add granularity to the pipeline area by tracking a second top-level object
alongside `Deal`: a **Deliverable** — a standalone project-management to-do /
task-tracking item. Deals and Deliverables share three fields (`title`,
`dueDate`, `notes`) but otherwise diverge. Deliverables live in their own
to-do-style list view and can optionally be linked to zero or more Deals.

## Key decisions

1. **Two independent `@Model` classes, not inheritance.** SwiftData has no clean
   queryable `@Model` subclassing, so `Deal` and `Deliverable` each own their own
   copy of the shared trio (`title`, `dueDate`, `notes`). Duplicating three
   fields is simpler and clearer than any base-class machinery — composition over
   inheritance.

2. **A `Deliverable` is not an `Activity`.** `Activity(kind: .task)` already
   exists but is a *timeline child* — cascade-deleted with its parent Deal, always
   attached to one deal/contact. A Deliverable is the opposite: top-level,
   stands alone, outlives any Deal it links to, has its own list view. These stay
   two distinct concepts; `Activity` is unchanged by this work.

3. **Standalone but linkable.** Deliverables are independent records with an
   optional **many-to-many** relationship to `Deal` (a Deliverable can reference
   several deals; a Deal can have several deliverables). Deleting a Deal must
   **nullify** the link, never delete the Deliverable, and vice versa.

4. **Optional shared protocol for a future unified view.** A lightweight
   `DueItem { var title; var dueDate }` protocol lets both models conform so a
   later "what's due" view can sort/display across both without coupling the
   database tables. The protocol is read-only behavior, not persisted. Included
   now because it is nearly free; no cross-model view is built in this pass.

## Data model

### New enums (in `Models/Enums.swift`, following the existing Raw+computed pattern)

```swift
enum DeliverableStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted, inProgress, blocked, done
    var id: String { rawValue }
    var title: String     // "Not Started" / "In Progress" / "Blocked" / "Done"
    var tint: Color       // e.g. gray / blue / orange / green
    var systemImage: String
}

enum DeliverablePriority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String     // "Low" / "Medium" / "High"
    var tint: Color       // e.g. gray / blue / red
    var systemImage: String
}
```

### New model `Models/Deliverable.swift`

```swift
@Model
final class Deliverable {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String            // shared "notes" field
    var dueDate: Date?
    var statusRaw: String        // DeliverableStatus
    var priorityRaw: String      // DeliverablePriority
    var sortOrder: Int           // manual ordering in the to-do list
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?       // set when status becomes .done

    // Optional link to deals. Default delete rule (.nullify) is correct:
    // deleting a Deal leaves its Deliverables intact.
    @Relationship var deals: [Deal]

    init(...) { ... }            // mirrors Deal's init defaults

    var status: DeliverableStatus { get/set via statusRaw }
    var priority: DeliverablePriority { get/set via priorityRaw }
    func touch() { updatedAt = .now }
}
```

Field notes:
- `statusRaw` / `priorityRaw` use the same String-backed pattern as `Deal.statusRaw`
  so `#Predicate` filtering stays simple.
- `completedAt` is set when `status` transitions to `.done` (and cleared if it
  moves back). This is UI/service logic, not enforced by the model itself.
- Matches the codebase convention of `@Attribute(.unique) var id` even though
  CloudKit is currently `.none`.

### Change to `Deal` (`Models/Deal.swift`)

Add the inverse relationship only:

```swift
@Relationship(inverse: \Deliverable.deals)
var deliverables: [Deliverable]
```

Initialize `deliverables = []` in `Deal.init`. No other Deal changes.

### Shared protocol (in `Models/Enums.swift` or a small `Models/DueItem.swift`)

```swift
protocol DueItem {
    var title: String { get }
    var dueDate: Date? { get }
}
extension Deal: DueItem {}
extension Deliverable: DueItem {}
```

### Schema registration (`Persistence/PersistenceController.swift`)

Add `Deliverable.self` to the `schema` array.

## Out of scope for this pass

- The Deliverables **list/to-do view** and any navigation/tab wiring (UI is a
  follow-up; this pass is the model layer + schema).
- Any unified cross-object "due soon" view (the `DueItem` protocol enables it
  later but no view is built now).
- Seed/sample data for Deliverables (optional; can be added if useful for
  previews).
- Custom fields for Deliverables (`CustomFieldEntity` currently covers
  `.deal` / `.contact` only; not extending it now).

## Testing

Follow the project convention (add tests only where the project expects them).
At minimum, verify the container builds with the new model registered — the
existing in-memory container path (`makeInMemoryContainer`) exercises the schema,
so a preview/build check confirms the model and relationships are valid.
