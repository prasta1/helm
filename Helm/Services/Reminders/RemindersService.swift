import EventKit
import Foundation
import SwiftUI

/// A reminder list (an `EKCalendar` for reminders), in a lightweight app-facing form.
struct ReminderList: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    /// The account the list lives in, e.g. "iCloud" or "On My Mac".
    let sourceName: String
    /// Whether new reminders may be saved into this list.
    let allowsModifications: Bool
}

/// A single reminder, in a lightweight app-facing form. Views never see EKReminder.
struct ReminderItem: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: String
    /// Resolved due date, if the reminder has one.
    let dueDate: Date?
    /// Whether the due date includes a time of day (vs. an all-day date).
    let hasDueTime: Bool
    let isCompleted: Bool
    let completionDate: Date?
    let listID: String
    let listName: String
    let listColorHex: String
}

/// Reads and writes Apple Reminders through EventKit.
///
/// Same model as `EventKitCalendarService`: the user's lists come from whatever
/// accounts are configured in System Settings → Internet Accounts. Requires
/// `NSRemindersFullAccessUsageDescription` in Info.plist; on sandboxed macOS the
/// calendars entitlement covers the shared EventKit store.
///
/// Writes are deliberately limited to "safe" operations: completing/un-completing
/// a reminder and creating new ones. Helm never edits or deletes existing items.
@MainActor
final class RemindersService {
    private let store = EKEventStore()

    /// Notification posted by EventKit whenever reminders/events change anywhere
    /// on the system — observe this to refresh without polling.
    static var changeNotification: Notification.Name { .EKEventStoreChanged }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Convenience flags so views don't need to import EventKit.
    var hasFullAccess: Bool { authorizationStatus == .fullAccess }
    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }

    /// Requests full access to reminders. Returns `true` if granted. Re-invoking
    /// after a grant or denial returns immediately without prompting again.
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    /// All reminder lists across the device's accounts.
    func lists() -> [ReminderList] {
        store.calendars(for: .reminder).map(Self.mapList)
    }

    /// All incomplete reminders across every list, soonest due date first
    /// (reminders without a due date sort last).
    func incompleteReminders() async -> [ReminderItem] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let reminders = await fetch(matching: predicate)
        return reminders
            .map(Self.mapReminder)
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Reminders completed on or after `since`, most recent first. Used for the Logbook.
    func completedReminders(since: Date) async -> [ReminderItem] {
        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: since, ending: nil, calendars: nil
        )
        let reminders = await fetch(matching: predicate)
        return reminders
            .map(Self.mapReminder)
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    }

    /// Marks a reminder complete or incomplete and saves it back to the store.
    func setCompleted(_ completed: Bool, reminderID: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw RemindersServiceError.reminderNotFound
        }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    /// Creates a new reminder in the given list (or the default list when nil).
    func createReminder(title: String, dueDate: Date?, listID: String?) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let listID, let list = store.calendar(withIdentifier: listID) {
            reminder.calendar = list
        } else if let defaultList = store.defaultCalendarForNewReminders() {
            reminder.calendar = defaultList
        } else {
            // No writable default list (e.g. all accounts read-only) — fail
            // with a message the user can act on instead of a raw EventKit error.
            throw NSError(domain: "Helm.Reminders", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No default Reminders list is available. Pick a list, or set a default list in the Reminders app."
            ])
        }
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        }
        try store.save(reminder, commit: true)
    }

    // MARK: - Private

    /// Wraps EventKit's callback-based fetch in async/await.
    private func fetch(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private static func mapList(_ calendar: EKCalendar) -> ReminderList {
        ReminderList(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: hexColor(of: calendar),
            sourceName: calendar.source?.title ?? "",
            allowsModifications: calendar.allowsContentModifications
        )
    }

    private static func mapReminder(_ reminder: EKReminder) -> ReminderItem {
        let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "(No title)",
            notes: reminder.notes ?? "",
            dueDate: due,
            hasDueTime: reminder.dueDateComponents?.hour != nil,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listName: reminder.calendar?.title ?? "",
            listColorHex: reminder.calendar.map(hexColor) ?? "#8E99AD"
        )
    }

    static func hexColor(of calendar: EKCalendar) -> String {
        guard let cgColor = calendar.cgColor else { return "#8E99AD" }
        return Color(cgColor: cgColor).hexString
    }
}

enum RemindersServiceError: LocalizedError {
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .reminderNotFound:
            return "That reminder could not be found — it may have been deleted in another app."
        }
    }
}
