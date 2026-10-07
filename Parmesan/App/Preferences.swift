import AppKit

/// UserDefaults keys for Settings (see specs.md → Settings). Read with `@AppStorage` in views; the
/// defaults are registered once at launch so every reader agrees on them.
enum PreferenceKey {
    // General
    static let terminalApp = "terminalApp"
    static let confirmTrash = "confirmTrash"
    static let restoreLastScan = "restoreLastScan"
    // Scanning
    static let sizeMode = "sizeMode"
    static let crossVolumes = "crossVolumes"
    static let countHardLinksOnce = "countHardLinksOnce"
    static let skipPatterns = "skipPatterns"
    static let includeHidden = "includeHidden"
    // Appearance
    static let appearance = "appearance"
    static let chartMode = "chartMode"
    static let sunburstRings = "sunburstRings"
    static let treemapDepth = "treemapDepth"
    static let colorMode = "colorMode"
    static let showLabels = "showLabels"
    static let animations = "animations"
    // State
    static let recentScans = "recentScans"
    static let skipAccessOnboarding = "skipFullDiskAccessOnboarding"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            terminalApp: OpenIn.terminal.bundleID,
            confirmTrash: true,
            restoreLastScan: false,
            sizeMode: SizeMode.allocated.rawValue,
            crossVolumes: false,
            countHardLinksOnce: true,
            skipPatterns: "",
            includeHidden: true,
            appearance: Appearance.system.rawValue,
            chartMode: ChartMode.sunburst.rawValue,
            sunburstRings: 4,
            treemapDepth: 3,
            colorMode: ColorMode.size.rawValue,
            showLabels: true,
            animations: true,
        ])
    }
}

/// Settings → Scanning, read when a scan starts.
enum ScanPreferences {
    static func current(_ defaults: UserDefaults = .standard) -> ScanOptions {
        var options = ScanOptions()
        options.crossVolumes = defaults.bool(forKey: PreferenceKey.crossVolumes)
        options.countHardLinksOnce = defaults.bool(forKey: PreferenceKey.countHardLinksOnce)
        options.includeHidden = defaults.bool(forKey: PreferenceKey.includeHidden)
        options.skipList = SkipList(text: defaults.string(forKey: PreferenceKey.skipPatterns) ?? "")
        return options
    }
}

enum ChartMode: String, CaseIterable, Identifiable {
    case sunburst, treemap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sunburst: String(localized: "Sunburst")
        case .treemap: String(localized: "Treemap")
        }
    }

    var systemImage: String {
        switch self {
        case .sunburst: "chart.pie"
        case .treemap: "square.grid.2x2"
        }
    }
}

enum ColorMode: String, CaseIterable, Identifiable {
    case size, kind, age

    var id: String { rawValue }

    var label: String {
        switch self {
        case .size: String(localized: "By Size")
        case .kind: String(localized: "By Kind")
        case .age: String(localized: "By Age")
        }
    }
}

/// Chart and table side by side, stacked, or the table alone.
enum LayoutMode: String, CaseIterable, Identifiable {
    case sideBySide, stacked, tableOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: String(localized: "Side by Side")
        case .stacked: String(localized: "Stacked")
        case .tableOnly: String(localized: "Table Only")
        }
    }
}

/// Settings → Appearance. Applied through `NSApp.appearance` rather than `.preferredColorScheme`,
/// so sheets, alerts, menus and the Settings window follow it too.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    static func apply(_ rawValue: String) {
        NSApp.appearance = (Appearance(rawValue: rawValue) ?? .system).nsAppearance
    }
}

/// Running under XCTest: no onboarding sheets or restored scans.
enum Runtime {
    static let isRunningTests = NSClassFromString("XCTestCase") != nil
}
