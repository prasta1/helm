import SwiftUI
import SwiftData

/// A searchable multi-select sheet for linking contacts to a deal or meeting.
struct ContactPickerView: View {
    let selected: [Contact]
    let onDone: ([Contact]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.name) private var contacts: [Contact]

    @State private var selectedIDs: Set<UUID> = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView("No Contacts", systemImage: "person.crop.circle.badge.questionmark")
                }
                ForEach(filtered) { contact in
                    Button {
                        toggle(contact)
                    } label: {
                        HStack {
                            AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 30)
                            VStack(alignment: .leading) {
                                Text(contact.name).foregroundStyle(.primary)
                                if !contact.company.isEmpty {
                                    Text(contact.company).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedIDs.contains(contact.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Search contacts")
            .navigationTitle("Link Contacts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(contacts.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                }
            }
        }
        .onAppear { selectedIDs = Set(selected.map(\.id)) }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
    }

    private var filtered: [Contact] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.company.localizedCaseInsensitiveContains(search)
        }
    }

    private func toggle(_ contact: Contact) {
        if selectedIDs.contains(contact.id) {
            selectedIDs.remove(contact.id)
        } else {
            selectedIDs.insert(contact.id)
        }
    }
}
