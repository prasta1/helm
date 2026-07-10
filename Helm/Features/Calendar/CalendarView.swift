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

// MARK: - Helm Calendar

private struct HelmWeekCalendarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    @State private var anchorDate: Date = Calendar.current.date(
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
        _googleAuth = StateObject(wrappedValue: GoogleAuth(clientID: AppSettings().googleClientID))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 18)

            if let model = bannerModel {
                statusBanner(model)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 14)
            }

            Group {
                if viewMode == .month {
                    monthGrid
                } else {
                    timeGrid
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 20)

            askBar
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .background(Theme.Palette.canvas)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: reloadKey) { await loadEvents() }
        .onChange(of: viewMode) { _, newMode in snapAnchor(for: newMode) }
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

    private var reloadKey: String {
        let calendarsKey = settings.enabledCalendarIDs.map { $0.sorted().joined(separator: ",") } ?? "all"
        return "\(anchorDate.timeIntervalSince1970)|\(viewMode.rawValue)|\(settings.calendarSource.rawValue)|\(calendarsKey)|\(googleAuth.isSignedIn)"
    }

    // MARK: Anchor management

    private func snapAnchor(for mode: CalendarViewMode) {
        switch mode {
        case .day:
            anchorDate = calendar.startOfDay(for: anchorDate)
        case .week:
            anchorDate = mondayOfWeek(containing: anchorDate)
        case .month:
            anchorDate = calendar.date(from: calendar.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        }
    }

    private func mondayOfWeek(containing date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysToMonday = (weekday - 2 + 7) % 7
        return calendar.date(byAdding: .day, value: -daysToMonday, to: calendar.startOfDay(for: date)) ?? date
    }

    // MARK: Data loading

    private func loadEvents() async {
        loadErrorMessage = nil
        let (loadStart, loadEnd) = loadRange

        switch settings.calendarSource {
        case .device:
            if !deviceService.hasFullAccess, !deviceService.isDenied {
                _ = try? await deviceService.requestAccess()
            }
            deviceDenied = deviceService.isDenied
            guard deviceService.hasFullAccess else { events = []; return }
            deviceCalendars = deviceService.calendars()
            events = deviceService.events(from: loadStart, to: loadEnd, calendarIDs: settings.enabledCalendarIDs)

        case .google:
            guard !settings.googleClientID.isEmpty, googleAuth.isSignedIn else { events = []; return }
            let service = googleService ?? GoogleCalendarService(auth: googleAuth)
            googleService = service
            do {
                events = try await service.events(from: loadStart, to: loadEnd, maxResults: 250)
            } catch {
                events = []
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    private var loadRange: (start: Date, end: Date) {
        switch viewMode {
        case .day:
            return (anchorDate, calendar.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate)
        case .week:
            return (anchorDate, calendar.date(byAdding: .day, value: 7, to: anchorDate) ?? anchorDate)
        case .month:
            return (anchorDate, calendar.date(byAdding: .month, value: 1, to: anchorDate) ?? anchorDate)
        }
    }

    // MARK: Status banner

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
            // Title — mode-aware with inline WEEK badge
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headerTitle)
                        .font(.system(size: 23, weight: .bold))
                        .kerning(-0.2)
                        .foregroundStyle(Theme.Palette.textPrimary)

                    if viewMode == .week {
                        Text("WEEK \(calendar.component(.weekOfYear, from: anchorDate))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                }

                if viewMode == .day {
                    Text(daySubtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }

            Spacer()

            if settings.calendarSource == .device, !deviceCalendars.isEmpty {
                calendarFilterMenu
            }

            // Period navigation ‹ Today ›
            HStack(spacing: 0) {
                Button(action: previousPeriod) {
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

                Button(action: nextPeriod) {
                    Text("›")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Palette.border, lineWidth: 1))

            // Day / Week / Month toggle
            HStack(spacing: 2) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { viewMode = mode }
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

            if settings.calendarSource == .device, deviceService.hasFullAccess {
                Button { showingNewEvent = true } label: {
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

    private var headerTitle: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        switch viewMode {
        case .day:
            return df.string(from: anchorDate)
        case .week:
            // Use Wednesday so the displayed month is stable at week boundaries.
            let midWeek = calendar.date(byAdding: .day, value: 2, to: anchorDate) ?? anchorDate
            return df.string(from: midWeek)
        case .month:
            return df.string(from: anchorDate)
        }
    }

    private var daySubtitle: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        return df.string(from: anchorDate)
    }

    private var calendarFilterMenu: some View {
        Menu {
            ForEach(deviceCalendars) { cal in
                Button { toggleCalendar(cal.id) } label: {
                    if isCalendarEnabled(cal.id) {
                        Label("\(cal.title) — \(cal.sourceName)", systemImage: "checkmark")
                    } else {
                        Text("\(cal.title) — \(cal.sourceName)")
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
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Palette.border, lineWidth: 1))
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
        if enabled.contains(id) { enabled.remove(id) } else { enabled.insert(id) }
        settings.enabledCalendarIDs = enabled.count == deviceCalendars.count ? nil : enabled
    }

    // MARK: Navigation

    private func previousPeriod() {
        switch viewMode {
        case .day:   anchorDate = calendar.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate
        case .week:  anchorDate = calendar.date(byAdding: .weekOfYear, value: -1, to: anchorDate) ?? anchorDate
        case .month: anchorDate = calendar.date(byAdding: .month, value: -1, to: anchorDate) ?? anchorDate
        }
    }

    private func nextPeriod() {
        switch viewMode {
        case .day:   anchorDate = calendar.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate
        case .week:  anchorDate = calendar.date(byAdding: .weekOfYear, value: 1, to: anchorDate) ?? anchorDate
        case .month: anchorDate = calendar.date(byAdding: .month, value: 1, to: anchorDate) ?? anchorDate
        }
    }

    private func goToToday() {
        switch viewMode {
        case .day:   anchorDate = calendar.startOfDay(for: .now)
        case .week:  anchorDate = mondayOfWeek(containing: .now)
        case .month: anchorDate = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        }
    }

    // MARK: Display days (Day = 1 col, Week = Mon–Fri)

    private var displayDays: [Date] {
        switch viewMode {
        case .day:
            return [calendar.startOfDay(for: anchorDate)]
        case .week:
            let monday = mondayOfWeek(containing: anchorDate)
            return (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        case .month:
            return []
        }
    }

    // MARK: Time grid (Day + Week)

    private var timeGrid: some View {
        VStack(spacing: 0) {
            // Day-column headers
            HStack(spacing: 0) {
                Rectangle().fill(Color.clear).frame(width: timeColumnWidth)
                ForEach(displayDays, id: \.self) { day in
                    dayHeader(day).frame(maxWidth: .infinity)
                }
            }
            .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .bottom)

            // Scrollable time rows + event pills
            ScrollView {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(workingHours, id: \.self) { hour in
                                hourRow(hour, columnCount: displayDays.count)
                            }
                        }
                        ForEach(placedEvents(gridWidth: geo.size.width)) { placed in
                            eventPill(placed)
                                .position(x: placed.x + placed.width / 2, y: placed.top + placed.height / 2)
                        }
                        if displayDays.contains(where: { calendar.isDateInToday($0) }) {
                            currentTimeIndicator
                        }
                    }
                }
                .frame(height: hourHeight * CGFloat(workingHours.count))
            }
            .overlay(Rectangle().fill(Theme.Palette.border).frame(height: 1), alignment: .top)
        }
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Palette.border, lineWidth: 1))
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

    private func hourRow(_ hour: Int, columnCount: Int) -> some View {
        HStack(spacing: 0) {
            Text(String(format: "%02d:00", hour))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 8)

            HStack(spacing: 0) {
                ForEach(0..<columnCount, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(maxWidth: .infinity)
                        .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .top)
                        .overlay(Rectangle().fill(Theme.Palette.hairline).frame(width: 1), alignment: .leading)
                }
            }
        }
        .frame(height: hourHeight)
    }

    private var currentTimeIndicator: some View {
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let startHour = workingHours.first ?? 8
        let yOffset = (CGFloat(hour - startHour) + CGFloat(minute) / 60.0) * hourHeight

        return HStack(spacing: 0) {
            Circle().fill(Theme.Palette.brass).frame(width: 9, height: 9)
            Rectangle().fill(Theme.Palette.brass).frame(height: 2).frame(maxWidth: .infinity)
        }
        .padding(.leading, timeColumnWidth - 4)
        .offset(y: yOffset - 4)
    }

    // MARK: Event placement

    private func placedEvents(gridWidth: CGFloat) -> [PlacedEvent] {
        let columnCount = displayDays.count
        let columnWidth = (gridWidth - timeColumnWidth) / CGFloat(columnCount)
        guard columnWidth > 0, let referenceDate = displayDays.first else { return [] }
        let startHour = CGFloat(workingHours.first ?? 8)
        let gridHeight = hourHeight * CGFloat(workingHours.count)

        return events.compactMap { event in
            guard !event.isAllDay else { return nil }
            let dayStart = calendar.startOfDay(for: event.start)
            guard let dayIndex = calendar.dateComponents([.day], from: referenceDate, to: dayStart).day,
                  (0..<columnCount).contains(dayIndex) else { return nil }

            let startFraction = CGFloat(calendar.component(.hour, from: event.start))
                + CGFloat(calendar.component(.minute, from: event.start)) / 60 - startHour
            let duration = CGFloat(event.end.timeIntervalSince(event.start)) / 3600

            var top = startFraction * hourHeight
            var height = max(duration * hourHeight, 22)
            if top < 0 { height += top; top = 0 }
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
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.Palette.focusBorder, lineWidth: isFocus ? 1 : 0))
    }

    // MARK: Month Grid

    private var monthGrid: some View {
        VStack(spacing: 0) {
            // Weekday header row
            HStack(spacing: 0) {
                ForEach(localizedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .overlay(Rectangle().fill(Theme.Palette.hairline).frame(height: 1), alignment: .bottom)

            // Day cells in rows of 7
            let cells = monthCells
            let rowCount = cells.count / 7
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        monthDayCell(cells[row * 7 + col])
                    }
                }
                if row < rowCount - 1 {
                    Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                }
            }
        }
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.Palette.border, lineWidth: 1))
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func monthDayCell(_ cell: MonthCell) -> some View {
        let isToday = calendar.isDateInToday(cell.date)
        let dayNum = calendar.component(.day, from: cell.date)
        let dayEvents = events.filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: cell.date) }

        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if isToday {
                    Circle().fill(Theme.Palette.brass).frame(width: 22, height: 22)
                }
                Text("\(dayNum)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(
                        isToday ? Theme.Palette.navy :
                        cell.isCurrentMonth ? Theme.Palette.textPrimary : Theme.Palette.textMuted
                    )
            }

            if !dayEvents.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(dayEvents.prefix(3)), id: \.id) { event in
                        Circle()
                            .fill(Color(hex: event.colorHex.isEmpty ? "#5B8DB8" : event.colorHex))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .background(isToday ? Theme.Palette.focusBg.opacity(0.3) : Color.clear)
        .overlay(Rectangle().fill(Theme.Palette.hairline).frame(width: 1), alignment: .leading)
    }

    private var localizedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first]).map { $0.uppercased() }
    }

    private var monthCells: [MonthCell] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: anchorDate),
              let firstWeekday = calendar.dateComponents([.weekday], from: anchorDate).weekday
        else { return [] }

        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalDays = monthRange.count
        let totalCells = ((offset + totalDays + 6) / 7) * 7

        return (0..<totalCells).compactMap { index in
            let dayOffset = index - offset
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: anchorDate) else { return nil }
            return MonthCell(date: date, isCurrentMonth: dayOffset >= 0 && dayOffset < totalDays)
        }
    }

    // MARK: Shared helpers

    private var workingHours: [Int] { Array(8...18) }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    // MARK: Ask bar

    private var askBar: some View {
        HStack(spacing: 12) {
            CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.surface)
                .frame(width: 15, height: 15)

            Text("Ask Helm — \u{201C}find 90 min for the deck before Thu\u{201D}, \u{201C}move dentist to next week\u{201D}\u{2026}")
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
        .background(Theme.Palette.navy, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
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
                ForEach(calendars) { cal in
                    Text("\(cal.title) — \(cal.sourceName)").tag(String?.some(cal.id))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Palette.danger)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
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
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }
}

private struct PlacedEvent: Identifiable {
    let id: String
    let event: CalendarEvent
    let x: CGFloat
    let top: CGFloat
    let height: CGFloat
    let width: CGFloat
}

private struct MonthCell {
    let date: Date
    let isCurrentMonth: Bool
}

#Preview {
    NavigationStack {
        CalendarView()
            .environment(AppSettings())
            .modelContainer(PersistenceController.makeInMemoryContainer())
    }
}
