import AppKit

/// A GUI app Parmesan can open a folder in.
struct ExternalApp: Identifiable, Hashable {
    var id: String { bundleID }
    let name: String
    let bundleID: String

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { url != nil }
}

struct OperationError: LocalizedError {
    var errorDescription: String?
}

/// Finder, Terminal and Get Info (see specs.md → Open in Terminal — details).
enum OpenIn {
    static let terminal = ExternalApp(name: "Terminal", bundleID: "com.apple.Terminal")

    /// Choices for Settings → General → Terminal; only installed ones are offered.
    static let terminals = [
        terminal,
        ExternalApp(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        ExternalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        ExternalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        ExternalApp(name: "WezTerm", bundleID: "com.github.wez.wezterm"),
        ExternalApp(name: "kitty", bundleID: "net.kovidgoyal.kitty"),
    ]

    /// The saved terminal if it's still installed, else Terminal.
    static func terminal(for bundleID: String) -> ExternalApp {
        terminals.first { $0.bundleID == bundleID && $0.isInstalled } ?? terminal
    }

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens each item with its default app.
    static func open(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }

    /// Opens the folder (or a file's parent folder) in a terminal, like `open -a <app> <folder>`.
    static func openInTerminal(_ url: URL, app: ExternalApp) async throws {
        guard let appURL = app.url else {
            throw OperationError(errorDescription: String(localized: "\(app.name) isn't installed."))
        }
        let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        try await NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Asks Finder to show its Get Info window for each item (Apple Events; macOS asks for Automation
    /// permission the first time).
    @MainActor
    static func getInfo(_ urls: [URL]) throws {
        let items = urls.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        let source = """
        tell application "Finder"
            activate
            repeat with anItem in {\(items)}
                open information window of (anItem as alias)
            end repeat
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return }
        if error[NSAppleScript.errorNumber] as? Int == -1743 {
            throw OperationError(errorDescription: String(localized: "Parmesan isn't allowed to control Finder. Turn it on in System Settings → Privacy & Security → Automation → Parmesan → Finder."))
        }
        throw OperationError(errorDescription: (error[NSAppleScript.errorMessage] as? String) ?? String(localized: "Finder couldn't show the Info window."))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
