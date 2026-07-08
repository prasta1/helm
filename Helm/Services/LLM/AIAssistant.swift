import Foundation

/// High-level AI features built on top of `LLMManager`. Each method turns CRM
/// context into a prompt, calls the model, and returns text the UI can show or
/// insert as an activity.
struct AIAssistant {
    let manager: LLMManager

    private static let systemPrompt = LLMMessage.system(
        """
        You are the assistant inside Helm, a personal CRM used for job \
        searching and business development ("Peregrine Prospects"). Be concise, \
        practical and warm. When asked to draft outreach, write in first person \
        as the user. Prefer plain language over jargon. Use markdown when it \
        aids readability.
        """
    )

    // MARK: Deals

    /// Suggests concrete next steps to move a deal forward.
    func suggestNextSteps(for deal: Deal) async throws -> String {
        let prompt = """
        Here is a deal from my \(deal.pipeline?.name ?? "pipeline") pipeline. \
        Suggest 3–5 specific next actions to move it forward, as a short checklist.

        \(Self.describe(deal))
        """
        return try await manager.complete(messages: [Self.systemPrompt, .user(prompt)], maxTokens: 700)
    }

    /// Drafts a follow-up message to a contact on a deal.
    func draftFollowUp(for deal: Deal, tone: String = "friendly and professional") async throws -> String {
        let contactLine = deal.contacts.first.map { "The primary contact is \($0.name)\($0.title.isEmpty ? "" : ", \($0.title)")\($0.company.isEmpty ? "" : " at \($0.company)")." } ?? "There is no named contact yet."
        let prompt = """
        Draft a \(tone) follow-up email for this deal. \(contactLine) \
        Keep it under 150 words and end with a clear call to action. \
        Return only the email body.

        \(Self.describe(deal))
        """
        return try await manager.complete(messages: [Self.systemPrompt, .user(prompt)], maxTokens: 600)
    }

    // MARK: Meetings

    /// Extracts action items from a meeting summary.
    func extractActionItems(from meeting: MeetingNote) async throws -> String {
        let prompt = """
        From the meeting notes below, extract a short markdown checklist of \
        action items and who owns each (if stated). If there are none, say so.

        Title: \(meeting.title)
        Attendees: \(meeting.attendeesText)

        \(meeting.summaryMarkdown.isEmpty ? meeting.transcript : meeting.summaryMarkdown)
        """
        return try await manager.complete(messages: [Self.systemPrompt, .user(prompt)], maxTokens: 700)
    }

    // MARK: Contacts

    /// Generates a brief on a contact to prep for a conversation.
    func prepBrief(for contact: Contact) async throws -> String {
        let deals = contact.deals.map(\.title).joined(separator: ", ")
        let prompt = """
        Write a short prep brief (3–4 bullets) to help me before speaking with \
        this contact: what to remember, what to ask, and how to add value.

        Name: \(contact.name)
        Title: \(contact.title)
        Company: \(contact.company)
        Related deals: \(deals.isEmpty ? "none" : deals)
        Notes: \(contact.notes.isEmpty ? "none" : contact.notes)
        """
        return try await manager.complete(messages: [Self.systemPrompt, .user(prompt)], maxTokens: 500)
    }

    // MARK: Free-form

    /// A general chat turn with optional pipeline context.
    func ask(_ question: String, context: String? = nil) async throws -> String {
        var messages: [LLMMessage] = [Self.systemPrompt]
        if let context, !context.isEmpty {
            messages.append(.user("Context:\n\(context)"))
        }
        messages.append(.user(question))
        return try await manager.complete(messages: messages, maxTokens: 1024)
    }

    // MARK: Prompt building

    private static func describe(_ deal: Deal) -> String {
        var lines: [String] = []
        lines.append("Title: \(deal.title)")
        lines.append("Stage: \(deal.stage?.name ?? "—")")
        lines.append("Status: \(deal.status.title)")
        if let amount = deal.formattedAmount { lines.append("Value: \(amount)") }
        if !deal.contacts.isEmpty {
            lines.append("Contacts: " + deal.contacts.map { "\($0.name) (\($0.title))" }.joined(separator: "; "))
        }
        if !deal.details.isEmpty { lines.append("Details: \(deal.details)") }
        let recent = deal.activities.sorted { $0.date > $1.date }.prefix(5)
        if !recent.isEmpty {
            lines.append("Recent activity:")
            for a in recent {
                lines.append("- [\(a.kind.title)] \(a.title.isEmpty ? a.body : a.title)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
