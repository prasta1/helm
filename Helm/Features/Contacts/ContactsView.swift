import SwiftUI
import SwiftData

/// A searchable directory of contacts with a detail pane.
struct ContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.name) private var contacts: [Contact]

    @State private var selection: Contact?
    @State private var search = ""

    var body: some View {
        Group {
            if contacts.isEmpty {
                EmptyStateView(
                    title: "No Contacts Yet",
                    message: "Add the people you're tracking — recruiters, hiring managers, prospects.",
                    systemImage: "person.crop.circle.badge.plus",
                    actionTitle: "Add Contact",
                    action: addContact
                )
            } else {
                list
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem {
                Button(action: addContact) { Label("Add Contact", systemImage: "plus") }
            }
        }
        .sheet(item: $selection) { contact in
            NavigationStack { ContactDetailView(contact: contact) }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { contact in
                Button {
                    selection = contact
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                            let subtitle = [contact.title, contact.company].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !contact.deals.isEmpty {
                            Chip(text: "\(contact.deals.count)", systemImage: "square.stack", color: Theme.Palette.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .searchable(text: $search, prompt: "Search contacts")
    }

    private var filtered: [Contact] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.company.localizedCaseInsensitiveContains(search) ||
            $0.email.localizedCaseInsensitiveContains(search)
        }
    }

    private func addContact() {
        let contact = Contact(name: "New Contact")
        modelContext.insert(contact)
        try? modelContext.save()
        selection = contact
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(filtered[index]) }
        try? modelContext.save()
    }
}
