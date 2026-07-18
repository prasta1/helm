import SwiftUI
import SwiftData

/// The Bridge — the main Helm dashboard showing the day's course, your heading,
/// on-deck tasks, and the pipeline chart. This is the primary landing screen.
struct BridgeDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    /// Bound to RootView's sidebar selection so the Ask bar can navigate.
    @Binding var selection: SidebarItem?

    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]

    @State private var calendarService = EventKitCalendarService()
    @State private var remindersService = RemindersService()
    @State private var todayEvents: [CalendarEvent] = []
    @State private var openReminders: [ReminderItem] = []
    @State private var remindersDoneToday = 0

    // Computed (not stored) so "today" stays correct if the window sits open
    // across midnight — a stored `let` would freeze yesterday's boundaries.
    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                header

                // Course strip (timeline)
                courseStrip
                    .padding(.top, 24)

                // Three panels
                threePanelGrid
                    .padding(.top, 18)

                // Ask bar
                askBar
                    .padding(.top, 18)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 44)
        }
        .background(Theme.Palette.canvas)
        .navigationTitle("The Bridge")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadLiveData() }
        .onReceive(NotificationCenter.default.publisher(for: EventKitCalendarService.changeNotification)) { _ in
            Task { await loadLiveData() }
        }
    }

    // MARK: - Live data (EventKit)

    /// The Bridge is the landing screen, so this is where the app first asks
    /// for Calendar & Reminders access — its whole purpose is showing the day.
    private func loadLiveData() async {
        if !calendarService.hasFullAccess, !calendarService.isDenied {
            _ = try? await calendarService.requestAccess()
        }
        if !remindersService.hasFullAccess, !remindersService.isDenied {
            _ = try? await remindersService.requestAccess()
        }

        if calendarService.hasFullAccess {
            todayEvents = calendarService.events(from: dayStart, to: dayEnd)
        }
        if remindersService.hasFullAccess {
            openReminders = await remindersService.incompleteReminders()
            remindersDoneToday = await remindersService.completedReminders(since: dayStart).count
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("The Bridge")
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(formattedSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text("LOCAL")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.Palette.textMuted)
                Text(formattedTime)
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }

    private var formattedSubtitle: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        let dateStr = df.string(from: .now)

        // Count deadlines and events today
        let deadlines = tasksDueToday
        let deadlineCount = deadlines.count

        if deadlineCount > 0 {
            let topDeadline = deadlines.first?.title ?? ""
            return "\(dateStr) · steady as she goes — \(topDeadline) due today."
        }
        return "\(dateStr) · steady as she goes."
    }

    private var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: .now)
    }

    // MARK: - Course Strip

    private var courseStrip: some View {
        VStack(spacing: 14) {
            HStack {
                Text("TODAY'S COURSE")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Palette.textMuted)
                Spacer()
                Text(formattedDayRange)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            // Timeline bar — everything is positioned as a fraction of the
            // available width, so it scales with the window.
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // Base track line
                    Rectangle()
                        .fill(Theme.Palette.border)
                        .frame(width: w, height: 2)
                        .offset(y: 38)

                    // Tick marks + hour labels at 08/10/12/14/16/18
                    ForEach(Array(courseTicks.enumerated()), id: \.element) { index, tick in
                        let f = CGFloat(index) / CGFloat(courseTicks.count - 1)
                        Rectangle()
                            .fill(Theme.Palette.border)
                            .frame(width: 1, height: 14)
                            .offset(x: min(f * w, w - 1), y: 32)
                        Text(tick)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textMuted)
                            .fixedSize()
                            .offset(x: min(f * w, w - 32), y: 50)
                    }

                    // Event pills, positioned by time across the strip
                    ForEach(courseEvents) { event in
                        CourseEventPillButton(event: event, stripWidth: w)
                            .offset(x: event.start * w, y: 12)
                    }

                    // "Now" needle — only shown during the 08:00–18:00 window
                    if let f = nowFraction {
                        Rectangle()
                            .fill(Theme.Palette.brass)
                            .frame(width: 2, height: 48)
                            .offset(x: f * w - 1, y: 2)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.Palette.brass)
                            .offset(x: f * w - 5, y: -3)
                    }
                }
            }
            .frame(height: 64)
        }
        .padding(22)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.cardShadow, radius: 3, x: 0, y: 1)
    }


    private var formattedDayRange: String {
        "08:00 — 18:00"
    }

    private var courseTicks: [String] {
        ["08:00", "10:00", "12:00", "14:00", "16:00", "18:00"]
    }

    /// Current time as a fraction of the 08:00–18:00 day, or nil if outside it.
    private var nowFraction: CGFloat? {
        let cal = Calendar.current
        let hour = CGFloat(cal.component(.hour, from: .now))
        let minute = CGFloat(cal.component(.minute, from: .now))
        let minutes = (hour - 8) * 60 + minute
        let dayMinutes: CGFloat = 10 * 60 // 08:00 to 18:00
        guard minutes >= 0, minutes <= dayMinutes else { return nil }
        return minutes / dayMinutes
    }

    // MARK: - Three-panel grid

    private var threePanelGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 18),
            GridItem(.flexible(), spacing: 18),
            GridItem(.flexible(), spacing: 18),
        ], spacing: 18) {
            // HEADING panel
            headingPanel

            // ON DECK panel
            onDeckPanel

            // CHART panel
            chartPanel
        }
    }

    // MARK: Heading panel (navy card)

    private var headingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HEADING")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Palette.sidebarMuted)
                Spacer()
                if let top = topPriorityDeadline {
                    Text(top.formattedDue)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.Palette.brass)
                }
            }

            if let top = topPriorityDeadline {
                Text(top.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Palette.onNavy)
                    .padding(.top, 14)
                    .lineLimit(3)

                if let details = top.details {
                    Text(details)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.Palette.sidebarMuted)
                        .padding(.top, 8)
                        .lineLimit(3)
                }

                // Progress
                if top.hasProgress {
                    ProgressBar(progress: top.progress, color: Theme.Palette.brass, trackColor: Color.white.opacity(0.12))
                        .padding(.top, 16)
                }

                Spacer(minLength: 0)

                PillButton(title: "Ask Helm to finish it", color: Theme.Palette.brass, textColor: Theme.Palette.navy) {
                    selection = .assistant
                }
                .padding(.top, 18)
            } else {
                Text("All clear — no pressing deadlines today.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.sidebarMuted)
                    .padding(.top, 14)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Palette.navy,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    // MARK: On Deck panel

    private var onDeckPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ON DECK")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)
                .padding(.bottom, 14)

            let tasks = tasksDueToday
            if tasks.isEmpty {
                Text("No tasks due today.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Palette.textMuted)
                Spacer()
            } else {
                ForEach(Array(tasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                    taskRow(task, isLast: index == min(tasks.count - 1, 4))
                }
                if tasks.count > 5 {
                    Text("+\(tasks.count - 5) more")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Palette.brassDim)
                        .padding(.top, 8)
                }
            }

            Spacer(minLength: 0)

            if !tasks.isEmpty || remindersDoneToday > 0 {
                let done = tasks.filter(\.isCompleted).count + remindersDoneToday
                let total = tasks.count + remindersDoneToday
                Text("\(done) of \(total) done today\(done > 0 ? " — good wind." : ".")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Palette.textMuted)
                    .padding(.top, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.cardShadow, radius: 3, x: 0, y: 1)
    }

    private func taskRow(_ task: TaskItem, isLast: Bool) -> some View {
        // A Button (not a bare HStack) so the row is clickable, keyboard
        // focusable, and read as interactive by VoiceOver.
        Button {
            selection = .tasks
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .strokeBorder(task.isUrgent ? Theme.Palette.brassDim : Theme.Palette.textMuted, lineWidth: 1.5)
                    .frame(width: 16, height: 16)

                Text(task.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                if let sourceText = task.sourceText {
                    SourceBadge(text: sourceText, color: Theme.Palette.textMuted)
                }

                if let dueText = task.dueText {
                    Text(dueText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Tasks: \(task.title)")
        .overlay(
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: Chart panel

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THE CHART · \(pipelines.first?.name.uppercased() ?? "PIPELINE")")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.6)
                    .foregroundStyle(Theme.Palette.textMuted)
                Spacer()
                Text(formattedTotalPipeline)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(.bottom, 14)

            // Bar chart
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(stageBars, id: \.name) { bar in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bar.color)
                            .frame(height: bar.height)
                        Text(bar.label)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                }
            }
            .frame(height: 64)

            // Deals needing attention
            VStack(spacing: 9) {
                ForEach(dealsNeedingAttention.prefix(3), id: \.title) { deal in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(deal.indicatorColor)
                            .frame(width: 6, height: 6)
                        Text(deal.title)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(deal.statusText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(deal.indicatorColor)
                    }
                }
                if dealsNeedingAttention.isEmpty {
                    Text("No open deals needing attention.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
            .padding(.top, 16)
            .overlay(
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1),
                alignment: .top
            )

            Spacer(minLength: 0)

            Text("Weighted, both charts · updated \(formattedTime)")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.Palette.textMuted)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.cardShadow, radius: 3, x: 0, y: 1)
    }

    // MARK: Ask bar

    private var askBar: some View {
        Button {
            selection = .assistant
        } label: {
            HStack(spacing: 12) {
                CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.surface)
                    .frame(width: 15, height: 15)

                Text("Ask Helm — \"draft the Meridian email\", \"what's slipping?\", \"plot tomorrow\"…")
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
            .padding(.vertical, 12)
            .background(
                Theme.Palette.navy,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data sources (bridging model to design)

    /// Tasks due today (or overdue): Helm task Activities merged with Apple Reminders.
    private var tasksDueToday: [TaskItem] {
        let helmTasks = activities
            .filter { $0.kind == .task && $0.date >= dayStart && $0.date < dayEnd }
            .map { activity in
                let isUrgent = !activity.isCompleted && activity.date < .now
                return TaskItem(
                    title: activity.title.isEmpty ? activity.body : activity.title,
                    details: activity.body,
                    isCompleted: activity.isCompleted,
                    isUrgent: isUrgent,
                    hasProgress: false,
                    progress: activity.isCompleted ? 1 : 0,
                    sourceText: sourceLabel(for: activity),
                    dueText: activity.isCompleted ? nil : dueTimeFormatter.string(from: activity.date),
                    formattedDue: dueTimeFormatter.string(from: activity.date),
                    dueDate: activity.date
                )
            }

        let reminderTasks = openReminders
            .filter { $0.dueDate.map { $0 < dayEnd } ?? false }
            .map { reminder in
                TaskItem(
                    title: reminder.title,
                    details: reminder.notes,
                    isCompleted: false,
                    isUrgent: reminder.hasDueTime && (reminder.dueDate.map { $0 < .now } ?? false),
                    hasProgress: false,
                    progress: 0,
                    sourceText: "REMINDERS · \(reminder.listName.uppercased())",
                    dueText: reminder.hasDueTime ? reminder.dueDate.map { dueTimeFormatter.string(from: $0) } : nil,
                    formattedDue: reminder.dueDate.map { dueTimeFormatter.string(from: $0) } ?? "",
                    reminderID: reminder.id,
                    dueDate: reminder.dueDate
                )
            }

        return (helmTasks + reminderTasks)
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var topPriorityDeadline: TaskItem? {
        let urgent = tasksDueToday.filter { !$0.isCompleted && $0.isUrgent }
        return urgent.first ?? tasksDueToday.first { !$0.isCompleted }
    }

    private var dealsNeedingAttention: [DealAlert] {
        pipelines.flatMap { pipeline in
            pipeline.deals
                .filter { $0.status == .open }
                .map { deal in
                    let daysSinceTouch = Calendar.current.dateComponents(
                        [.day],
                        from: deal.updatedAt,
                        to: .now
                    ).day ?? 0

                    let isUrgent = daysSinceTouch >= 7
                    return DealAlert(
                        title: "\(deal.title) — \(pipeline.name)",
                        statusText: isUrgent ? "\(daysSinceTouch)d" : "ok",
                        indicatorColor: isUrgent ? Theme.Palette.warning : Theme.Palette.textMuted
                    )
                }
        }
        .sorted { $0.statusText != "ok" && $1.statusText == "ok" }
    }

    private var stageBars: [StageBar] {
        guard let pipeline = pipelines.first else {
            return [
                StageBar(name: "Discovery", label: "Disc", height: 34, color: Theme.Palette.hairline),
                StageBar(name: "Proposal", label: "Prop", height: 52, color: Theme.Palette.brassDim),
                StageBar(name: "Nego", label: "Nego", height: 40, color: Theme.Palette.info),
                StageBar(name: "Won", label: "Won", height: 20, color: Theme.Palette.success),
            ]
        }
        let stages = pipeline.orderedStages
        if stages.isEmpty { return [] }

        let maxDeals = max(stages.map { $0.deals.count }.max() ?? 1, 1)
        return stages.map { stage in
            let count = stage.deals.count
            let heightFraction = CGFloat(count) / CGFloat(maxDeals) * 52
            return StageBar(
                name: stage.name,
                label: "\(stage.name.prefix(4))",
                height: max(heightFraction, 12),
                color: Color(hex: stage.colorHex)
            )
        }
    }

    private var formattedTotalPipeline: String {
        let total = pipelines.reduce(0.0) { $0 + $1.openValue }
        return total.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// Today's real calendar events plotted onto the 08:00–18:00 strip.
    private var courseEvents: [CourseEvent] {
        let windowStart: CGFloat = 8 * 60
        let windowMinutes: CGFloat = 10 * 60
        let now = Date()
        let cal = Calendar.current

        return todayEvents.compactMap { event in
            guard !event.isAllDay else { return nil }

            let startMinutes = CGFloat(cal.component(.hour, from: event.start)) * 60
                + CGFloat(cal.component(.minute, from: event.start)) - windowStart
            // Calendar-based minutes stay correct for events spanning a DST change.
            let durationMinutes = CGFloat(cal.dateComponents([.minute], from: event.start, to: event.end).minute ?? 0)

            let start = startMinutes / windowMinutes
            let width = durationMinutes / windowMinutes
            // Skip events entirely outside the strip.
            guard start + width > 0, start < 1 else { return nil }

            let isActive = event.start <= now && now < event.end
            let isFocus = event.title.localizedCaseInsensitiveContains("focus")

            let bg: Color
            let border: Color
            let text: Color
            if isActive {
                bg = Theme.Palette.navy; border = .clear; text = Theme.Palette.onNavy
            } else if isFocus {
                bg = Theme.Palette.focusBg; border = Theme.Palette.focusBorder; text = Theme.Palette.focusText
            } else {
                bg = Theme.Palette.surface; border = Theme.Palette.border; text = Theme.Palette.textSecondary
            }

            return CourseEvent(
                title: event.title,
                start: max(start, 0),
                width: min(max(width, 0.04), 1 - max(start, 0)),
                bgColor: bg,
                borderColor: border,
                textColor: text,
                isActive: isActive,
                sourceEvent: event
            )
        }
    }

    private func sourceLabel(for activity: Activity) -> String? {
        switch activity.source {
        case .googleCalendar: return "GOOGLE"
        case .deviceCalendar: return "APPLE"
        case .ai: return "HELM"
        case .granola: return "GRANOLA"
        case .manual: return nil
        }
    }

    private let dueTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Model types for the dashboard

struct TaskItem: Identifiable {
    /// Stable identity from the backing record. TaskItems are rebuilt on every
    /// render, so a stored `UUID()` here would give SwiftUI a brand-new
    /// identity each time and defeat row diffing/animation.
    var id: String {
        activityID?.uuidString ?? reminderID ?? githubItemID ?? title
    }
    let title: String
    let details: String?
    let isCompleted: Bool
    let isUrgent: Bool
    let hasProgress: Bool
    let progress: Double
    let sourceText: String?
    let dueText: String?
    let formattedDue: String
    var tag: String? = nil
    /// Backing SwiftData Activity, when this row is a Helm task.
    var activityID: UUID? = nil
    /// Backing EKReminder identifier, when this row is an Apple Reminder.
    var reminderID: String? = nil
    /// Backing GitHub item ID ("owner/repo#number"), when this row is a GitHub issue or PR.
    var githubItemID: String? = nil
    /// Due date used for grouping (nil = no due date).
    var dueDate: Date? = nil
}

struct DealAlert: Identifiable {
    let id = UUID()
    let title: String
    let statusText: String
    let indicatorColor: Color
}

struct StageBar: Identifiable {
    let id = UUID()
    let name: String
    let label: String
    let height: CGFloat
    let color: Color
}

struct CourseEvent: Identifiable {
    let id = UUID()
    let title: String
    /// Where the event starts, as a fraction (0...1) of the 08:00–18:00 day.
    let start: CGFloat
    /// The pill's width, as a fraction of the strip width.
    let width: CGFloat
    let bgColor: Color
    let borderColor: Color
    let textColor: Color
    let isActive: Bool
    var dashed: Bool = false
    /// The original calendar event, used to populate the detail popover.
    let sourceEvent: CalendarEvent
}

// MARK: - Course event pill button

/// A tappable pill that shows a popover anchored to itself when clicked.
private struct CourseEventPillButton: View {
    let event: CourseEvent
    let stripWidth: CGFloat
    @State private var showingDetail = false

    var body: some View {
        let desired = max(event.width * stripWidth, 44)
        let available = stripWidth - event.start * stripWidth
        Button { showingDetail = true } label: {
            Text(event.title)
                .font(.system(size: 10, weight: event.isActive ? .semibold : .regular))
                .foregroundStyle(event.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(width: min(desired, available), height: 20, alignment: .leading)
                .background(event.bgColor, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            event.borderColor,
                            style: StrokeStyle(
                                lineWidth: event.isActive ? 0 : 1,
                                dash: event.dashed ? [3, 2] : []
                            )
                        )
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            CourseEventDetailView(event: event.sourceEvent)
        }
    }
}

// MARK: - Course event detail popover

private struct CourseEventDetailView: View {
    let event: CalendarEvent

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            Text(event.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                // Time range
                Label(event.timeRangeText, systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)

                // Location
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "location")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                }

                // Organizer
                if !event.organizerEmail.isEmpty {
                    Label(event.organizerEmail, systemImage: "person")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }

            // Attendees
            if !event.attendees.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ATTENDEES")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Theme.Palette.textMuted)
                    ForEach(event.attendees.prefix(6), id: \.self) { attendee in
                        Text(attendee)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    if event.attendees.count > 6 {
                        Text("+\(event.attendees.count - 6) more")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 220, maxWidth: 320)
    }
}

#Preview {
    BridgeDashboardView(selection: .constant(.bridge))
        .environment(AppSettings())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
