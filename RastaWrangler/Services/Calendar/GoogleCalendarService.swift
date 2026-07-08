import Foundation

/// A calendar event in a lightweight app-facing form, produced by both the
/// Google and EventKit services.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String
    let attendees: [String]
    let organizerEmail: String
    let htmlLink: String
    let isAllDay: Bool
    /// Identifier of the calendar this event belongs to (EventKit only; empty for Google).
    var calendarID: String = ""
    /// Display color of the owning calendar as `#RRGGBB` (EventKit only; empty for Google).
    var colorHex: String = ""

    var timeRangeText: String {
        if isAllDay { return "All day" }
        let f = Date.FormatStyle().hour().minute()
        return "\(start.formatted(f)) – \(end.formatted(f))"
    }
}

/// Reads events from the user's Google calendars using the Calendar REST API.
@MainActor
final class GoogleCalendarService {
    private let auth: GoogleAuth

    init(auth: GoogleAuth) {
        self.auth = auth
    }

    /// Lists the user's calendars (id + summary).
    func listCalendars() async throws -> [(id: String, name: String)] {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        let json = try await get(url)
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return (id, item["summary"] as? String ?? id)
        }
    }

    /// Fetches events in a date range from a calendar (default: primary).
    func events(
        calendarID: String = "primary",
        from startDate: Date,
        to endDate: Date,
        maxResults: Int = 50
    ) async throws -> [CalendarEvent] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events")!
        components.queryItems = [
            .init(name: "timeMin", value: ISO8601DateFormatter().string(from: startDate)),
            .init(name: "timeMax", value: ISO8601DateFormatter().string(from: endDate)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: String(maxResults)),
        ]
        let json = try await get(components.url!)
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap(Self.parseEvent)
    }

    // MARK: Networking

    private func get(_ url: URL) async throws -> [String: Any] {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding("Unexpected calendar response.")
        }
        return json
    }

    // MARK: Parsing

    private static func parseEvent(_ item: [String: Any]) -> CalendarEvent? {
        guard let id = item["id"] as? String else { return nil }
        let summary = item["summary"] as? String ?? "(No title)"

        let startInfo = item["start"] as? [String: Any] ?? [:]
        let endInfo = item["end"] as? [String: Any] ?? [:]
        let isAllDay = startInfo["date"] != nil

        let start = date(from: startInfo) ?? Date()
        let end = date(from: endInfo) ?? start

        let attendees = (item["attendees"] as? [[String: Any]] ?? [])
            .compactMap { $0["email"] as? String }
        let organizer = (item["organizer"] as? [String: Any])?["email"] as? String ?? ""

        return CalendarEvent(
            id: id,
            title: summary,
            start: start,
            end: end,
            location: item["location"] as? String ?? "",
            attendees: attendees,
            organizerEmail: organizer,
            htmlLink: item["htmlLink"] as? String ?? "",
            isAllDay: isAllDay
        )
    }

    private static func date(from info: [String: Any]) -> Date? {
        if let dateTime = info["dateTime"] as? String {
            return ISO8601DateFormatter().date(from: dateTime)
        }
        if let dateString = info["date"] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: dateString)
        }
        return nil
    }
}
