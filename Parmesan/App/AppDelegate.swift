import AppKit
import QuickLookUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply(UserDefaults.standard.string(forKey: PreferenceKey.appearance) ?? "")
    }

    /// Folders dropped on the Dock icon or opened with Parmesan from Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppState.shared.requestOpen(urls)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshFullDiskAccess()
    }

    // MARK: Quick Look: the panel looks for a controller along the responder chain, which ends here.

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    // These come from an Objective-C informal protocol, so they aren't marked main-actor, but the panel
    // only ever calls them on the main thread.
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = QuickLook.shared
            panel.delegate = QuickLook.shared
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}
