import SwiftUI
import SwiftData

/// Views / edits a meeting note, links it to contacts and a deal, and offers an
/// AI "extract action items" action.
struct MeetingDetailView: View {
    @Bindable var meeting: MeetingNote
    var isNew: Bool = false

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]

    @State private var showingContactPicker = false
    @State private var showingActionItems = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        Form {
            Section("Meeting") {
                TextField("Title", text: $meeting.title)
                DatePicker("Date", selection: $meeting.date)
                TextField("Attendees", text: $meeting.attendeesText, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("Summary") {
                TextField("Summary", text: $meeting.summaryMarkdown, axis: .vertical)
                    .lineLimit(4...20)
                    .font(.callout)
            }

            if !meeting.transcript.isEmpty {
                Section("Transcript") {
                    Text(meeting.transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Linked") {
                ForEach(meeting.contacts) { contact in
                    HStack {
                        AvatarView(initials: contact.initials, colorHex: contact.avatarColorHex, size: 26)
                        Text(contact.name)
                    }
                }
                Button {
                    showingContactPicker = true
                } label: { Label("Link Contacts", systemImage: "person.badge.plus") }

                Picker("Deal", selection: dealBinding) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(allDeals) { deal in
                        Text(deal.title).tag(Optional(deal.id))
                    }
                }
            }

            Section("AI Assistant") {
                if settings.isLLMConfigured {
                    Button {
                        showingActionItems = true
                    } label: { Label("Extract Action Items", systemImage: "checklist") }
                } else {
                    Label("Add an LLM API key in Settings to enable AI actions.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(meeting.title.isEmpty ? "Meeting" : meeting.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { try? modelContext.save(); dismiss() }
            }
            if !isNew {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete meeting")
                }
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(meeting.title)\u{201D}?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Meeting", role: .destructive) {
                modelContext.delete(meeting)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView(selected: meeting.contacts) { picked in
                meeting.contacts = picked
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showingActionItems) {
            AIResultSheet(title: "Action Items") {
                try await AIAssistant(manager: LLMManager(config: settings.activeLLMConfig)).extractActionItems(from: meeting)
            } onSave: { text in
                if let deal = meeting.deal {
                    let activity = Activity(kind: .task, title: "Action items from \(meeting.title)", body: text, source: .ai)
                    activity.deal = deal
                    modelContext.insert(activity)
                } else {
                    meeting.summaryMarkdown += "\n\n## Action Items\n" + text
                }
                try? modelContext.save()
            }
        }
    }

    private var allDeals: [Deal] {
        pipelines.flatMap(\.deals).sorted { $0.updatedAt > $1.updatedAt }
    }

    private var dealBinding: Binding<UUID?> {
        Binding(
            get: { meeting.deal?.id },
            set: { newID in meeting.deal = allDeals.first { $0.id == newID } }
        )
    }
}
