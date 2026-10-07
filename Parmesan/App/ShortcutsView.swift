import SwiftUI

/// Help → Keyboard Shortcuts (see specs.md → Actions & Shortcuts).
struct ShortcutsView: View {
    struct Entry: Identifiable {
        var id: String { action }
        var action: String
        var keys: String
    }

    static let sections: [(String, [Entry])] = [
        (String(localized: "Items"), [
            Entry(action: String(localized: "Reveal in Finder"), keys: "⌘R"),
            Entry(action: String(localized: "Open in Terminal"), keys: "⌥⌘T"),
            Entry(action: String(localized: "Open (selection)"), keys: "⌘O"),
            Entry(action: String(localized: "Quick Look"), keys: "Space  ·  ⌘Y"),
            Entry(action: String(localized: "Get Info in Finder"), keys: "⌘I"),
            Entry(action: String(localized: "Copy Path"), keys: "⌥⌘C"),
            Entry(action: String(localized: "Copy Size Summary"), keys: "⇧⌘C"),
            Entry(action: String(localized: "Move to Trash"), keys: "⌘⌫"),
        ]),
        (String(localized: "Navigation"), [
            Entry(action: String(localized: "Drill In"), keys: "⌘↓  ·  Return  ·  double-click"),
            Entry(action: String(localized: "Up to Parent"), keys: "⌘↑  ·  ⌫"),
            Entry(action: String(localized: "Back / Forward"), keys: "⌘[  ·  ⌘]"),
            Entry(action: String(localized: "Go to Root"), keys: "⇧⌘↑"),
        ]),
        (String(localized: "Scanning"), [
            Entry(action: String(localized: "Scan Folder (nothing selected)"), keys: "⌘O"),
            Entry(action: String(localized: "Rescan Focus"), keys: "⇧⌘R"),
            Entry(action: String(localized: "Rescan All"), keys: "⌥⌘R"),
            Entry(action: String(localized: "Stop Scan"), keys: "⌘."),
            Entry(action: String(localized: "New Scan Window"), keys: "⌘N"),
        ]),
        (String(localized: "View"), [
            Entry(action: String(localized: "Sunburst / Treemap"), keys: "⌘1  ·  ⌘2"),
            Entry(action: String(localized: "Show Largest Files"), keys: "⌘L"),
            Entry(action: String(localized: "Filter"), keys: "⌘F"),
            Entry(action: String(localized: "Settings"), keys: "⌘,"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Self.sections, id: \.0) { title, entries in
                Section(title) {
                    ForEach(entries) { entry in
                        LabeledContent(entry.action) {
                            Text(entry.keys).monospaced()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
