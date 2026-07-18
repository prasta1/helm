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

/// Imports meeting summaries from the Granola desktop app.
///
/// Granola keeps a local cache on macOS at
/// `~/Library/Application Support/Granola/cache-v3.json`. That file is an
/// undocumented, evolving format, so this importer is deliberately defensive: it
/// walks the JSON tree looking for document-shaped nodes and extracts their
/// text. If Granola changes its schema, use **manual import** (paste markdown or
/// pick an exported file), which is always reliable.
///
/// On macOS the app is sandboxed, so the user grants read access once via an
/// open panel; the resulting security-scoped bookmark is persisted in
/// `AppSettings.granolaBookmark`.
struct GranolaService {

    /// The default location of Granola's cache on macOS.
    static var defaultCacheURL: URL? {
        #if os(macOS)
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Granola/cache-v3.json")
        #else
        nil
        #endif
    }

    // MARK: Cache import (macOS)

    /// Reads and parses meetings from a Granola cache file the user granted
    /// access to via a security-scoped bookmark.
    func importFromCache(bookmark: Data) throws -> [GranolaMeeting] {
        #if os(macOS)
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw GranolaError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // The bookmark may point at the directory or the file itself.
        let fileURL = url.hasDirectoryPath ? url.appendingPathComponent("cache-v3.json") : url
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
        #else
        throw GranolaError.unsupportedPlatform
        #endif
    }

    // MARK: Parsing

    /// Parses meetings from raw Granola cache data.
    func parse(data: Data) throws -> [GranolaMeeting] {
        var root = try JSONSerialization.jsonObject(with: data)

        // Granola double-encodes: a top-level object with a "cache" string that
        // is itself a JSON document. Unwrap it if present.
        if let dict = root as? [String: Any], let cacheString = dict["cache"] as? String,
           let inner = cacheString.data(using: .utf8),
           let innerObject = try? JSONSerialization.jsonObject(with: inner) {
            root = innerObject
        }

        var meetings: [GranolaMeeting] = []
        collectDocuments(from: root, into: &meetings)

        // De-duplicate by id, keeping the richest version.
        var byID: [String: GranolaMeeting] = [:]
        for meeting in meetings {
            if let existing = byID[meeting.id],
               existing.summaryMarkdown.count >= meeting.summaryMarkdown.count {
                continue
            }
            byID[meeting.id] = meeting
        }
        return byID.values.sorted { $0.date > $1.date }
    }

    /// Recursively walks the JSON looking for document-shaped nodes: objects
    /// that carry a title plus some notes/content.
    private func collectDocuments(from node: Any, into meetings: inout [GranolaMeeting]) {
        if let dict = node as? [String: Any] {
            if let meeting = Self.meeting(from: dict) {
                meetings.append(meeting)
            }
            for value in dict.values {
                collectDocuments(from: value, into: &meetings)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectDocuments(from: value, into: &meetings)
            }
        }
    }

    private static func meeting(from dict: [String: Any]) -> GranolaMeeting? {
        // Heuristic: a Granola document has a title and a content/notes body.
        guard let title = (dict["title"] ?? dict["name"]) as? String, !title.isEmpty else { return nil }

        let contentNode = dict["notes"] ?? dict["notes_markdown"] ?? dict["content"] ?? dict["summary"]
        let summary: String
        if let markdown = contentNode as? String {
            summary = markdown
        } else if let node = contentNode {
            summary = extractText(from: node)
        } else {
            return nil
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let id = (dict["id"] ?? dict["document_id"]) as? String ?? UUID().uuidString
        let transcript = (dict["transcript"] as? String) ?? extractText(from: dict["transcript"] ?? "")
        let date = parseDate(dict["created_at"] ?? dict["updated_at"] ?? dict["date"]) ?? Date()
        let attendees = (dict["attendees"] as? [Any])?.compactMap { ($0 as? [String: Any])?["name"] as? String ?? $0 as? String } ?? []

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
        case accessDenied, unsupportedPlatform

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Couldn't access the Granola cache. Re-select it in Settings."
            case .unsupportedPlatform: return "Automatic Granola import is only available on macOS. Use manual import instead."
            }
        }
    }
}
