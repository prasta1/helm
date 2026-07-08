import SwiftUI
import SwiftData

/// Helm Tasks view — a unified ledger of todos and reminders from every source.
/// Shows tasks grouped by due date period, with a sidebar of lists.
struct BridgeTasksView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Activity.date, order: .forward) private var activities: [Activity]

    @State private var selectedPeriod: TaskPeriod = .today
    @State private var newTaskText = ""

    var body: some View {
        HStack(spacing: 0) {
            // Lists sidebar
            listsSidebar

            // Main content
            mainContent
        }
        .background(Theme.Palette.canvas)
        .navigationTitle("Tasks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Lists sidebar

    private var listsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LISTS")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Helm lists (grouped by source tag)
            VStack(spacing: 0) {
                listSectionHeader("HELM")
                ForEach(helmLists, id: \.name) { list in
                    listRow(name: list.name, count: list.count, color: Theme.Palette.brassDim)
                }

                Divider().padding(.vertical, 8)

                listSectionHeader("APPLE REMINDERS")
                ForEach(appleLists, id: \.name) { list in
                    listRow(name: list.name, count: list.count, color: Theme.Palette.sidebarDark)
                }

                Divider().padding(.vertical, 8)

                listSectionHeader("GOOGLE TASKS")
                ForEach(googleLists, id: \.name) { list in
                    listRow(name: list.name, count: list.count, color: Theme.Palette.info)
                }
            }

            Spacer()

            // Footer
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.Palette.success)
                    .frame(width: 6, height: 6)
                Text("All lines synced")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(Divider(), alignment: .top)
        }
        .frame(width: 240)
        .background(Theme.Palette.surface)
        .overlay(Divider(), alignment: .trailing)
    }

    private func listSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .kerning(1.4)
            .foregroundStyle(Theme.Palette.sidebarDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
    }

    private func listRow(name: String, count: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    // MARK: Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tasks")
                    .font(.system(size: 25, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text(formattedDate)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 18)

            // Smart input
            smartInputBar
                .padding(.horizontal, 44)
                .padding(.bottom, 20)

            // Period tabs
            periodTabs
                .padding(.horizontal, 44)
                .padding(.bottom, 20)

            // Task groups
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedPeriod {
                    case .today:
                        taskGroup("DUE TODAY", tasks: tasksDueToday, showTime: true)
                        taskGroup("TOMORROW", tasks: tasksDueTomorrow, showTime: false)
                        taskGroup("LATER THIS WEEK", tasks: tasksLaterThisWeek, showTime: false)
                    case .upcoming:
                        taskGroup("THIS WEEK", tasks: tasksUpcoming, showTime: true)
                        taskGroup("NEXT WEEK", tasks: tasksNextWeek, showTime: false)
                    case .anytime:
                        taskGroup("NO DUE DATE", tasks: tasksAnytime, showTime: false)
                    case .logbook:
                        completedTaskGroup
                    }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 24)
            }
        }
    }

    private var smartInputBar: some View {
        HStack(spacing: 12) {
            Text("+")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Palette.brassDim)

            TextField("Jot a task — try “follow up Dana fri 9am #consulting”", text: $newTaskText)
                .font(.system(size: 13))
                .textFieldStyle(.plain)

            Text("\u{23CE}")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.Palette.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.Palette.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private var periodTabs: some View {
        HStack(spacing: 24) {
            ForEach(TaskPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.title)
                        .font(.system(size: 11, weight: selectedPeriod == period ? .bold : .semibold))
                        .kerning(1.4)
                        .foregroundStyle(selectedPeriod == period ? Theme.Palette.textPrimary : Theme.Palette.textMuted)
                        .padding(.bottom, 8)
                        .overlay(
                            Rectangle()
                                .fill(selectedPeriod == period ? Theme.Palette.brass : Color.clear)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Group: due date \u{25BE}")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textMuted)
        }
    }

    private func taskGroup(_ title: String, tasks: [TaskItem], showTime: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)

            if tasks.isEmpty {
                Text("No tasks in this period.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Palette.textMuted)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                        taskRow(task: task, showTime: showTime, isLast: index == tasks.count - 1)
                    }
                }
                .background(
                    Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
            }
        }
    }

    private func taskRow(task: TaskItem, showTime: Bool, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            if task.isCompleted {
                Circle()
                    .fill(Theme.Palette.brassDim)
                    .frame(width: 17, height: 17)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
            } else {
                Circle()
                    .strokeBorder(task.isUrgent ? Theme.Palette.danger : Theme.Palette.textMuted, lineWidth: 1.5)
                    .frame(width: 17, height: 17)
            }

            Text(task.title)
                .font(.system(size: 13, weight: task.isUrgent ? .semibold : .regular))
                .foregroundStyle(task.isCompleted ? Theme.Palette.textMuted : Theme.Palette.textPrimary)
                .strikethrough(task.isCompleted)

            if let tag = task.tag {
                Text(tag)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.tagText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.Palette.tagBg, in: Capsule())
            }

            Spacer()

            if let source = task.sourceText {
                SourceBadge(text: source)
            }

            if showTime, let due = task.dueText {
                Text(due)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(task.isUrgent ? Theme.Palette.danger : Theme.Palette.textSecondary)
                    .fontWeight(task.isUrgent ? .semibold : .regular)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .overlay(
            !isLast ? Divider().padding(.leading, 47) : nil,
            alignment: .bottom
        )
    }

    private var completedTaskGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOGBOOK")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)

            let completed = activities.filter { $0.isCompleted }
            if completed.isEmpty {
                Text("No completed tasks yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Palette.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(completed.prefix(10).enumerated()), id: \.offset) { index, activity in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.Palette.brassDim)
                                .frame(width: 17, height: 17)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                            Text(activity.title.isEmpty ? activity.body : activity.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Palette.textMuted)
                                .strikethrough()
                            Spacer()
                            Text(activity.date, format: .dateTime.month().day())
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.Palette.textMuted)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .overlay(
                            index < min(completed.count, 10) - 1 ? Divider().padding(.leading, 47) : nil,
                            alignment: .bottom
                        )
                    }
                }
                .background(
                    Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                )
                .shadow(color: Theme.Palette.navy.opacity(0.06), radius: 3, x: 0, y: 1)
            }
        }
    }

    // MARK: Data helpers

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM dd"
        return df.string(from: .now).uppercased()
    }

    private var tasksDueToday: [TaskItem] {
        taskItems(for: .today, upcomingDays: 0)
    }

    private var tasksDueTomorrow: [TaskItem] {
        taskItems(for: .upcoming, upcomingDays: 1)
    }

    private var tasksLaterThisWeek: [TaskItem] {
        taskItems(for: .upcoming, upcomingDays: 2...6)
    }

    private var tasksUpcoming: [TaskItem] {
        taskItems(for: .upcoming, upcomingDays: 0...6)
    }

    private var tasksNextWeek: [TaskItem] {
        taskItems(for: .upcoming, upcomingDays: 7...13)
    }

    private var tasksAnytime: [TaskItem] {
        activities
            .filter { $0.kind == .task && !$0.isCompleted }
            .map { makeTaskItem($0) }
    }

    private func taskItems(for period: TaskPeriod, upcomingDays: ClosedRange<Int>) -> [TaskItem] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        return activities
            .filter { activity in
                guard activity.kind == .task, !activity.isCompleted else { return false }
                let daysFromToday = cal.dateComponents([.day], from: todayStart, to: activity.date).day ?? -1
                return upcomingDays.contains(daysFromToday)
            }
            .map { makeTaskItem($0) }
    }

    private func taskItems(for period: TaskPeriod, upcomingDays: Int) -> [TaskItem] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        return activities
            .filter { activity in
                guard activity.kind == .task, !activity.isCompleted else { return false }
                let daysFromToday = cal.dateComponents([.day], from: todayStart, to: activity.date).day ?? -1
                return daysFromToday == upcomingDays
            }
            .map { makeTaskItem($0) }
    }

    private func makeTaskItem(_ activity: Activity) -> TaskItem {
        let sourceMap: [ActivitySource: String] = [
            .googleCalendar: "GOOGLE",
            .deviceCalendar: "APPLE",
            .ai: "HELM",
            .granola: "GRANOLA",
        ]
        return TaskItem(
            title: activity.title.isEmpty ? activity.body : activity.title,
            details: activity.body,
            isCompleted: activity.isCompleted,
            isUrgent: !activity.isCompleted && activity.date < .now,
            hasProgress: false,
            progress: 0,
            sourceText: sourceMap[activity.source],
            dueText: Formatters.time.string(from: activity.date),
            formattedDue: Formatters.time.string(from: activity.date),
            tag: nil
        )
    }

    private var helmLists: [(name: String, count: Int)] {
        let allTasks = activities.filter { $0.kind == .task }
        return [
            ("Consulting", allTasks.filter { $0.body.localizedCaseInsensitiveContains("consult") }.count),
            ("Q3 planning", allTasks.filter { $0.body.localizedCaseInsensitiveContains("q3") || $0.title.localizedCaseInsensitiveContains("q3") }.count),
            ("House hunt", allTasks.filter { $0.body.localizedCaseInsensitiveContains("house") || $0.title.localizedCaseInsensitiveContains("house") }.count),
        ]
    }

    private var appleLists: [(name: String, count: Int)] {
        let appleTasks = activities.filter { $0.source == .deviceCalendar && $0.kind == .task }
        return [
            ("Errands", appleTasks.filter { $0.body.localizedCaseInsensitiveContains("errand") }.count),
            ("Home", appleTasks.filter { $0.body.localizedCaseInsensitiveContains("home") }.count),
        ]
    }

    private var googleLists: [(name: String, count: Int)] {
        let googleTasks = activities.filter { $0.source == .googleCalendar && $0.kind == .task }
        return [
            ("Work", googleTasks.filter { $0.body.localizedCaseInsensitiveContains("work") }.count + 1),
            ("Personal", googleTasks.filter { $0.body.localizedCaseInsensitiveContains("personal") }.count),
        ]
    }
}

// MARK: - Supporting types

enum TaskPeriod: String, CaseIterable {
    case today, upcoming, anytime, logbook

    var title: String {
        switch self {
        case .today: return "TODAY"
        case .upcoming: return "UPCOMING"
        case .anytime: return "ANYTIME"
        case .logbook: return "LOGBOOK"
        }
    }
}

enum Formatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

#Preview {
    NavigationStack {
        BridgeTasksView()
            .environment(AppSettings())
            .modelContainer(PersistenceController.makeInMemoryContainer())
    }
}
