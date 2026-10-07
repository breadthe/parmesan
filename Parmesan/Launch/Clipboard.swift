import AppKit

/// Copy Path and Copy Size Summary.
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// POSIX paths, one per line.
    static func copyPaths(_ paths: [String]) {
        copy(paths.joined(separator: "\n"))
    }

    /// "<name> — <size>" lines.
    static func copySizeSummary(_ items: [(name: String, size: UInt64)]) {
        copy(items.map { "\($0.name) — \(Format.size($0.size))" }.joined(separator: "\n"))
    }
}
