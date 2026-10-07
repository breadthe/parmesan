import Darwin
import Foundation

/// Shell-style wildcards (`*`, `?`, `[…]`) via `fnmatch(3)`, used by the table filter and Settings →
/// Scanning → Skip paths.
enum Glob {
    static func isPattern(_ text: String) -> Bool {
        text.contains { $0 == "*" || $0 == "?" || $0 == "[" }
    }

    static func matches(_ pattern: String, _ text: String, caseInsensitive: Bool = true) -> Bool {
        fnmatch(pattern, text, caseInsensitive ? FNM_CASEFOLD : 0) == 0
    }
}

/// Settings → Scanning → Skip paths. A pattern with a `/` is matched against the full path (`~` expands
/// to Home), anything else against the item's name: `node_modules`, `*.photoslibrary`, `~/Library/Caches/*`.
struct SkipList: Sendable {
    private let namePatterns: [String]
    private let pathPatterns: [String]

    init(_ patterns: [String]) {
        let cleaned = patterns.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        namePatterns = cleaned.filter { !$0.contains("/") }
        pathPatterns = cleaned.filter { $0.contains("/") }.map {
            let expanded = ($0 as NSString).expandingTildeInPath
            return expanded.count > 1 && expanded.hasSuffix("/") ? String(expanded.dropLast()) : expanded
        }
    }

    /// Splits Settings' one-pattern-per-line text.
    init(text: String) {
        self.init(text.components(separatedBy: .newlines))
    }

    var isEmpty: Bool { namePatterns.isEmpty && pathPatterns.isEmpty }

    func skips(name: String, path: String) -> Bool {
        namePatterns.contains { Glob.matches($0, name, caseInsensitive: false) }
            || pathPatterns.contains { Glob.matches($0, path, caseInsensitive: false) }
    }
}
