import SwiftUI
import SwiftData

// MARK: - Router

/// Routes to the active calendar source, wrapped in Helm design.
struct CalendarView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HelmWeekCalendarView()
            .navigationTitle("Calendar")
    }
}

// MARK: - Helm Week Calendar

/// A week-view calendar matching the Helm design — Google + Apple events woven
/// into one time grid with color-coded events and a current-time indicator.
private struct HelmWeekCalendarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var currentWeekStart: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
    ) ?? .now
    @State private var viewMode: CalendarViewMode = .week
    @State private var events: [CalendarEvent] = []

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 18)

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
        }
    }

    // MARK: Week Grid

    private var weekGrid: some View {
        VStack(spacing: 0) {
            // Day headers
            HStack(spacing: 0) {
                // Time column spacer
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 56)

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
                ZStack(alignment: .topLeading) {
                    // Hour rows
                    VStack(spacing: 0) {
                        ForEach(workingHours, id: \.self) { hour in
                            hourRow(hour)
                        }
                    }

                    // Events positioned absolutely
                    ForEach(placedEvents, id: \.id) { placed in
                        // columnOffset already includes the time-gutter width.
                        eventPill(placed)
                            .position(
                                x: placed.columnOffset + placed.width / 2,
                                y: placed.topOffset + placed.height / 2
                            )
                    }

                    // Current time indicator
                    if isThisWeek {
                        currentTimeIndicator
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

    private var timeColumnWidth: CGFloat = 56

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

    // MARK: Event pills

    private func eventPill(_ placed: PlacedEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(placed.event.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(placed.event.isFocus ? Theme.Palette.focusText : .white)
                .lineLimit(1)

            if placed.height > 30 {
                Text(placed.event.timeString)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(placed.event.isFocus ? Theme.Palette.focusText.opacity(0.8) : .white.opacity(0.8))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(placed.height, 22))
        .background(placed.event.bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(placed.event.borderColor, lineWidth: placed.event.isFocus ? 1 : 0)
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

    // Sample events for the design visualization
    private var placedEvents: [PlacedEvent] {
        let todayIndex = isThisWeek ? calendar.component(.weekday, from: .now) - 2 : 0 // Mon=0
        let baseColumn = timeColumnWidth + 2
        let columnWidth: CGFloat = 120

        // Build sample events mirroring the design
        return [
            PlacedEvent(
                id: "1",
                event: SampleEvent(title: "Pipeline review", timeString: "10:00",
                                   bgColor: Theme.Palette.info, borderColor: .clear, isFocus: false),
                columnOffset: baseColumn + columnWidth * 0, topOffset: hourHeight * 2 + 8,
                height: 44, width: columnWidth - 8
            ),
            PlacedEvent(
                id: "2",
                event: SampleEvent(title: "Northwind check-in", timeString: "",
                                   bgColor: Theme.Palette.info, borderColor: .clear, isFocus: false),
                columnOffset: baseColumn + columnWidth * 1, topOffset: hourHeight * 1 + 6,
                height: 28, width: columnWidth - 8
            ),
            PlacedEvent(
                id: "3",
                event: SampleEvent(title: "Focus — board deck", timeString: "14:00 · held by Helm",
                                   bgColor: Theme.Palette.focusBg, borderColor: Theme.Palette.focusBorder, isFocus: true),
                columnOffset: baseColumn + columnWidth * 1, topOffset: hourHeight * 6 + 8,
                height: 90, width: columnWidth - 8
            ),
        ]
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
    let event: SampleEvent
    let columnOffset: CGFloat
    let topOffset: CGFloat
    let height: CGFloat
    let width: CGFloat
}

private struct SampleEvent: Identifiable {
    let id = UUID()
    let title: String
    let timeString: String
    let bgColor: Color
    let borderColor: Color
    let isFocus: Bool
}

#Preview {
    NavigationStack {
        CalendarView()
            .environment(AppSettings())
            .modelContainer(PersistenceController.makeInMemoryContainer())
    }
}
