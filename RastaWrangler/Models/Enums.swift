import Foundation
import SwiftUI

/// Shared enumerations used across the RastaWrangler data model.
///
/// Enums are persisted in SwiftData as their `String` raw value via a
/// dedicated `…Raw` stored property plus a computed accessor. This keeps
/// `#Predicate` queries simple (they can filter on the raw string) while the
/// rest of the app works with strongly typed values.

enum PipelineKind: String, Codable, CaseIterable, Identifiable {
    case jobSearch
    case prospects
    case sales
    case personal
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobSearch: return "Job Search"
        case .prospects: return "Prospects"
        case .sales: return "Sales"
        case .personal: return "Personal"
        case .custom: return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .jobSearch: return "briefcase"
        case .prospects: return "person.2"
        case .sales: return "chart.line.uptrend.xyaxis"
        case .personal: return "heart"
        case .custom: return "square.grid.2x2"
        }
    }
}

enum DealStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case won
    case lost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .won: return "Won"
        case .lost: return "Lost"
        }
    }

    var tint: Color {
        switch self {
        case .open: return .blue
        case .won: return .green
        case .lost: return .red
        }
    }
}

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case note
    case task
    case call
    case email
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: return "Note"
        case .task: return "Task"
        case .call: return "Call"
        case .email: return "Email"
        case .meeting: return "Meeting"
        }
    }

    var systemImage: String {
        switch self {
        case .note: return "note.text"
        case .task: return "checkmark.circle"
        case .call: return "phone"
        case .email: return "envelope"
        case .meeting: return "person.2.wave.2"
        }
    }
}

enum ActivitySource: String, Codable {
    case manual
    case granola
    case googleCalendar
    case deviceCalendar
    case ai
}

enum CustomFieldType: String, Codable, CaseIterable, Identifiable {
    case text
    case multilineText
    case number
    case currency
    case date
    case boolean
    case url
    case singleSelect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .multilineText: return "Long Text"
        case .number: return "Number"
        case .currency: return "Currency"
        case .date: return "Date"
        case .boolean: return "Toggle"
        case .url: return "Link"
        case .singleSelect: return "Single Select"
        }
    }
}

enum CustomFieldEntity: String, Codable, CaseIterable, Identifiable {
    case deal
    case contact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deal: return "Deal"
        case .contact: return "Contact"
        }
    }
}

enum LLMProviderKind: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openAI
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openAI: return "OpenAI"
        case .custom: return "Custom / Local"
        }
    }
}

/// Which source the Calendar tab reads events from.
enum CalendarSourceKind: String, CaseIterable, Identifiable {
    /// Google Calendar via OAuth (hand-rolled PKCE flow).
    case google
    /// The device's built-in calendar database via EventKit — reads whatever
    /// calendars are synced in System Settings → Internet Accounts.
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google Calendar"
        case .device: return "This Device"
        }
    }
}
