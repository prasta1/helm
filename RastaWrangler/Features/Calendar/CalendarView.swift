import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

// MARK: - Router

/// Routes to the active calendar source, wrapped in Helm design.
struct CalendarView: View {
    var body: some View {
        HelmWeekCalendarView()
            .navigationTitle("Calendar")
    }
}

// MARK: - Helm Week Calendar

/// A week-view calendar matching the Helm design — real events from the active
/// source (Apple via EventKit, or Google) laid out on one time grid with
/// calendar colors and a current-time indicator.
private struct HelmWeekCalendarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    @State private var currentWeekStart: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
    ) ?? .now
    @State private var viewMode: CalendarViewMode = .week
    @State private var events: [CalendarEvent] = []
    @State private var deviceCalendars: [DeviceCalendar] = []
    @State private var deviceDenied = false
    @State private var loadErrorMessage: String?
    @State private var showingNewEvent = false

    @State private var deviceService = EventKitCalendarService()
    @StateObject private var googleAuth: GoogleAuth
    @State private var googleService: GoogleCalendarService?

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 52
    private let timeColumnWidth: CGFloat = 56

    init() {
        // RootView keys CalendarView with `.id(...)` so this re-inits when the
        // client ID or calendar source changes.
        _googleAuth = StateObject(wrappedValue: GoogleAuth(clientID: AppSettings().googleClientID))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 18)

            // Source status banner (permission / sign-in), when needed
            if let model = bannerModel {
                statusBanner(model)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 14)
            }

            // Week grid
            weekGrid
                .padding(.horizontal, 36)
                .padding(.bottom, 20)

            // Ask bar
            askBar
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .background(Theme.Palette.canvas)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: reloadKey) { await loadEvents() }
        .onReceive(NotificationCenter.default.publisher(for: EventKitCalendarService.changeNotification)) { _ in
            Task { await loadEvents() }
        }
        .sheet(isPresented: $showingNewEvent) {
            NewEventSheet(
                calendars: deviceCalendars.filter(\.allowsModifications),
                service: deviceService
            )
        }
    }

    /// Changing any of these re-runs the `.task` that loads events.
    private var reloadKey: String {
        let calendarsKey = settings.enabledCalendarIDs.map { $0.sorted().joined(separator: ",") } ?? "all"
        return "\(currentWeekStart.timeIntervalSince1970)|\(settings.calendarSource.rawValue)|\(calendarsKey)|\(googleAuth.isSignedIn)"
    }

    // MARK: Data loading

    private func loadEvents() async {
        loadErrorMessage = nil
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart

        switch settings.calendarSource {
        case .device:
            if !deviceService.hasFullAccess, !deviceService.isDenied {
                _ = try? await deviceService.requestAccess()
            }
            deviceDenied = deviceService.isDenied
            guard deviceService.hasFullAccess else {
                events = []
                return
            }
            deviceCalendars = deviceService.calendars()
            events = deviceService.events(
                from: currentWeekStart, to: weekEnd,
                calendarIDs: settings.enabledCalendarIDs
            )

        case .google:
            guard !settings.googleClientID.isEmpty, googleAuth.isSignedIn else {
                events = []
                return
            }
            let service = googleService ?? GoogleCalendarService(auth: googleAuth)
            googleService = service
            do {
                events = try await service.events(from: currentWeekStart, to: weekEnd, maxResults: 250)
            } catch {
                events = []
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Source status banner

    private struct BannerModel {
        let title: String
        let message: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    private var bannerModel: BannerModel? {
        switch settings.calendarSource {
        case .device where deviceDenied:
            return BannerModel(
                title: "Calendar access is switched off",
                message: "Helm can show your Apple calendars once access is granted.",
                actionTitle: "Open Settings",
                action: { if let url = privacySettingsURL { openURL(url) } }
            )
        case .google where settings.googleClientID.isEmpty:
            return BannerModel(
                title: "Google Calendar isn't configured",
                message: "Add your Google OAuth Client ID in Settings, or switch the source to This Device."
            )
        case .google where !googleAuth.isSignedIn:
            return BannerModel(
                title: "Sign in to Google",
                message: "Grant read access to your calendars to see your week.",
                actionTitle: "Sign In",
                action: { Task { try? await googleAuth.signIn() } }
            )
        case _ where loadErrorMessage != nil:
            return BannerModel(title: "Couldn't load events", message: loadErrorMessage ?? "")
        default:
            return nil
        }
    }

    private func statusBanner(_ model: BannerModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.brassDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(model.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if let actionTitle = model.actionTitle, let action = model.action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.brassDim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.Palette.focusBg, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.focusBorder, lineWidth: 1)
        )
    }

    private var privacySettingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #else
        URL(string: UIApplication.openSettingsURLString)
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedMonthYear)
                    .font(.system(size: 23, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text("WEEK \(weekNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textMuted)
            }

            Spacer()

            // Calendar filter (device source only)
            if settings.calendarSource == .device, !deviceCalendars.isEmpty {
                calendarFilterMenu
            }

            // Day nav
            HStack(spacing: 0) {
                Button(action: previousWeek) {
                    Text("‹")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Button(action: goToToday) {
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Button(action: nextWeek) {
                    Text("›")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )

            // View mode toggle
            HStack(spacing: 2) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewMode = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(viewMode == mode ? .white : Theme.Palette.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .background(
                                viewMode == mode ? Theme.Palette.navy : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Theme.Palette.tagBg, in: RoundedRectangle(cornerRadius: 8))

            // New event (device source only — Google is read-only)
            if settings.calendarSource == .device, deviceService.hasFullAccess {
                Button {
                    showingNewEvent = true
                } label: {
                    Text("+ New event")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.navy)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Theme.Palette.brass, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "MY CALENDARS" visibility toggles, matching the design's sidebar list.
    private var calendarFilterMenu: some View {
        Menu {
            ForEach(deviceCalendars) { deviceCalendar in
                Button {
                    toggleCalendar(deviceCalendar.id)
                } label: {
                    if isCalendarEnabled(deviceCalendar.id) {
                        Label("\(deviceCalendar.title) — \(deviceCalendar.sourceName)", systemImage: "checkmark")
                    } else {
                        Text("\(deviceCalendar.title) — \(deviceCalendar.sourceName)")
                    }
                }
            }
            Divider()
            Button("Show all") { settings.enabledCalendarIDs = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                Text("Calendars")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func isCalendarEnabled(_ id: String) -> Bool {
        settings.enabledCalendarIDs?.contains(id) ?? true
    }

    private func toggleCalendar(_ id: String) {
        var enabled = settings.enabledCalendarIDs ?? Set(deviceCalendars.map(\.id))
        if enabled.contains(id) {
            enabled.remove(id)
        } else {
            enabled.insert(id)
        }
        // Back to nil ("all") when everything is re-enabled.
        settings.enabledCalendarIDs = enabled.count == deviceCalendars.count ? nil : enabled
    }

    // MARK: Week Grid

    private var weekGrid: some View {
        VStack(spacing: 0) {
            // Day headers
            HStack(spacing: 0) {
                // Time column spacer
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: timeColumnWidth)

                ForEach(weekDays, id: \.self) { day in
                    dayHeader(day)
                        .frame(maxWidth: .infinity)
                }
            }
            .overlay(
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Time grid
            ScrollView {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        // Hour rows
                        VStack(spacing: 0) {
                            ForEach(workingHours, id: \.self) { hour in
                                hourRow(hour)
                            }
                        }

                        // Events positioned absolutely by weekday and time
                        ForEach(placedEvents(gridWidth: geo.size.width)) { placed in
                            eventPill(placed)
                                .position(
                                    x: placed.x + placed.width / 2,
                                    y: placed.top + placed.height / 2
                                )
                        }

                        // Current time indicator
                        if isThisWeek {
                            currentTimeIndicator
                        }
                    }
                }
                .frame(height: hourHeight * CGFloat(workingHours.count))
            }
            .overlay(
                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(height: 1),
                alignment: .top
            )
        }
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func dayHeader(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let dayNum = calendar.component(.day, from: date)
        let dayName = dayFormatter.string(from: date).uppercased()

        return VStack(spacing: 4) {
            Text(dayName)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(isToday ? Theme.Palette.brassDim : Theme.Palette.textMuted)
            Text("\(dayNum)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isToday ? Theme.Palette.navy : Theme.Palette.textSecondary)
                .background(
                    isToday ?
                        Circle()
                            .fill(Theme.Palette.brass)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("\(dayNum)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.Palette.navy)
                            )
                        : nil
                )
                .frame(width: 24, height: 24)
        }
        .padding(.vertical, 10)
        .background(isToday ? Theme.Palette.focusBg.opacity(0.3) : Color.clear)
    }

    private func hourRow(_ hour: Int) -> some View {
        HStack(spacing: 0) {
            // Time label
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 8)

            // Day columns
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .fill(Theme.Palette.hairline)
                                .frame(height: 1),
                            alignment: .top
                        )
                        .overlay(
                            Rectangle()
                                .fill(Theme.Palette.hairline)
                                .frame(width: 1),
                            alignment: .leading
                        )
                }
            }
        }
        .frame(height: hourHeight)
    }

    private var isThisWeek: Bool {
        calendar.isDate(currentWeekStart, equalTo: calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        ) ?? currentWeekStart, toGranularity: .weekOfYear)
    }

    private var currentTimeIndicator: some View {
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let startHour = workingHours.first ?? 8
        let fractionalHour = CGFloat(hour - startHour) + CGFloat(minute) / 60.0
        let yOffset = fractionalHour * hourHeight

        // A brass "now" line spanning the day columns, with a dot at the gutter
        // edge. The dot and line are vertically centred by the HStack, so both
        // sit on the same baseline; the whole row is dropped to the current time.
        return HStack(spacing: 0) {
            Circle()
                .fill(Theme.Palette.brass)
                .frame(width: 9, height: 9)
            Rectangle()
                .fill(Theme.Palette.brass)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
        }
        .padding(.leading, timeColumnWidth - 4)
        .offset(y: yOffset - 4)
    }

    // MARK: Event placement

    /// Lays real events onto the grid: column = weekday, y/height = time/duration.
    private func placedEvents(gridWidth: CGFloat) -> [PlacedEvent] {
        let columnWidth = (gridWidth - timeColumnWidth) / 7
        guard columnWidth > 0 else { return [] }
        let startHour = CGFloat(workingHours.first ?? 8)
        let gridHeight = hourHeight * CGFloat(workingHours.count)

        return events.compactMap { event in
            guard !event.isAllDay else { return nil }
            let dayStart = calendar.startOfDay(for: event.start)
            guard let dayIndex = calendar.dateComponents([.day], from: currentWeekStart, to: dayStart).day,
                  (0..<7).contains(dayIndex) else { return nil }

            let startFraction = CGFloat(calendar.component(.hour, from: event.start))
                + CGFloat(calendar.component(.minute, from: event.start)) / 60 - startHour
            let duration = CGFloat(event.end.timeIntervalSince(event.start)) / 3600

            var top = startFraction * hourHeight
            var height = max(duration * hourHeight, 22)
            // Clip events that spill outside the visible 08:00–19:00 window.
            if top < 0 {
                height += top
                top = 0
            }
            guard top < gridHeight, height > 8 else { return nil }
            height = min(height, gridHeight - top)

            return PlacedEvent(
                id: event.id,
                event: event,
                x: timeColumnWidth + CGFloat(dayIndex) * columnWidth + 4,
                top: top + 2,
                height: height,
                width: columnWidth - 8
            )
        }
    }

    private func eventPill(_ placed: PlacedEvent) -> some View {
        let isFocus = placed.event.title.localizedCaseInsensitiveContains("focus")
        let fillColor = isFocus
            ? Theme.Palette.focusBg
            : Color(hex: placed.event.colorHex.isEmpty ? "#5B8DB8" : placed.event.colorHex)

        return VStack(alignment: .leading, spacing: 2) {
            Text(placed.event.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isFocus ? Theme.Palette.focusText : .white)
                .lineLimit(1)

            if placed.height > 30 {
                Text(placed.event.timeRangeText)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(isFocus ? Theme.Palette.focusText.opacity(0.8) : .white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: placed.width, height: placed.height, alignment: .topLeading)
        .background(fillColor)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.Palette.focusBorder, lineWidth: isFocus ? 1 : 0)
        )
    }

    // MARK: Data helpers

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: currentWeekStart) }
    }

    private var workingHours: [Int] {
        Array(8...18)
    }

    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: currentWeekStart)
    }

    private var formattedMonthYear: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df.string(from: currentWeekStart)
    }

    private func previousWeek() {
        currentWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) ?? currentWeekStart
    }

    private func nextWeek() {
        currentWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) ?? currentWeekStart
    }

    private func goToToday() {
        currentWeekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        ) ?? currentWeekStart
    }

    private var askBar: some View {
        HStack(spacing: 12) {
            CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.surface)
                .frame(width: 15, height: 15)

            Text("Ask Helm — “find 90 min for the deck before Thu”, “move dentist to next week”…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.sidebarMuted)
                .lineLimit(1)

            Spacer()

            Text("\u{2318}J")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.Palette.sidebarMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.Palette.sidebarDark.opacity(0.5), lineWidth: 1)
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            Theme.Palette.navy,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
    }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
}

// MARK: - New event sheet

/// Minimal event composer: title, day, start time, duration, calendar.
/// Writes through EventKit; Helm never edits existing events.
private struct NewEventSheet: View {
    let calendars: [DeviceCalendar]
    let service: EventKitCalendarService

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var startDate: Date = Self.nextRoundHour()
    @State private var durationMinutes = 60
    @State private var calendarID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Event")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            DatePicker("Starts", selection: $startDate)

            Picker("Duration", selection: $durationMinutes) {
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("90 min").tag(90)
                Text("2 hours").tag(120)
            }

            Picker("Calendar", selection: $calendarID) {
                Text("Default").tag(String?.none)
                ForEach(calendars) { deviceCalendar in
                    Text("\(deviceCalendar.title) — \(deviceCalendar.sourceName)")
                        .tag(String?.some(deviceCalendar.id))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Palette.danger)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Event") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private func save() {
        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
        do {
            try service.createEvent(
                title: title.trimmingCharacters(in: .whitespaces),
                start: startDate,
                end: end,
                calendarID: calendarID
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The next whole hour — a sensible default start time.
    private static func nextRoundHour() -> Date {
        let cal = Calendar.current
        let thisHour = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: .now)) ?? .now
        return cal.date(byAdding: .hour, value: 1, to: thisHour) ?? thisHour
    }
}

// MARK: - Supporting types

private enum CalendarViewMode: String, CaseIterable {
    case day, week, month

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

private struct PlacedEvent: Identifiable {
    let id: String
    let event: CalendarEvent
    /// Leading x of the pill within the grid (includes the time gutter).
    let x: CGFloat
    let top: CGFloat
    let height: CGFloat
    let width: CGFloat
}

#Preview {
    NavigationStack {
        CalendarView()
            .environment(AppSettings())
            .modelContainer(PersistenceController.makeInMemoryContainer())
    }
}
