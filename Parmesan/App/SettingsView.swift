import SwiftUI

/// The ⌘, window: General, Scanning, Appearance (see specs.md → Settings).
struct SettingsView: View {
    // The last tab shown; the debug script also sets it for screenshots.
    @AppStorage("settingsTab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)
            ScanningSettings()
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
                .tag(1)
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(2)
        }
        .frame(width: 520, height: 560)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(PreferenceKey.terminalApp) private var terminalID = OpenIn.terminal.bundleID
    @AppStorage(PreferenceKey.confirmTrash) private var confirmTrash = true
    @AppStorage(PreferenceKey.restoreLastScan) private var restoreLastScan = false

    var body: some View {
        Form {
            Picker("Terminal", selection: $terminalID) {
                ForEach(OpenIn.terminals.filter(\.isInstalled)) { app in
                    Text(app.name).tag(app.bundleID)
                }
            }
            Toggle("Confirm before moving to the Trash", isOn: $confirmTrash)
            Text("Items in system locations always ask, and need ⌥ held to move.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Restore last scan on launch", isOn: $restoreLastScan)
            Text("Rescans the most recent folder when Parmesan opens with no windows to restore.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            // Fall back to Terminal if the saved app has been uninstalled.
            terminalID = OpenIn.terminal(for: terminalID).bundleID
        }
    }
}

// MARK: - Scanning

private struct ScanningSettings: View {
    @AppStorage(PreferenceKey.sizeMode) private var sizeMode = SizeMode.allocated.rawValue
    @AppStorage(PreferenceKey.crossVolumes) private var crossVolumes = false
    @AppStorage(PreferenceKey.countHardLinksOnce) private var countHardLinksOnce = true
    @AppStorage(PreferenceKey.includeHidden) private var includeHidden = true
    @AppStorage(PreferenceKey.skipPatterns) private var skipPatterns = ""

    var body: some View {
        Form {
            Section {
                Picker("Size", selection: $sizeMode) {
                    ForEach(SizeMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Text("Allocated size is what the file takes on disk; logical size is its length. Applies right away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Cross into other volumes", isOn: $crossVolumes)
                Toggle("Count hard links once", isOn: $countHardLinksOnce)
                Toggle("Include hidden files", isOn: $includeHidden)
            } footer: {
                Text("These apply to the next scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Skip Paths") {
                TextEditor(text: $skipPatterns)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                Text("One glob pattern per line. Patterns with a / match the full path (~ is your Home folder), others match names: `node_modules`, `*.photoslibrary`, `~/Library/Caches/*`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(PreferenceKey.chartMode) private var chartMode = ChartMode.sunburst.rawValue
    @AppStorage(PreferenceKey.sunburstRings) private var sunburstRings = 4
    @AppStorage(PreferenceKey.treemapDepth) private var treemapDepth = 3
    @AppStorage(PreferenceKey.colorMode) private var colorMode = ColorMode.size.rawValue
    @AppStorage(PreferenceKey.showLabels) private var showLabels = true
    @AppStorage(PreferenceKey.animations) private var animations = true

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _, value in Appearance.apply(value) }

            Section {
                Picker("Default chart", selection: $chartMode) {
                    ForEach(ChartMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Stepper("Sunburst rings: \(sunburstRings)", value: $sunburstRings, in: 2 ... 8)
                Stepper("Treemap levels: \(treemapDepth)", value: $treemapDepth, in: 1 ... 6)
                Picker("Color", selection: $colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            } footer: {
                Text("Defaults for new windows; each window can change them from the View menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show labels on the chart", isOn: $showLabels)
                Toggle("Animate drilling in and out", isOn: $animations)
            }
        }
        .formStyle(.grouped)
    }
}
