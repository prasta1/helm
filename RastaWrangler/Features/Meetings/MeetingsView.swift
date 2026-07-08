import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Lists imported and manually created meeting notes, styled for Helm.
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
        .background(Theme.Palette.canvas)
        .navigationTitle("Meetings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                    HStack(spacing: 14) {
                        // Date column
                        VStack(spacing: 2) {
                            Text(meeting.date, format: .dateTime.month(.abbreviated))
                                .font(.system(size: 10, weight: .bold))
                                .kerning(0.5)
                                .foregroundStyle(Theme.Palette.textMuted)
                            Text(meeting.date, format: .dateTime.day())
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(meeting.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if meeting.source == .granola {
                                    Chip(text: "Granola", color: .purple)
                                } else if meeting.source == .ai {
                                    Chip(text: "AI", systemImage: "sparkles", color: Theme.Palette.brass)
                                }
                            }
                            Text(meeting.date, format: .dateTime.weekday().hour().minute())
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            if !meeting.summaryMarkdown.isEmpty {
                                Text(meeting.summaryMarkdown)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Palette.textMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                for index in indexSet { modelContext.delete(meetings[index]) }
                try? modelContext.save()
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.canvas)
    }

    // MARK: Import (unchanged from original)

    private func importFromGranola() {
        #if os(macOS)
        do {
            let bookmark = try resolveOrPromptForGranolaAccess()
            let parsed = try GranolaService().importFromCache(bookmark: bookmark)
            if parsed.isEmpty {
                errorMessage = "No meetings were found in the Granola cache. Its format may have changed — try adding manually."
            } else {
                importCandidates = parsed
                showingImport = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        #else
        errorMessage = "Automatic Granola import runs on macOS. On iOS/iPad, add meetings manually or sync via iCloud from your Mac."
        addManualMeeting()
        #endif
    }

    #if os(macOS)
    private func resolveOrPromptForGranolaAccess() throws -> Data {
        if let bookmark = settings.granolaBookmark {
            return bookmark
        }
        let panel = NSOpenPanel()
        panel.message = "Select Granola's cache file (cache-v3.json) or its folder"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let defaultURL = GranolaService.defaultCacheURL {
            panel.directoryURL = defaultURL.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            throw GranolaService.GranolaError.accessDenied
        }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.granolaBookmark = bookmark
        return bookmark
    }
    #endif

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
