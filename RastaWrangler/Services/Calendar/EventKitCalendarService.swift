import EventKit
import Foundation

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

    /// Returns events in [from, to] across all of the device's event calendars,
    /// sorted by start date. Requires access to have been granted first.
    func events(from: Date, to: Date) -> [CalendarEvent] {
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        return store.events(matching: predicate)
            .map(Self.map)
            .sorted { $0.start < $1.start }
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
            isAllDay: ekEvent.isAllDay
        )
    }
}
