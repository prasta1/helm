import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Helm Tasks view — a unified ledger of todos from every source.
/// Merges Helm's own tasks (SwiftData) with live Apple Reminders (EventKit),
/// grouped by due-date period, with a sidebar of real lists.
struct BridgeTasksView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Query(sort: \Activity.date, order: .forward) private var activities: [Activity]
    @Query private var githubOverrides: [GitHubItemOverride]

    @State private var service = RemindersService()
    @State private var reminders: [ReminderItem] = []
    @State private var doneReminders: [ReminderItem] = []
    @State private var reminderLists: [ReminderList] = []
    @State private var remindersDenied = false
    @State private var selectedPeriod: TaskPeriod = .today
    @State private var newTaskText = ""
    @State private var saveErrorMessage: String?
    @State private var githubService = GitHubService()
    @State private var githubItems: [GitHubItem] = []
    @State private var githubFetchError = false
    @State private var dueDateItemID: String?
    @State private var pendingDueDate = Date.now

    var body: some View {
        HStack(spacing: 0) {
            listsSidebar
            mainContent
        }
        .background(Theme.Palette.canvas)
        .navigationTitle("Tasks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await connectAndLoad() }
        .onReceive(NotificationCenter.default.publisher(for: RemindersService.changeNotification)) { _ in
            Task { await reload() }
        }
        .alert("Couldn't save", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .task(id: settings.trackedGitHubRepos) { await fetchGitHubItems() }
        .sheet(isPresented: Binding(
            get: { dueDateItemID != nil },
            set: { if !$0 { dueDateItemID = nil } }
        )) { githubDueDateSheet }
    }

    // MARK: Reminders loading

    private func connectAndLoad() async {
        if !service.hasFullAccess, !service.isDenied {
            _ = try? await service.requestAccess()
        }
        remindersDenied = service.isDenied
        await reload()
    }

    private func reload() async {
        guard service.hasFullAccess else { return }
        reminderLists = service.lists()
        reminders = await service.incompleteReminders()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        doneReminders = await service.completedReminders(since: weekAgo)
    }

    private func fetchGitHubItems() async {
        guard !settings.trackedGitHubRepos.isEmpty else { githubItems = []; return }
        let result = await githubService.fetchItems(for: settings.trackedGitHubRepos)
        githubItems = result.items
        githubFetchError = !result.errors.isEmpty
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
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

            ScrollView {
                VStack(spacing: 0) {
                    listSectionHeader("HELM")
                    ForEach(helmLists, id: \.name) { list in
                        listRow(name: list.name, count: list.count, color: Theme.Palette.brassDim)
                    }

                    if !reminderLists.isEmpty {
                        Divider().padding(.vertical, 8)

                        listSectionHeader("APPLE REMINDERS")
                        ForEach(reminderLists) { list in
                            let enabled = isReminderListEnabled(list.id)
                            Button { toggleReminderList(list.id) } label: {
                                listRow(
                                    name: list.title,
                                    count: reminders.filter { $0.listID == list.id }.count,
                                    color: Color(hex: list.colorHex)
                                )
                            }
                            .buttonStyle(.plain)
                            .opacity(enabled ? 1 : 0.38)
                        }
                    }

                    if !settings.trackedGitHubRepos.isEmpty {
                        Divider().padding(.vertical, 8)

                        listSectionHeader("GITHUB")
                        ForEach(settings.trackedGitHubRepos, id: \.self) { repo in
                            githubRepoRow(repo)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer
            HStack(spacing: 8) {
                Circle()
                    .fill(service.hasFullAccess ? Theme.Palette.success : Theme.Palette.textMuted)
                    .frame(width: 6, height: 6)
                Text(service.hasFullAccess ? "Reminders connected" : "Reminders off")
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
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func githubRepoRow(_ repo: String) -> some View {
        let count = openGitHubItems.filter { $0.repoSlug == repo }.count
        return HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: 8)
            Text(repo)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            if githubFetchError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.danger)
            } else {
                Text("\(count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func isReminderListEnabled(_ listID: String) -> Bool {
        guard let enabled = settings.enabledReminderListIDs else { return true }
        return enabled.contains(listID)
    }

    private func toggleReminderList(_ listID: String) {
        var enabled = settings.enabledReminderListIDs ?? Set(reminderLists.map(\.id))
        if enabled.contains(listID) {
            enabled.remove(listID)
        } else {
            enabled.insert(listID)
        }
        settings.enabledReminderListIDs = enabled
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

            if remindersDenied {
                permissionCard
                    .padding(.horizontal, 44)
                    .padding(.bottom, 16)
            }

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
                        taskGroup("DUE TODAY", tasks: tasksDueToday, style: .time)
                        taskGroup("TOMORROW — \(dayLabel(offset: 1))", tasks: tasks(inDayOffsets: 1...1), style: .time)
                        taskGroup("LATER THIS WEEK", tasks: tasks(inDayOffsets: 2...6), style: .date)
                    case .upcoming:
                        taskGroup("THIS WEEK", tasks: tasks(inDayOffsets: 0...6), style: .date)
                        taskGroup("NEXT WEEK", tasks: tasks(inDayOffsets: 7...13), style: .date)
                    case .anytime:
                        taskGroup("NO DUE DATE", tasks: tasksAnytime, style: .none)
                    case .logbook:
                        completedTaskGroup
                    }
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Permission explainer

    private var permissionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.brassDim)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Reminders is switched off")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Helm can show your reminders alongside its own tasks once access is granted.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if let url = privacySettingsURL {
                Button("Open Settings") { openURL(url) }
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
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        #else
        URL(string: UIApplication.openSettingsURLString)
        #endif
    }

    // MARK: Smart input

    private var smartInputBar: some View {
        HStack(spacing: 12) {
            // Destination picker: Helm task or an Apple Reminders list.
            Menu {
                Button {
                    settings.quickAddReminderListID = nil
                } label: {
                    destinationMenuLabel("Helm task", isSelected: settings.quickAddReminderListID == nil)
                }
                ForEach(reminderLists.filter(\.allowsModifications)) { list in
                    Button {
                        settings.quickAddReminderListID = list.id
                    } label: {
                        destinationMenuLabel(
                            "Reminders · \(list.title)",
                            isSelected: settings.quickAddReminderListID == list.id
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("+")
                        .font(.system(size: 15, weight: .bold))
                    Text(quickAddDestinationLabel)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.Palette.brassDim)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            TextField("Jot a task — press ⏎ to add", text: $newTaskText)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .onSubmit(addQuickTask)

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

    @ViewBuilder
    private func destinationMenuLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var quickAddDestinationLabel: String {
        guard let listID = settings.quickAddReminderListID,
              let list = reminderLists.first(where: { $0.id == listID }) else {
            return "HELM"
        }
        return list.title.uppercased()
    }

    private func addQuickTask() {
        let title = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let listID = settings.quickAddReminderListID, service.hasFullAccess {
            do {
                try service.createReminder(title: title, dueDate: nil, listID: listID)
            } catch {
                saveErrorMessage = error.localizedDescription
                return
            }
            Task { await reload() }
        } else {
            modelContext.insert(Activity(kind: .task, title: title, date: .now, source: .manual))
        }
        newTaskText = ""
    }

    // MARK: Period tabs

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

    // MARK: Task groups

    private enum DueStyle {
        case time, date, none
    }

    private func taskGroup(_ title: String, tasks: [TaskItem], style: DueStyle) -> some View {
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
                        taskRow(task: task, isLast: index == tasks.count - 1)
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

    private func taskRow(task: TaskItem, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            // Checkbox — writes back to the owning source.
            Button {
                toggle(task)
            } label: {
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
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13, weight: task.isUrgent ? .semibold : .regular))
                .foregroundStyle(task.isCompleted ? Theme.Palette.textMuted : Theme.Palette.textPrimary)
                .strikethrough(task.isCompleted)
                .lineLimit(1)

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

            if let due = task.dueText {
                Text(due)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(task.isUrgent ? Theme.Palette.danger : Theme.Palette.textSecondary)
                    .fontWeight(task.isUrgent ? .semibold : .regular)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .opacity(task.isCompleted ? 0.45 : 1)
        .overlay(
            !isLast ? Divider().padding(.leading, 47) : nil,
            alignment: .bottom
        )
        .contextMenu {
            if let githubID = task.githubItemID {
                Button("Set Due Date…") {
                    pendingDueDate = githubOverride(for: githubID)?.dueDate ?? .now
                    dueDateItemID = githubID
                }
                if githubOverride(for: githubID)?.dueDate != nil {
                    Button("Clear Due Date") {
                        findOrCreateOverride(for: githubID).dueDate = nil
                    }
                }
                Divider()
                if let item = githubItems.first(where: { $0.id == githubID }) {
                    Button("Open on GitHub") { openURL(item.htmlURL) }
                }
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        if let activityID = task.activityID {
            if let activity = activities.first(where: { $0.id == activityID }) {
                activity.isCompleted.toggle()
            }
        } else if let reminderID = task.reminderID {
            do {
                try service.setCompleted(!task.isCompleted, reminderID: reminderID)
            } catch {
                saveErrorMessage = error.localizedDescription
                return
            }
            Task { await reload() }
        } else if let githubID = task.githubItemID {
            findOrCreateOverride(for: githubID).isLocallyDone = !task.isCompleted
        }
    }

    private var completedTaskGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOGBOOK — LAST 7 DAYS")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.Palette.textMuted)

            let completed = logbookItems
            if completed.isEmpty {
                Text("No completed tasks yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Palette.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(completed.enumerated()), id: \.offset) { index, task in
                        taskRow(task: task, isLast: index == completed.count - 1)
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

    // MARK: - Merged ledger

    /// Open items due today or overdue, plus items completed today (struck through, on top).
    private var tasksDueToday: [TaskItem] {
        let cal = Calendar.current
        let todayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!

        let completedToday = doneReminders
            .filter { $0.completionDate.map(cal.isDateInToday) ?? false }
            .map { makeItem($0, style: .time) }
        + activities
            .filter { $0.kind == .task && $0.isCompleted && cal.isDateInToday($0.date) }
            .map { makeItem($0, style: .time) }

        let open = openHelmTasks
            .filter { $0.date < todayEnd }
            .map { makeItem($0, style: .time) }
        + openReminders
            .filter { $0.dueDate.map { $0 < todayEnd } ?? false }
            .map { makeItem($0, style: .time) }
        + openGitHubItems
            .filter { githubOverride(for: $0.id)?.dueDate.map { $0 < todayEnd } ?? false }
            .map { makeItem($0, style: .time) }

        return completedToday + open.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Open items due within the given day offsets from today (1...1 = tomorrow).
    private func tasks(inDayOffsets offsets: ClosedRange<Int>) -> [TaskItem] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let style: DueStyle = offsets.upperBound <= 1 ? .time : .date

        func offset(of date: Date) -> Int {
            cal.dateComponents([.day], from: todayStart, to: cal.startOfDay(for: date)).day ?? -999
        }

        let items = openHelmTasks
            .filter { offsets.contains(offset(of: $0.date)) }
            .map { makeItem($0, style: style) }
        + openReminders
            .filter { $0.dueDate.map { offsets.contains(offset(of: $0)) } ?? false }
            .map { makeItem($0, style: style) }
        + openGitHubItems
            .filter { githubOverride(for: $0.id)?.dueDate.map { offsets.contains(offset(of: $0)) } ?? false }
            .map { makeItem($0, style: style) }

        return items.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Items with no due date: dateless Reminders and GitHub items without a local due date.
    private var tasksAnytime: [TaskItem] {
        openReminders
            .filter { $0.dueDate == nil }
            .map { makeItem($0, style: .none) }
        + openGitHubItems
            .filter { githubOverride(for: $0.id)?.dueDate == nil }
            .map { makeItem($0, style: .none) }
    }

    private var logbookItems: [TaskItem] {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) ?? .now
        let items = doneReminders.map { makeItem($0, style: .date) }
        + activities
            .filter { $0.kind == .task && $0.isCompleted && $0.date >= weekAgo }
            .map { makeItem($0, style: .date) }
        + githubItems
            .filter { githubOverride(for: $0.id)?.isLocallyDone ?? false }
            .map { makeItem($0, style: .date) }
        return items.sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    private var openHelmTasks: [Activity] {
        activities.filter { $0.kind == .task && !$0.isCompleted }
    }

    private var openReminders: [ReminderItem] {
        reminders.filter {
            !$0.isCompleted && isReminderListEnabled($0.listID)
        }
    }

    private var openGitHubItems: [GitHubItem] {
        githubItems.filter { !(githubOverride(for: $0.id)?.isLocallyDone ?? false) }
    }

    private func githubOverride(for itemID: String) -> GitHubItemOverride? {
        githubOverrides.first { $0.itemID == itemID }
    }

    private func findOrCreateOverride(for itemID: String) -> GitHubItemOverride {
        if let existing = githubOverrides.first(where: { $0.itemID == itemID }) {
            return existing
        }
        let new = GitHubItemOverride(itemID: itemID)
        modelContext.insert(new)
        return new
    }

    // MARK: Item mapping

    private func makeItem(_ activity: Activity, style: DueStyle) -> TaskItem {
        TaskItem(
            title: activity.title.isEmpty ? activity.body : activity.title,
            details: activity.body,
            isCompleted: activity.isCompleted,
            isUrgent: !activity.isCompleted && activity.date < .now,
            hasProgress: false,
            progress: 0,
            sourceText: sourceLabel(for: activity),
            dueText: dueText(for: activity.date, hasTime: true, style: style),
            formattedDue: Formatters.time.string(from: activity.date),
            activityID: activity.id,
            dueDate: activity.date
        )
    }

    private func makeItem(_ reminder: ReminderItem, style: DueStyle) -> TaskItem {
        TaskItem(
            title: reminder.title,
            details: reminder.notes,
            isCompleted: reminder.isCompleted,
            isUrgent: !reminder.isCompleted && reminder.hasDueTime && (reminder.dueDate.map { $0 < .now } ?? false),
            hasProgress: false,
            progress: 0,
            sourceText: "REMINDERS · \(reminder.listName.uppercased())",
            dueText: reminder.dueDate.flatMap { dueText(for: $0, hasTime: reminder.hasDueTime, style: style) },
            formattedDue: reminder.dueDate.map { Formatters.time.string(from: $0) } ?? "",
            reminderID: reminder.id,
            dueDate: reminder.dueDate ?? reminder.completionDate
        )
    }

    private func makeItem(_ item: GitHubItem, style: DueStyle) -> TaskItem {
        let override = githubOverride(for: item.id)
        let due = override?.dueDate
        let prefix = item.isPR ? "PR #\(item.number)" : "#\(item.number)"
        return TaskItem(
            title: "[\(prefix)] \(item.title)",
            details: item.body.isEmpty ? nil : item.body,
            isCompleted: override?.isLocallyDone ?? false,
            isUrgent: due.map { $0 < .now } ?? false,
            hasProgress: false,
            progress: 0,
            sourceText: "GITHUB · \(item.repoSlug)",
            dueText: due.flatMap { dueText(for: $0, hasTime: false, style: style) },
            formattedDue: due.map { Formatters.shortDay.string(from: $0) } ?? "",
            githubItemID: item.id,
            dueDate: due
        )
    }

    // MARK: GitHub date picker sheet

    private var githubDueDateSheet: some View {
        VStack(spacing: 20) {
            Text("Set Due Date")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            DatePicker("Due date", selection: $pendingDueDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.Palette.brass)

            HStack(spacing: 12) {
                Button("Cancel") { dueDateItemID = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.textMuted)
                Spacer()
                Button("Save") {
                    if let id = dueDateItemID {
                        findOrCreateOverride(for: id).dueDate = pendingDueDate
                    }
                    dueDateItemID = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.brassDim)
                .fontWeight(.semibold)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func dueText(for date: Date, hasTime: Bool, style: DueStyle) -> String? {
        switch style {
        case .none:
            return nil
        case .time:
            return hasTime ? Formatters.time.string(from: date) : "all day"
        case .date:
            return Formatters.shortDay.string(from: date).uppercased()
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

    // MARK: Formatting helpers

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM dd"
        return df.string(from: .now).uppercased()
    }

    private func dayLabel(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        return Formatters.shortDay.string(from: date).uppercased()
    }

    private var helmLists: [(name: String, count: Int)] {
        let open = openHelmTasks
        guard !open.isEmpty else { return [("Tasks", 0)] }
        return [("Tasks", open.count)]
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

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
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
