import AppKit
import Observation
import SwiftUI
import UserNotifications

/// App-wide state shared by all windows: recent scans, folders handed to the app by the Dock or Finder,
/// and the Full Disk Access check.
@Observable @MainActor
final class AppState {
    static let shared = AppState()

    /// Most recent first.
    private(set) var recents: [URL] = []
    /// Folders dropped on the Dock icon (or opened with Parmesan) that no window has taken yet.
    private(set) var openRequests: [URL] = []
    private(set) var hasFullDiskAccess = FullDiskAccess.isGranted
    /// Captured from the first window, so folders can open new windows from outside a view.
    @ObservationIgnored var openWindow: OpenWindowAction?
    /// The onboarding sheet shows at most once per launch.
    var hasShownAccessOnboarding = false
    /// "Restore last scan on launch" applies to the first window only.
    var hasHandledLaunchRestore = false

    private let defaults: UserDefaults
    private static let maxRecents = 10

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = (defaults.array(forKey: PreferenceKey.recentScans) as? [Data] ?? []).compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
        }
    }

    // MARK: Recents (bookmarks, so they follow moved folders)

    func addRecent(_ url: URL) {
        var updated = recents.filter { $0.standardizedFileURL != url.standardizedFileURL }
        updated.insert(url, at: 0)
        saveRecents(Array(updated.prefix(Self.maxRecents)))
    }

    func removeRecent(_ url: URL) {
        saveRecents(recents.filter { $0 != url })
    }

    func clearRecents() {
        saveRecents([])
    }

    private func saveRecents(_ urls: [URL]) {
        recents = urls
        defaults.set(urls.compactMap { try? $0.bookmarkData() }, forKey: PreferenceKey.recentScans)
    }

    // MARK: Opening folders from outside

    func requestOpen(_ urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard !folders.isEmpty else { return }
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if !hasWindow, let openWindow {
            for url in folders { openWindow(id: WindowID.browser, value: url) }
        } else {
            openRequests += folders
        }
    }

    func takeOpenRequests() -> [URL] {
        defer { openRequests = [] }
        return openRequests
    }

    // MARK: Full Disk Access

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.isGranted
    }

    var shouldShowAccessOnboarding: Bool {
        !hasFullDiskAccess && !hasShownAccessOnboarding && !Runtime.isRunningTests
            && !defaults.bool(forKey: PreferenceKey.skipAccessOnboarding)
    }

    // MARK: Notifications

    /// A long scan (> 30 s) finished while Parmesan was in the background (see specs.md → Status Bar & Feedback).
    func notifyScanFinished(name: String, progress: ScanProgress, mode: SizeMode) {
        guard !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = progress.wasCancelled ? String(localized: "Scan stopped") : String(localized: "Scan finished")
        content.body = String(localized: "\(name): \(Format.count(progress.items)) items, \(Format.size(progress.bytes(mode))) in \(Format.duration(progress.elapsed))")
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

enum WindowID {
    static let browser = "browser"
    static let shortcuts = "shortcuts"
}

extension FocusedValues {
    @Entry var browserModel: BrowserModel?
}
