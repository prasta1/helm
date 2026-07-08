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
                .tint(Theme.Palette.accent)
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            SidebarCommands()
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
