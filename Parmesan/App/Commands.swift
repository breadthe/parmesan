import SwiftUI

/// The menu bar (see specs.md → Actions & Shortcuts). Every shortcut is listed in a menu, so Help search
/// finds it. Actions apply to the focused window's selection, or its focus folder when nothing is selected.
struct ParmesanCommands: Commands {
    let appState: AppState
    @FocusedValue(\.browserModel) private var model
    @Environment(\.openWindow) private var openWindow

    private var hasScan: Bool { model?.hasScan == true }
    private var hasSelection: Bool { model?.selection.isEmpty == false }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Scan Folder…") { scanFolder() }
                // ⌘O opens the selection when there is one (Item → Open).
                .keyboardShortcut(hasSelection ? nil : KeyboardShortcut("o"))
            Menu("Scan Recent") {
                ForEach(appState.recents, id: \.self) { url in
                    Button(FileManager.default.displayName(atPath: url.path)) { scan(url) }
                }
                Divider()
                Button("Clear Menu") { appState.clearRecents() }
                    .disabled(appState.recents.isEmpty)
            }
        }

        CommandGroup(before: .toolbar) {
            Toggle("Sunburst", isOn: binding(\.chartMode, .sunburst))
                .keyboardShortcut("1")
                .disabled(!hasScan)
            Toggle("Treemap", isOn: binding(\.chartMode, .treemap))
                .keyboardShortcut("2")
                .disabled(!hasScan)
            Toggle("Show Largest Files", isOn: Binding(get: { model?.flattened ?? false }, set: { model?.flattened = $0 }))
                .keyboardShortcut("l")
                .disabled(!hasScan)
            Button("Filter") { model?.requestFilterFocus() }
                .keyboardShortcut("f")
                .disabled(!hasScan)
            Menu("Color") {
                ForEach(ColorMode.allCases) { mode in
                    Toggle(mode.label, isOn: binding(\.colorMode, mode))
                }
            }
            .disabled(!hasScan)
            Menu("Sunburst Rings") {
                ForEach(2 ... 8, id: \.self) { rings in
                    Toggle("\(rings) Rings", isOn: binding(\.sunburstRings, rings))
                }
            }
            .disabled(!hasScan)
            Menu("Treemap Depth") {
                ForEach(1 ... 6, id: \.self) { depth in
                    Toggle("\(depth) Levels", isOn: binding(\.treemapDepth, depth))
                }
            }
            .disabled(!hasScan)
            Menu("Layout") {
                ForEach(LayoutMode.allCases) { layout in
                    Toggle(layout.label, isOn: binding(\.layout, layout))
                }
            }
            .disabled(!hasScan)
            Button("Show Legend") { model?.isShowingLegend.toggle() }
                .disabled(!hasScan || model?.layout == .tableOnly)
            Divider()
        }

        CommandMenu("Go") {
            Button("Drill In") { model?.drillIntoSelection() }
                .keyboardShortcut(.downArrow)
                .disabled(!hasSelection)
            Button("Up to Parent") { model?.goUp() }
                .keyboardShortcut(.upArrow)
                .disabled(model?.canGoUp != true)
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[")
                .disabled(model?.canGoBack != true)
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]")
                .disabled(model?.canGoForward != true)
            Button("Go to Root") { model?.goToRoot() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                .disabled(model?.canGoUp != true)
        }

        CommandMenu("Item") {
            Button("Reveal in Finder") { model?.revealInFinder() }
                .keyboardShortcut("r")
                .disabled(!hasScan)
            Button("Open in Terminal") { model?.openInTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!hasScan)
            Button("Open") { model?.open() }
                .keyboardShortcut("o")
                .disabled(!hasSelection)
            Button("Quick Look") { model?.quickLook() }
                .keyboardShortcut("y")
                .disabled(!hasScan)
            Button("Get Info") { model?.getInfo() }
                .keyboardShortcut("i")
                .disabled(!hasScan)
            Divider()
            Button("Copy Path") { model?.copyPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!hasScan)
            Button("Copy Size Summary") { model?.copySizeSummary() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!hasScan)
            Divider()
            Button("Move to Trash…") { model?.requestTrash() }
                .keyboardShortcut(.delete)
                .disabled(model?.canTrash() != true)
        }

        CommandMenu("Scan") {
            Button("Rescan Focus") { model?.rescanFocus() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!hasScan || model?.isScanning == true)
            Button("Rescan All") { model?.rescanAll() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!hasScan || model?.isScanning == true)
            Button("Stop Scan") { model?.stopScan() }
                .keyboardShortcut(".")
                .disabled(model?.isScanning != true)
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: WindowID.shortcuts) }
                .keyboardShortcut("/")
            Button("Grant Full Disk Access…") { FullDiskAccess.openSettings() }
        }
    }

    private func binding<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<BrowserModel, Value>, _ value: Value) -> Binding<Bool> {
        Binding(
            get: { model?[keyPath: keyPath] == value },
            set: { if $0 { model?[keyPath: keyPath] = value } }
        )
    }

    private func scanFolder() {
        guard let url = FolderPicker.choose() else { return }
        scan(url)
    }

    /// In the focused window when it's empty, else in a new one.
    private func scan(_ url: URL) {
        if let model, !model.hasScan {
            model.startScan(url)
        } else {
            openWindow(id: WindowID.browser, value: url)
        }
    }
}
