import SwiftUI
import SwiftData

@main
struct HelmApp: App {
    /// The single shared SwiftData container for the whole app.
    private let container = PersistenceController.makeSharedContainer()

    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Theme.Palette.brass)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        .commands {
            SidebarCommands()
            HelmCommands()
        }
        #endif

        #if os(macOS)
        // A dedicated Settings window on macOS (⌘,).
        Settings {
            SettingsView()
                .environment(settings)
                .modelContainer(container)
                .frame(width: 560, height: 620)
        }
        #endif
    }
}

// MARK: - Menu bar commands

/// Focused values let views publish state "upward" to the menu bar: RootView
/// exposes bindings via `.focusedSceneValue`, and the commands below read them
/// with `@FocusedBinding` for whichever window is frontmost. When no Helm
/// window is key, the bindings are nil and the commands are no-ops.
struct SidebarSelectionKey: FocusedValueKey {
    typealias Value = Binding<SidebarItem?>
}

struct NewPipelineRequestKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var sidebarSelection: Binding<SidebarItem?>? {
        get { self[SidebarSelectionKey.self] }
        set { self[SidebarSelectionKey.self] = newValue }
    }

    var newPipelineRequest: Binding<Bool>? {
        get { self[NewPipelineRequestKey.self] }
        set { self[NewPipelineRequestKey.self] = newValue }
    }
}

/// App-specific menu bar commands: a Go menu mirroring the sidebar (⌘1–⌘5,
/// ⌘J for Ask Helm — the shortcut the dashboard ask bar advertises) and a
/// New Pipeline… item in the File menu.
struct HelmCommands: Commands {
    @FocusedBinding(\.sidebarSelection) private var selection
    @FocusedBinding(\.newPipelineRequest) private var newPipelineRequest

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Pipeline…") { newPipelineRequest = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Go") {
            Button("The Bridge") { selection = .bridge }
                .keyboardShortcut("1", modifiers: .command)
            Button("Tasks") { selection = .tasks }
                .keyboardShortcut("2", modifiers: .command)
            Button("Calendar") { selection = .calendar }
                .keyboardShortcut("3", modifiers: .command)
            Button("Pipelines") { selection = .pipelinesHint }
                .keyboardShortcut("4", modifiers: .command)
            Button("Contacts") { selection = .contacts }
                .keyboardShortcut("5", modifiers: .command)
            Divider()
            Button("Ask Helm") { selection = .assistant }
                .keyboardShortcut("j", modifiers: .command)
        }
    }
}