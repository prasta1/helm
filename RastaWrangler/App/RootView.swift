import SwiftUI
import SwiftData

/// The items shown in the sidebar. Pipelines are dynamic; the rest are fixed.
enum SidebarItem: Hashable {
    case pipeline(UUID)
    case contacts
    case meetings
    case calendar
    case assistant
    case settings
}

/// Root navigation: an adaptive `NavigationSplitView` that becomes a sidebar on
/// Mac/iPad and a stack on iPhone.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Pipeline.sortOrder) private var pipelines: [Pipeline]

    @State private var selection: SidebarItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingNewPipeline = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detail
        }
        .task {
            if selection == nil {
                selection = pipelines.first.map { .pipeline($0.id) } ?? .contacts
            }
        }
        .sheet(isPresented: $showingNewPipeline) {
            PipelineEditorView(pipeline: nil)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Pipelines") {
                ForEach(pipelines) { pipeline in
                    Label {
                        Text(pipeline.name)
                    } icon: {
                        Image(systemName: pipeline.iconSystemName)
                            .foregroundStyle(Color(hex: pipeline.colorHex))
                    }
                    .tag(SidebarItem.pipeline(pipeline.id))
                }
                .onDelete(perform: deletePipelines)

                Button {
                    showingNewPipeline = true
                } label: {
                    Label("New Pipeline", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Section("Workspace") {
                Label("Contacts", systemImage: "person.crop.circle").tag(SidebarItem.contacts)
                Label("Meetings", systemImage: "text.bubble").tag(SidebarItem.meetings)
                Label("Calendar", systemImage: "calendar").tag(SidebarItem.calendar)
                Label("AI Assistant", systemImage: "sparkles").tag(SidebarItem.assistant)
            }

            #if !os(macOS)
            Section {
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            #endif
        }
        .navigationTitle("RastaWrangler")
        .safeAreaInset(edge: .top) {
            BrandMark()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
        }
        #if os(iOS)
        .listStyle(.sidebar)
        #endif
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case let .pipeline(id):
            if let pipeline = pipelines.first(where: { $0.id == id }) {
                PipelineBoardView(pipeline: pipeline)
                    .id(pipeline.id)
            } else {
                EmptyStateView(title: "Pipeline not found", message: "It may have been deleted.", systemImage: "questionmark.folder")
            }
        case .contacts:
            ContactsView()
        case .meetings:
            MeetingsView()
        case .calendar:
            CalendarView()
                .id(settings.googleClientID)
        case .assistant:
            AIAssistantView()
        case .settings:
            SettingsView()
        case nil:
            EmptyStateView(title: "Welcome to RastaWrangler", message: "Pick a pipeline to get started.", systemImage: "square.stack.3d.up")
        }
    }

    private func deletePipelines(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(pipelines[index])
        }
        try? modelContext.save()
    }
}

#Preview {
    RootView()
        .environment(AppSettings())
        .modelContainer(PersistenceController.makeInMemoryContainer())
}
