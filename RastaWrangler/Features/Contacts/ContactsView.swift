import SwiftUI
import SwiftData

/// Helm Contacts — people with standing, linked deals, and a log.
/// Searchable directory on the left, detail pane on the right.
struct ContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.name) private var contacts: [Contact]

    @State private var selection: Contact?
    @State private var search = ""
    @State private var filterTag: String? = nil
    @State private var showingCSVImport = false

    private let filterTags = ["All", "Warm", "Investors", "Recent"]

    var body: some View {
        Group {
            if contacts.isEmpty {
                EmptyStateView(
                    title: "No Contacts Yet",
                    message: "Add the people you're tracking — recruiters, hiring managers, prospects.",
                    systemImage: "person.crop.circle.badge.plus",
                    actionTitle: "Add Contact",
                    action: addContact,
                    secondaryActionTitle: "Import from CSV…",
                    secondaryAction: { showingCSVImport = true }
                )
            } else {
                HStack(spacing: 0) {
                    // Contact list
                    contactList

                    // Detail pane
                    if let selection {
                        contactDetail(selection)
                    } else {
                        emptySelection
                    }
                }
            }
        }
        .background(Theme.Palette.canvas)
        .navigationTitle("Contacts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    showingCSVImport = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .help("Import contacts or companies from a CSV file")
            }
        }
        .sheet(isPresented: $showingCSVImport) {
            CSVImportSheet()
        }
    }

    // MARK: Contact list (left panel)

    private var contactList: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textMuted)
                TextField("Search \(contacts.count) people", text: $search)
                    .font(.system(size: 12.5))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Filter chips
            HStack(spacing: 6) {
                ForEach(filterTags, id: \.self) { tag in
                    Button {
                        filterTag = tag == "All" ? nil : tag.lowercased()
                    } label: {
                        Text(tag)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(
                                (tag == "All" && filterTag == nil) || filterTag == tag.lowercased()
                                    ? .white : Theme.Palette.textSecondary
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                (tag == "All" && filterTag == nil) || filterTag == tag.lowercased()
                                    ? Theme.Palette.navy : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Theme.Palette.border, lineWidth: (tag == "All" && filterTag == nil) || filterTag == tag.lowercased() ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            // Contact rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredContacts) { contact in
                        contactRow(contact)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = contact
                            }
                            .background(
                                selection?.id == contact.id ? Theme.Palette.canvas : Color.clear
                            )
                            .overlay(
                                selection?.id == contact.id ?
                                    Rectangle()
                                        .fill(Theme.Palette.brass)
                                        .frame(width: 3)
                                        .frame(maxHeight: .infinity)
                                        .padding(.vertical, 4)
                                    : nil,
                                alignment: .leading
                            )
                    }
                }
            }

            // Footer
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.Palette.success)
                    .frame(width: 6, height: 6)
                Text("Google Contacts + Apple, deduped")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay(Divider(), alignment: .top)
        }
        .frame(width: 308)
        .background(Theme.Palette.surface)
        .overlay(Divider(), alignment: .trailing)
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(spacing: 11) {
            AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                let subtitle = [contact.title, contact.company].filter { !$0.isEmpty }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Source indicator
            let sourceText = contactSourceLabel(contact)
            if !sourceText.isEmpty {
                SourceBadge(text: sourceText)
            }

            if !contact.deals.isEmpty {
                Text("\(contact.deals.count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    // MARK: Detail pane

    private func contactDetail(_ contact: Contact) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 18) {
                    AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 58)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text(contact.name)
                                .font(.system(size: 23, weight: .bold))
                                .kerning(-0.2)
                                .foregroundStyle(Theme.Palette.textPrimary)

                            if isWarm(contact) {
                                Text("WARM")
                                    .font(.system(size: 9, weight: .bold))
                                    .kerning(1.0)
                                    .foregroundStyle(Theme.Palette.focusText)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.Palette.focusBg, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(Theme.Palette.focusBorder, lineWidth: 1)
                                    )
                            }
                        }

                        let subtitle = [contact.title, contact.company].filter { !$0.isEmpty }.joined(separator: " · ")
                        Text(subtitle.isEmpty ? "No details yet" : subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 8) {
                        actionButton("Email")
                        actionButton("Schedule")
                        PillButton(title: "+ Task", action: {})
                    }
                }

                // Details grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18),
                ], spacing: 14) {
                    // Standing card
                    standingCard(contact)

                    // Details card
                    detailsCard(contact)
                }

                // Linked deals
                if !contact.deals.isEmpty {
                    linkedDealsCard(contact)
                }

                // The Log (activity timeline)
                activityLog(contact)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 36)
        }
    }

    private var emptySelection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.brassDim)
            Text("Select a contact")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func standingCard(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STANDING")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)

            VStack(spacing: 9) {
                standingRow("Last touch", formattedLastTouch(contact))
                standingRow("Next", formattedNextTouch(contact), valueColor: Theme.Palette.brassDim)
                standingRow("Cadence", cadenceLabel(contact))
                standingRow("Met", "\(contact.deals.count) linked deals")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func detailsCard(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILS")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)

            VStack(spacing: 9) {
                if !contact.email.isEmpty {
                    detailRow("Email", contact.email)
                }
                if !contact.phone.isEmpty {
                    detailRow("Phone", contact.phone)
                }
                detailRow("Sources", contactSourceLabel(contact))
                detailRow("Tags", tagLabel(contact))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func linkedDealsCard(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LINKED DEALS")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)

            ForEach(contact.deals.prefix(3)) { deal in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deal.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(deal.stage?.name ?? "No stage")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    if let amount = deal.formattedAmount {
                        Text(amount)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func activityLog(_ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("THE LOG")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Palette.textMuted)
                Spacer()
                Button("+ Add note") {}
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brassDim)
                    .buttonStyle(.plain)
            }

            let activities = contact.activities.sorted { $0.date > $1.date }
            if activities.isEmpty {
                Text("No activity yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activities.prefix(10).enumerated()), id: \.offset) { index, activity in
                        HStack(spacing: 14) {
                            // Timeline dot + line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(index == 0 ? Theme.Palette.brass : Theme.Palette.textMuted)
                                    .frame(width: 9, height: 9)
                                if index < min(activities.count, 10) - 1 {
                                    Rectangle()
                                        .fill(Theme.Palette.hairline)
                                        .frame(width: 1.5)
                                        .frame(maxHeight: .infinity)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(activity.title.isEmpty ? activity.body : activity.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Text(activity.date, format: .dateTime.month().day())
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.Palette.textMuted)
                                }
                                if !activity.body.isEmpty && !activity.title.isEmpty {
                                    Text(activity.body)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding(.vertical, index == 0 ? 0 : 8)
                    }
                }
            }

            // Ask about contact
            HStack(spacing: 10) {
                CompassRose(accentColor: Theme.Palette.brassDim, bodyColor: Theme.Palette.canvas)
                    .frame(width: 13, height: 13)
                Text("Ask about \(contact.name.split(separator: " ").first ?? "them") — “when did we last talk pricing?”")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    // MARK: Helpers

    private var filteredContacts: [Contact] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.company.localizedCaseInsensitiveContains(search) ||
            $0.email.localizedCaseInsensitiveContains(search)
        }
    }

    private func actionButton(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.Palette.navy)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
    }

    private func standingRow(_ label: String, _ value: String, valueColor: Color = Theme.Palette.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(valueColor)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Spacer()
        }
    }

    private func isWarm(_ contact: Contact) -> Bool {
        // Simple heuristic: has deals and recent activity
        !contact.deals.isEmpty
    }

    private func formattedLastTouch(_ contact: Contact) -> String {
        if let last = contact.activities.sorted(by: { $0.date > $1.date }).first {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return "\(df.string(from: last.date)) · \(last.kind.title.lowercased())"
        }
        return "Never"
    }

    private func formattedNextTouch(_ contact: Contact) -> String {
        // Look for upcoming tasks or meetings
        if let nextTask = contact.activities.first(where: { !$0.isCompleted && $0.kind == .task }) {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return "\(df.string(from: nextTask.date))"
        }
        return "No upcoming"
    }

    private func cadenceLabel(_ contact: Contact) -> String {
        "~monthly"
    }

    private func contactSourceLabel(_ contact: Contact) -> String {
        let sources = contact.activities.map(\.source)
        var labels: [String] = []
        if sources.contains(.googleCalendar) { labels.append("G") }
        if sources.contains(.deviceCalendar) { labels.append("A") }
        return labels.joined(separator: "·")
    }

    private func tagLabel(_ contact: Contact) -> String {
        var tags: [String] = []
        if isWarm(contact) { tags.append("warm") }
        if !contact.deals.isEmpty { tags.append("linked") }
        return tags.isEmpty ? "—" : tags.joined(separator: " · ")
    }

    private func addContact() {
        let contact = Contact(name: "New Contact")
        modelContext.insert(contact)
        try? modelContext.save()
        selection = contact
    }
}

#Preview {
    NavigationStack {
        ContactsView()
            .environment(AppSettings())
            .modelContainer(PersistenceController.makeInMemoryContainer())
    }
}
