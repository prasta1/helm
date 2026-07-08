import EventKit
import Foundation
import SwiftUI

/// A device calendar (an `EKCalendar` for events), in a lightweight app-facing form.
struct DeviceCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    /// The account the calendar lives in, e.g. "iCloud" or "Google".
    let sourceName: String
    /// Whether new events may be saved into this calendar.
    let allowsModifications: Bool
}

/// Reads upcoming events from the device's built-in calendar database.
///
/// The user must have accounts configured in System Settings → Internet Accounts
/// for their events to appear here. This service wraps EventKit, which reads the
/// same calendar database that the macOS/iOS Calendar app uses — no OAuth required.
///
/// EventKit has no read-only mode for events; `requestFullAccessToEvents()` is the
/// minimum required to fetch event data. Once granted, the same permission is reused
/// on subsequent calls without showing another prompt.
@MainActor
final class EventKitCalendarService {
    private let store = EKEventStore()

    /// The current authorization status — useful for checking before calling `requestAccess()`.
    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Requests full-access authorization. Returns `true` if access was granted.
    /// If the user already granted access, returns `true` immediately without prompting.
    /// If the user previously denied access, returns `false` immediately without prompting.
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// Notification posted by EventKit whenever events/reminders change anywhere
    /// on the system — observe this to refresh without polling.
    static var changeNotification: Notification.Name { .EKEventStoreChanged }

    /// All event calendars across the device's accounts.
    func calendars() -> [DeviceCalendar] {
        store.calendars(for: .event).map { calendar in
            DeviceCalendar(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                colorHex: RemindersService.hexColor(of: calendar),
                sourceName: calendar.source?.title ?? "",
                allowsModifications: calendar.allowsContentModifications
            )
        }
    }

    /// Returns events in [from, to], sorted by start date. Pass `calendarIDs`
    /// to restrict to a subset of calendars; nil means all calendars.
    /// Requires access to have been granted first.
    func events(from: Date, to: Date, calendarIDs: Set<String>? = nil) -> [CalendarEvent] {
        var calendars = store.calendars(for: .event)
        if let calendarIDs {
            calendars = calendars.filter { calendarIDs.contains($0.calendarIdentifier) }
            if calendars.isEmpty { return [] }
        }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        return store.events(matching: predicate)
            .map(Self.map)
            .sorted { $0.start < $1.start }
    }

    /// Creates a new event in the given calendar (or the default calendar when nil).
    func createEvent(title: String, start: Date, end: Date, calendarID: String?) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        if let calendarID, let calendar = store.calendar(withIdentifier: calendarID) {
            event.calendar = calendar
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        try store.save(event, span: .thisEvent, commit: true)
    }

    private static func map(_ ekEvent: EKEvent) -> CalendarEvent {
        let attendees = (ekEvent.attendees ?? []).compactMap { participant -> String? in
            // EKParticipant.url is a mailto: URL; strip the scheme to get the address.
            let raw = participant.url.absoluteString
            if raw.hasPrefix("mailto:") {
                return String(raw.dropFirst("mailto:".count))
            }
            return participant.name
        }
        return CalendarEvent(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "(No title)",
            start: ekEvent.startDate,
            end: ekEvent.endDate,
            location: ekEvent.location ?? "",
            attendees: attendees,
            organizerEmail: ekEvent.organizer?.name ?? "",
            htmlLink: "",
            isAllDay: ekEvent.isAllDay,
            calendarID: ekEvent.calendar?.calendarIdentifier ?? "",
            colorHex: ekEvent.calendar.map(RemindersService.hexColor) ?? ""
        )
    }
}
