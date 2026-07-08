import Foundation

/// A meeting parsed out of Granola, before it becomes a persisted `MeetingNote`.
struct GranolaMeeting: Identifiable, Hashable {
    let id: String
    var title: String
    var summaryMarkdown: String
    var transcript: String
    var date: Date
    var attendees: [String]
}

/// Imports meetings from Granola's **official public API**
/// (`https://public-api.granola.ai/v1`).
///
/// The user creates an API key in Granola (Settings → Connectors → API keys) and
/// pastes it into RastaWrangler's Settings; we store it in the Keychain and send
/// it as a bearer token. Because this is a plain HTTPS API, it needs no access to
/// Granola's local files, works on every platform, and survives Granola's on-disk
/// format changes. If it's unavailable (the API is a Business/Enterprise feature),
/// **manual import** (paste markdown) is always available as a fallback.
///
/// The JSON field names below are matched defensively against a few likely
/// aliases, since the exact response shape isn't fully documented publicly.
struct GranolaService {

    private static let baseURL = "https://public-api.granola.ai/v1"

    // MARK: API import

    /// Fetches recent meetings from Granola's public API.
    ///
    /// - Parameter apiKey: The user's Granola API key (starts with `grn_`).
    /// - Returns: Parsed meetings, newest first.
    func importFromAPI(apiKey: String) async throws -> [GranolaMeeting] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GranolaError.missingAPIKey }
        let data = try await get(path: "notes", apiKey: key)
        return try parseNotes(data: data)
    }

    /// Performs an authenticated GET against the Granola API and returns the body,
    /// mapping auth/error statuses to typed errors.
    private func get(path: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/\(path)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw GranolaError.notAuthorized
            }
            guard (200..<300).contains(http.statusCode) else {
                throw GranolaError.apiError(status: http.statusCode)
            }
        }
        return data
    }

    // MARK: Parsing

    /// Maps a Granola API `notes` response into meetings. Accepts either a bare
    /// array or an object wrapping the array under a common key.
    func parseNotes(data: Data) throws -> [GranolaMeeting] {
        let root = try JSONSerialization.jsonObject(with: data)

        let items: [[String: Any]]
        if let array = root as? [[String: Any]] {
            items = array
        } else if let dict = root as? [String: Any] {
            let node = dict["notes"] ?? dict["data"] ?? dict["items"] ?? dict["documents"]
            items = (node as? [[String: Any]]) ?? []
        } else {
            items = []
        }

        // List responses may omit the full summary, so don't require content here;
        // a note with just a title is still a valid import candidate.
        let meetings = items.compactMap { Self.meeting(from: $0, requireContent: false) }
        return meetings.sorted { $0.date > $1.date }
    }

    /// Builds a `GranolaMeeting` from a note/document dictionary, matching a few
    /// likely field-name aliases.
    ///
    /// - Parameter requireContent: When true, a note with no summary/notes body is
    ///   rejected (used when scanning arbitrary JSON). When false, an empty summary
    ///   is allowed (used for API list responses that carry metadata only).
    private static func meeting(from dict: [String: Any], requireContent: Bool) -> GranolaMeeting? {
        guard let title = (dict["title"] ?? dict["name"] ?? dict["subject"]) as? String,
              !title.isEmpty else { return nil }

        let contentNode = dict["notes_markdown"] ?? dict["notes_plain"] ?? dict["notes"]
            ?? dict["content"] ?? dict["summary"] ?? dict["overview"]
        let summary: String
        if let markdown = contentNode as? String {
            summary = markdown
        } else if let node = contentNode {
            summary = extractText(from: node)
        } else {
            summary = ""
        }
        if requireContent, summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        let id = (dict["id"] ?? dict["document_id"] ?? dict["note_id"]) as? String ?? UUID().uuidString
        let transcriptNode = dict["transcript"]
        let transcript = (transcriptNode as? String) ?? (transcriptNode.map { extractText(from: $0) } ?? "")
        let date = parseDate(dict["created_at"] ?? dict["updated_at"] ?? dict["date"] ?? dict["created"]) ?? Date()
        let attendeeNode = dict["attendees"] ?? dict["people"]
        let attendees = (attendeeNode as? [Any])?.compactMap {
            ($0 as? [String: Any])?["name"] as? String
                ?? ($0 as? [String: Any])?["email"] as? String
                ?? $0 as? String
        } ?? []

        return GranolaMeeting(
            id: id,
            title: title,
            summaryMarkdown: summary,
            transcript: transcript,
            date: date,
            attendees: attendees
        )
    }

    /// Flattens a ProseMirror-style rich text node into plain text.
    private static func extractText(from node: Any) -> String {
        if let string = node as? String { return string }
        if let dict = node as? [String: Any] {
            var pieces: [String] = []
            if let text = dict["text"] as? String { pieces.append(text) }
            if let content = dict["content"] { pieces.append(extractText(from: content)) }
            let joined = pieces.joined()
            // Add paragraph breaks between block nodes.
            if (dict["type"] as? String) == "paragraph" { return joined + "\n\n" }
            return joined
        }
        if let array = node as? [Any] {
            return array.map { extractText(from: $0) }.joined()
        }
        return ""
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        if let interval = value as? Double {
            // Granola timestamps may be seconds or milliseconds.
            return Date(timeIntervalSince1970: interval > 1_000_000_000_000 ? interval / 1000 : interval)
        }
        return nil
    }

    enum GranolaError: LocalizedError {
        case missingAPIKey, notAuthorized
        case apiError(status: Int)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your Granola API key in Settings first (Granola → Settings → Connectors → API keys)."
            case .notAuthorized:
                return "Granola rejected the API key. Check that it's correct and still active in Granola's settings."
            case .apiError(let status):
                return "Granola's API returned an error (\(status)). Try again shortly, or add meetings manually."
            }
        }
    }
}
