import SwiftUI
import SwiftData

/// Lists imported and manually created meeting notes, and hosts the Granola
/// import flow.
struct MeetingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingNote.date, order: .reverse) private var meetings: [MeetingNote]

    @State private var selection: MeetingNote?
    @State private var manualMeeting: MeetingNote?
    @State private var importCandidates: [GranolaMeeting] = []
    @State private var showingImport = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if meetings.isEmpty {
                EmptyStateView(
                    title: "No Meetings Yet",
                    message: "Import summaries from Granola, or add a meeting note manually.",
                    systemImage: "text.bubble",
                    actionTitle: "Import from Granola",
                    action: importFromGranola
                )
            } else {
                list
            }
        }
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Import from Granola…", systemImage: "square.and.arrow.down", action: importFromGranola)
                    Button("Add Manually…", systemImage: "square.and.pencil") { addManualMeeting() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $selection) { meeting in
            NavigationStack { MeetingDetailView(meeting: meeting) }
        }
        .sheet(isPresented: $showingImport) {
            GranolaImportSheet(candidates: importCandidates, existingIDs: Set(meetings.compactMap(\.externalID))) { chosen in
                importMeetings(chosen)
            }
        }
        .sheet(item: $manualMeeting) { meeting in
            NavigationStack {
                MeetingDetailView(meeting: meeting, isNew: true)
            }
        }
        .alert("Import Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var list: some View {
        List {
            ForEach(meetings) { meeting in
                Button {
                    selection = meeting
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(meeting.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Spacer()
                            if meeting.source == .granola {
                                Chip(text: "Granola", color: .purple)
                            }
                        }
                        Text(meeting.date, format: .dateTime.weekday().month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        if !meeting.summaryMarkdown.isEmpty {
                            Text(meeting.summaryMarkdown)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                for index in indexSet { modelContext.delete(meetings[index]) }
                try? modelContext.save()
            }
        }
    }

    // MARK: Import

    private func importFromGranola() {
        let apiKey = settings.granolaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            errorMessage = GranolaService.GranolaError.missingAPIKey.localizedDescription
            return
        }
        // @MainActor so the @State mutations after the await run on the main
        // actor; the network request itself still runs off-main in URLSession.
        Task { @MainActor in
            do {
                let parsed = try await GranolaService().importFromAPI(apiKey: apiKey)
                if parsed.isEmpty {
                    errorMessage = "No meetings came back from Granola. Only notes with a generated summary are available via the API — or add one manually."
                } else {
                    importCandidates = parsed
                    showingImport = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importMeetings(_ chosen: [GranolaMeeting]) {
        let existingIDs = Set(meetings.compactMap(\.externalID))
        for meeting in chosen where !existingIDs.contains(meeting.id) {
            let note = MeetingNote(
                title: meeting.title,
                summaryMarkdown: meeting.summaryMarkdown,
                transcript: meeting.transcript,
                date: meeting.date,
                source: .granola,
                externalID: meeting.id,
                attendeesText: meeting.attendees.joined(separator: ", ")
            )
            modelContext.insert(note)
        }
        try? modelContext.save()
    }

    private func addManualMeeting() {
        let meeting = MeetingNote(title: "New Meeting", source: .manual)
        modelContext.insert(meeting)
        manualMeeting = meeting
    }
}
