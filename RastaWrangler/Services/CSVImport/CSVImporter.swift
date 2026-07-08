import Foundation
import SwiftData

/// Parses CSV files and maps rows onto `Contact` / `Organization` records so the
/// database can be seeded from an export (Google Contacts, HubSpot, a spreadsheet…).
///
/// Header names are matched loosely (case-insensitive, punctuation ignored) against
/// a set of common aliases, so "Email Address", "e-mail" and "EMAIL" all map to the
/// same field. Rows that duplicate an existing record are flagged so the UI can
/// pre-mark them as skipped.
enum CSVImporter {

    /// A parsed CSV file: one header row plus data rows, all as plain strings.
    struct Table {
        let headers: [String]
        let rows: [[String]]
    }

    /// A contact row lifted out of the CSV, ready to preview and import.
    struct ContactCandidate: Identifiable {
        let id = UUID()
        var name: String
        var email: String
        var phone: String
        var title: String
        var company: String
        var notes: String
        /// True when a contact with the same email (or, lacking one, the same
        /// name) already exists — either in the database or earlier in the file.
        var isDuplicate: Bool
    }

    /// A company row lifted out of the CSV, ready to preview and import.
    struct CompanyCandidate: Identifiable {
        let id = UUID()
        var name: String
        var domain: String
        var notes: String
        /// True when an organization with the same name already exists —
        /// either in the database or earlier in the file.
        var isDuplicate: Bool
    }

    /// Thrown when the file can't be understood well enough to import.
    enum ImportError: LocalizedError {
        case unreadableFile
        case emptyFile
        case missingNameColumn

        var errorDescription: String? {
            switch self {
            case .unreadableFile: "The file couldn't be read as text."
            case .emptyFile: "The file has no data rows."
            case .missingNameColumn: "No name column found. Expected a header like “Name” (or “First Name” + “Last Name” for contacts)."
            }
        }
    }

    // MARK: - Parsing

    /// Reads a CSV/TSV file from disk and parses it into a `Table`.
    ///
    /// Tries UTF-8 first and falls back to Latin-1 (a superset of ASCII that can't
    /// fail to decode) so exports from older tools still open. The field delimiter
    /// (comma, semicolon, or tab) is auto-detected from the header row.
    static func loadTable(from url: URL) throws -> Table {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadableFile
        }
        return try parse(text)
    }

    /// Parses CSV text into headers + rows, handling quoted fields per RFC 4180:
    /// quotes may wrap fields containing the delimiter or newlines, and a doubled
    /// quote ("") inside a quoted field is a literal quote character.
    static func parse(_ raw: String) throws -> Table {
        // Strip a UTF-8 byte-order mark (Excel prepends one) so the first header
        // doesn't come out as "\u{FEFF}Name".
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let delimiter = detectDelimiter(in: text)

        // A tiny state machine: walk the file character by character, tracking
        // whether we're inside a quoted field, and cut fields/rows at delimiters
        // and newlines only when we're not.
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() {
            record.append(field.trimmingCharacters(in: .whitespaces))
            field = ""
        }
        func endRecord() {
            endField()
            // Skip blank lines (a record whose only field is empty).
            if !(record.count == 1 && record[0].isEmpty) {
                records.append(record)
            }
            record = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    // Either the closing quote or an escaped "" — peek one ahead.
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case delimiter:
                    endField()
                case "\n", "\r", "\r\n":
                    // Swift groups CRLF into a single Character (grapheme
                    // cluster), so a Windows/Excel line ending arrives here as
                    // one "\r\n" character — it must be matched explicitly.
                    endRecord()
                default:
                    field.append(char)
                }
            }
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }

        guard let headers = records.first, records.count > 1 else {
            throw ImportError.emptyFile
        }
        return Table(headers: headers, rows: Array(records.dropFirst()))
    }

    /// Picks the delimiter (comma, semicolon, or tab) that appears most often in
    /// the header line — semicolons cover European locales, tabs cover TSV.
    private static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.prefix(while: { !$0.isNewline })
        let counts: [(Character, Int)] = [",", ";", "\t"].map { delim in
            (delim, firstLine.filter { $0 == delim }.count)
        }
        return counts.max(by: { $0.1 < $1.1 })?.0 ?? ","
    }

    // MARK: - Header mapping

    /// Lowercases and strips everything but letters/digits so "E-mail Address",
    /// "email_address" and "Email Address" all normalize to "emailaddress".
    private static func normalize(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Finds the column index for the first alias that matches a header.
    private static func column(in headers: [String], aliases: [String]) -> Int? {
        let normalized = headers.map(normalize)
        for alias in aliases {
            if let index = normalized.firstIndex(of: alias) { return index }
        }
        return nil
    }

    private static func value(_ row: [String], at index: Int?) -> String {
        guard let index, index < row.count else { return "" }
        return row[index]
    }

    // MARK: - Contacts

    /// Maps a parsed table onto contact candidates, flagging duplicates against
    /// the given existing contacts (matched by email, falling back to name).
    static func contactCandidates(from table: Table, existing: [Contact]) throws -> [ContactCandidate] {
        let headers = table.headers
        let nameCol = column(in: headers, aliases: ["name", "fullname", "contactname", "contact"])
        let firstCol = column(in: headers, aliases: ["firstname", "first", "givenname"])
        let lastCol = column(in: headers, aliases: ["lastname", "last", "surname", "familyname"])
        guard nameCol != nil || firstCol != nil else { throw ImportError.missingNameColumn }

        let emailCol = column(in: headers, aliases: ["email", "emailaddress", "workemail", "primaryemail", "email1"])
        let phoneCol = column(in: headers, aliases: ["phone", "phonenumber", "mobile", "mobilephone", "workphone", "cell", "telephone"])
        let titleCol = column(in: headers, aliases: ["title", "jobtitle", "role", "position"])
        let companyCol = column(in: headers, aliases: ["company", "companyname", "organization", "organisation", "account", "accountname", "employer"])
        let notesCol = column(in: headers, aliases: ["notes", "note", "description", "comments"])

        var seenEmails = Set(existing.map { $0.email.lowercased() }.filter { !$0.isEmpty })
        var seenNames = Set(existing.map { $0.name.lowercased() })

        return table.rows.compactMap { row in
            var name = value(row, at: nameCol)
            if name.isEmpty {
                name = [value(row, at: firstCol), value(row, at: lastCol)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            guard !name.isEmpty else { return nil }

            let email = value(row, at: emailCol)
            let emailKey = email.lowercased()
            let nameKey = name.lowercased()
            let isDuplicate = emailKey.isEmpty ? seenNames.contains(nameKey) : seenEmails.contains(emailKey)
            if !emailKey.isEmpty { seenEmails.insert(emailKey) }
            seenNames.insert(nameKey)

            return ContactCandidate(
                name: name,
                email: email,
                phone: value(row, at: phoneCol),
                title: value(row, at: titleCol),
                company: value(row, at: companyCol),
                notes: value(row, at: notesCol),
                isDuplicate: isDuplicate
            )
        }
    }

    /// Inserts the given candidates as `Contact` records. A candidate with a
    /// company name is linked to a matching `Organization` (created on the fly if
    /// none exists). Returns the number of contacts inserted.
    @discardableResult
    static func importContacts(
        _ candidates: [ContactCandidate],
        organizations: [Organization],
        context: ModelContext
    ) -> Int {
        // Case-insensitive name → organization lookup, including ones created
        // during this same import so two rows at "Acme" share one record.
        var orgsByName: [String: Organization] = [:]
        for org in organizations { orgsByName[org.name.lowercased()] = org }

        for candidate in candidates {
            let contact = Contact(
                name: candidate.name,
                email: candidate.email,
                phone: candidate.phone,
                title: candidate.title,
                company: candidate.company,
                notes: candidate.notes
            )
            if !candidate.company.isEmpty {
                let key = candidate.company.lowercased()
                if let org = orgsByName[key] {
                    contact.organization = org
                } else {
                    let org = Organization(name: candidate.company)
                    context.insert(org)
                    orgsByName[key] = org
                    contact.organization = org
                }
            }
            context.insert(contact)
        }
        return candidates.count
    }

    // MARK: - Companies

    /// Maps a parsed table onto company candidates, flagging duplicates against
    /// the given existing organizations (matched by name).
    static func companyCandidates(from table: Table, existing: [Organization]) throws -> [CompanyCandidate] {
        let headers = table.headers
        guard let nameCol = column(in: headers, aliases: ["name", "company", "companyname", "organization", "organisation", "account", "accountname"]) else {
            throw ImportError.missingNameColumn
        }
        let domainCol = column(in: headers, aliases: ["domain", "website", "site", "url", "web"])
        let notesCol = column(in: headers, aliases: ["notes", "note", "description", "comments"])

        var seenNames = Set(existing.map { $0.name.lowercased() })

        return table.rows.compactMap { row in
            let name = value(row, at: nameCol)
            guard !name.isEmpty else { return nil }

            let nameKey = name.lowercased()
            let isDuplicate = seenNames.contains(nameKey)
            seenNames.insert(nameKey)

            return CompanyCandidate(
                name: name,
                domain: cleanDomain(value(row, at: domainCol)),
                notes: value(row, at: notesCol),
                isDuplicate: isDuplicate
            )
        }
    }

    /// Inserts the given candidates as `Organization` records. Existing contacts
    /// whose `company` string matches (and aren't linked yet) get attached.
    /// Returns the number of organizations inserted.
    @discardableResult
    static func importCompanies(
        _ candidates: [CompanyCandidate],
        contacts: [Contact],
        context: ModelContext
    ) -> Int {
        for candidate in candidates {
            let org = Organization(name: candidate.name, domain: candidate.domain, notes: candidate.notes)
            context.insert(org)
            let key = candidate.name.lowercased()
            for contact in contacts where contact.organization == nil && contact.company.lowercased() == key {
                contact.organization = org
            }
        }
        return candidates.count
    }

    /// Normalizes a website value down to a bare domain:
    /// "https://www.acme.com/about" → "acme.com".
    private static func cleanDomain(_ raw: String) -> String {
        var domain = raw.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "http://", "www."] {
            if domain.hasPrefix(prefix) { domain = String(domain.dropFirst(prefix.count)) }
        }
        if let slash = domain.firstIndex(of: "/") { domain = String(domain[..<slash]) }
        return domain
    }
}
