import SwiftUI

@main
struct ParmesanApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appState: AppState

    init() {
        if CommandLineMode.isRequested { CommandLineMode.run() }
        PreferenceKey.registerDefaults()
        _appState = State(initialValue: AppState.shared)
    }

    var body: some Scene {
        // One scan root per window; windows can be merged into tabs (see specs.md → Main Window Layout).
        WindowGroup(id: WindowID.browser, for: URL.self) { $url in
            BrowserWindow(url: $url)
                .environment(appState)
        }
        .commands {
            ParmesanCommands(appState: appState)
        }

        Window("Keyboard Shortcuts", id: WindowID.shortcuts) {
            ShortcutsView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

/// Picks a folder to scan (⌘O).
@MainActor
enum FolderPicker {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = String(localized: "Scan")
        panel.message = String(localized: "Choose a folder or volume to scan.")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
