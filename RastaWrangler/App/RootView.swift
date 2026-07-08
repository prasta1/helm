import SwiftUI
import SwiftData

/// The items shown in the sidebar. Pipelines are dynamic; the rest are fixed.
enum SidebarItem: Hashable {
    case bridge
    case tasks
    case calendar
    case pipeline(UUID)
    case contacts
    case assistant
    case settings
}

/// Root navigation: a custom navy sidebar on the left + adaptive detail content.
/// On Mac this is a NavigationSplitView; on iPhone it collapses to a stack.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]

    @State private var selection: SidebarItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingNewPipeline = false

    private let syncTime = "10:21 AM"

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            helmSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 260)
        } detail: {
            detail
        }
        .task {
            if selection == nil {
                selection = .bridge
            }
        }
        .sheet(isPresented: $showingNewPipeline) {
            PipelineEditorView(pipeline: nil)
        }
    }

    // MARK: - Helm Navy Sidebar

    private var helmSidebar: some View {
        List(selection: $selection) {
            // Brand section
            Section {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        CompassRose(accentColor: Theme.Palette.brass, bodyColor: Theme.Palette.surface)
                            .frame(width: 22, height: 22)
                        Text("HELM")
                            .font(.system(size: 14, weight: .bold, design: .default))
                            .kerning(3.5)
                            .foregroundStyle(Theme.Palette.surface)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 22)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // THE BRIDGE nav items
            Section("THE BRIDGE") {
                sidebarNavLabel("The Bridge", icon: "sailboat", badge: nil,
                                isActive: selection == .bridge || selection == nil)
                    .tag(SidebarItem.bridge)

                sidebarNavLabel("Tasks", icon: "checklist", badge: nil,
                                isActive: selection == .tasks)
                    .tag(SidebarItem.tasks)

                sidebarNavLabel("Calendar", icon: "calendar", badge: nil,
                                isActive: selection == .calendar)
                    .tag(SidebarItem.calendar)

                sidebarNavLabel("Pipelines", icon: "chart.bar", badge: "\(pipelineDealCount)",
                                isActive: isPipelineSelected)
                    .tag(SidebarItem.pipelinesHint)

                sidebarNavLabel("Contacts", icon: "person.2", badge: nil,
                                isActive: selection == .contacts)
                    .tag(SidebarItem.contacts)

                sidebarNavLabel("Ask Helm", icon: "sparkle", badge: nil,
                                isActive: selection == .assistant)
                    .tag(SidebarItem.assistant)
            }

            // CHARTS section — dynamic pipeline list
            if !pipelines.isEmpty {
                Section("CHARTS") {
                    ForEach(pipelines) { pipeline in
                        chartLabel(pipeline, isActive: selection == .pipeline(pipeline.id))
                            .tag(SidebarItem.pipeline(pipeline.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.navy)
        .foregroundStyle(Theme.Palette.sidebarText)
        .safeAreaInset(edge: .bottom) {
            // Sync status footer
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.Palette.success)
                        .frame(width: 6, height: 6)
                    Text("All lines synced")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.sidebarMuted)
                }
                Text("Google \u{00B7} Apple \u{00B7} \(syncTime)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.sidebarDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.Palette.navy)
            .overlay(Divider().opacity(0.15), alignment: .top)
        }
    }

    // MARK: Sidebar label builders

    private func sidebarNavLabel(_ title: String, icon: String, badge: String?, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            // Active indicator bar (brass) on the leading edge.
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? Theme.Palette.brass : Color.clear)
                .frame(width: 3, height: 14)

            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)

            Text(title.uppercased())
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .kerning(0.08)

            Spacer()

            if let badge {
                Text(badge)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(isActive ? Theme.Palette.sidebarActiveText : Theme.Palette.sidebarMuted)
            }
        }
        .foregroundStyle(isActive ? Theme.Palette.sidebarActiveText : Theme.Palette.sidebarText)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isActive ? Theme.Palette.sidebarActiveBg : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .listRowBackground(Theme.Palette.navy)
        .listRowSeparator(.hidden)
    }

    /// True when any pipeline board is showing (including the synthetic
    /// "Pipelines" nav tag), so the Pipelines nav item stays highlighted.
    private var isPipelineSelected: Bool {
        if case .pipeline = selection { return true }
        return false
    }

    private func chartLabel(_ pipeline: Pipeline, isActive: Bool) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: pipeline.colorHex))
                .frame(width: 8, height: 8)

            Text(pipeline.name)
                .font(.system(size: 12.5))
                .lineLimit(1)

            Spacer()

            let openDeals = pipeline.deals.filter { $0.status == .open }.count
            if openDeals > 0 {
                Text("\(openDeals)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.Palette.sidebarMuted)
            }
        }
        .foregroundStyle(isActive ? Theme.Palette.surface : Theme.Palette.sidebarText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isActive ? Color.white.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .listRowBackground(Theme.Palette.navy)
        .listRowSeparator(.hidden)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .bridge, nil:
            BridgeDashboardView(selection: $selection)
        case .tasks:
            BridgeTasksView()
        case .calendar:
            CalendarView()
                .id("\(settings.calendarSource.rawValue)-\(settings.googleClientID)")
        case let .pipeline(id):
            // The synthetic "Pipelines" nav tag won't match a real id, so fall
            // back to the first pipeline; only show the empty state when there
            // are genuinely no pipelines.
            if let pipeline = pipelines.first(where: { $0.id == id }) ?? pipelines.first {
                PipelineBoardView(pipeline: pipeline)
                    .id(pipeline.id)
            } else {
                ContentUnavailableView(
                    "No pipelines yet",
                    systemImage: "chart.bar",
                    description: Text("Create a pipeline to start tracking deals.")
                )
            }
        case .contacts:
            ContactsView()
        case .assistant:
            AIAssistantView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: Count helpers

    private var pipelineDealCount: Int {
        pipelines.reduce(0) { $0 + $1.deals.filter { $0.status == .open }.count }
    }
}

extension SidebarItem {
    /// Synthetic tag used to select Pipelines header (children are the actual pipelines).
    static let pipelinesHint = SidebarItem.pipeline(UUID())
}