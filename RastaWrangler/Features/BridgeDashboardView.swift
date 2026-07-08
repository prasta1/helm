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

    private let dayStart: Date = Calendar.current.startOfDay(for: .now)
    private let dayEnd: Date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!

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
                    ForEach(Array(courseTicks.enumerated()), id: \.offset) { index, tick in
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
                        courseEventPill(event, stripWidth: w)
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
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func courseEventPill(_ event: CourseEvent, stripWidth: CGFloat) -> some View {
        // Width follows the design's fractions but never overflows the strip.
        let desired = max(event.width * stripWidth, 44)
        let available = stripWidth - event.start * stripWidth
        return Text(event.title)
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
                    .foregroundStyle(.white)
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

                HStack(spacing: 10) {
                    PillButton(title: "Open draft", color: Theme.Palette.brass, textColor: Theme.Palette.navy) {}
                    PillButton(title: "Ask Helm to finish it", color: Color.clear, textColor: Theme.Palette.sidebarActiveText) {}
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.Palette.brass.opacity(0.5), lineWidth: 1)
                        )
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
                ForEach(Array(tasks.prefix(5).enumerated()), id: \.offset) { index, task in
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

            if !tasks.isEmpty {
                let done = tasks.filter { $0.isCompleted }.count
                Text("\(done) of \(tasks.count) done before 10 AM — good wind.")
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
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private func taskRow(_ task: TaskItem, isLast: Bool) -> some View {
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
                Text("THE CHART · CONSULTING")
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
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
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

    /// Tasks due today derived from Activity model.
    private var tasksDueToday: [TaskItem] {
        let todayStart = Calendar.current.startOfDay(for: .now)
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!
        return activities
            .filter { $0.kind == .task && $0.date >= todayStart && $0.date < todayEnd }
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
                    formattedDue: dueTimeFormatter.string(from: activity.date)
                )
            }
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
        guard let consulting = pipelines.first else {
            return [
                StageBar(name: "Discovery", label: "Disc", height: 34, color: Theme.Palette.hairline),
                StageBar(name: "Proposal", label: "Prop", height: 52, color: Theme.Palette.brassDim),
                StageBar(name: "Nego", label: "Nego", height: 40, color: Theme.Palette.info),
                StageBar(name: "Won", label: "Won", height: 20, color: Theme.Palette.success),
            ]
        }
        let stages = consulting.orderedStages
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

    private var courseEvents: [CourseEvent] {
        // Sample course events positioned across the 08:00–18:00 day.
        [
            CourseEvent(title: "standup", start: 0.15, width: 0.06,
                        bgColor: Theme.Palette.hairline, borderColor: Theme.Palette.border,
                        textColor: Theme.Palette.textMuted, isActive: false),
            CourseEvent(title: "Acme call", start: 0.30, width: 0.11,
                        bgColor: Theme.Palette.navy, borderColor: .clear,
                        textColor: Theme.Palette.surface, isActive: true),
            CourseEvent(title: "Sarah — lunch", start: 0.45, width: 0.12,
                        bgColor: Theme.Palette.surface, borderColor: Theme.Palette.textMuted,
                        textColor: Theme.Palette.textSecondary, isActive: false),
            CourseEvent(title: "dentist", start: 0.70, width: 0.08,
                        bgColor: .clear, borderColor: Theme.Palette.border,
                        textColor: Theme.Palette.textSecondary, isActive: false, dashed: true),
            CourseEvent(title: "focus — proposal", start: 0.85, width: 0.14,
                        bgColor: Theme.Palette.focusBg, borderColor: Theme.Palette.focusBorder,
                        textColor: Theme.Palette.focusText, isActive: false),
        ]
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
    let id = UUID()
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
}

#Preview {
    BridgeDashboardView(selection: .constant(.bridge))
        .environment(AppSettings())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
