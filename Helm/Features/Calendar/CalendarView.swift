import SwiftUI
import SwiftData

/// Shows upcoming Google Calendar events and lets the user pull them into the
/// CRM as meeting notes.
struct CalendarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @StateObject private var auth: GoogleAuth
    @State private var service: GoogleCalendarService?
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init() {
        // Note: `RootView` gives this view `.id(settings.googleClientID)` so it
        // is re-created (and re-initialized) whenever the client id changes.
        _auth = StateObject(wrappedValue: GoogleAuth(clientID: AppSettings().googleClientID))
    }

    var body: some View {
        Group {
            if settings.googleClientID.isEmpty {
                EmptyStateView(
                    title: "Connect Google Calendar",
                    message: "Add your Google OAuth Client ID in Settings, then sign in to see your upcoming events here.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else if !auth.isSignedIn {
                EmptyStateView(
                    title: "Sign in to Google",
                    message: "Grant read access to your calendars to see upcoming meetings.",
                    systemImage: "calendar",
                    actionTitle: "Connect Google Calendar",
                    action: signIn
                )
            } else {
                eventsList
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            if auth.isSignedIn {
                ToolbarItem {
                    Button(action: { Task { await loadEvents() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            auth.signOut()
                            events = []
                        }
                    } label: { Label("Account", systemImage: "person.crop.circle") }
                }
            }
        }
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn { await loadEvents() }
        }
        .alert("Calendar", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var eventsList: some View {
        Group {
            if isLoading && events.isEmpty {
                ProgressView("Loading events…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                EmptyStateView(title: "No Upcoming Events", message: "You're all clear for the next week.", systemImage: "calendar")
            } else {
                List {
                    ForEach(groupedByDay, id: \.0) { day, dayEvents in
                        Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                            ForEach(dayEvents) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.accent).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium))
                HStack(spacing: Theme.Spacing.sm) {
                    Text(event.timeRangeText)
                    if !event.location.isEmpty {
                        Text("· \(event.location)").lineLimit(1)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                saveAsMeeting(event)
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Save as meeting note")
        }
    }

    private var groupedByDay: [(Date, [CalendarEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
        return groups.sorted { $0.key < $1.key }
    }

    // MARK: Actions

    private func signIn() {
        Task {
            do { try await auth.signIn() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func loadEvents() async {
        isLoading = true
        defer { isLoading = false }
        let service = self.service ?? GoogleCalendarService(auth: auth)
        self.service = service
        do {
            let now = Date()
            let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            events = try await service.events(from: now, to: weekOut)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsMeeting(_ event: CalendarEvent) {
        let note = MeetingNote(
            title: event.title,
            summaryMarkdown: "",
            date: event.start,
            source: .googleCalendar,
            externalID: event.id,
            attendeesText: event.attendees.joined(separator: ", "),
            calendarEventID: event.id
        )
        modelContext.insert(note)
        try? modelContext.save()
    }
}
