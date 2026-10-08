import AppKit
import Observation
import SwiftUI

/// Everything one window shows: its scan, the focus folder and history, the selection, the table rows
/// and the chart geometry (see specs.md → Main Window Layout).
///
/// The tree itself lives in a `FileTree` shared with the scanner's threads. This model only copies out
/// small slices of it: the focus's children for the table, and chart geometry computed off the main
/// actor. While a scan runs, both are refreshed at most four times a second.
@Observable @MainActor
final class BrowserModel {
    enum Phase: Equatable {
        case empty, scanning, finished, stopped
    }

    enum Zoom {
        case none, zoomIn, zoomOut
    }

    struct Crumb: Identifiable, Hashable {
        var id: NodeID
        var name: String
    }

    struct TrashItem: Identifiable, Hashable {
        var id: NodeID
        var name: String
        var path: String
        var size: UInt64
        var isProtected: Bool
    }

    struct TrashRequest: Identifiable {
        let id = UUID()
        var items: [TrashItem]
        var total: UInt64 { items.reduce(0) { $0 + $1.size } }
        var hasProtectedItems: Bool { items.contains(where: \.isProtected) }
    }

    // MARK: Scan

    private(set) var rootURL: URL?
    private(set) var tree: FileTree?
    private(set) var phase: Phase = .empty
    private(set) var progress = ScanProgress()
    /// The current scan covers only the focused folder (Rescan Focus).
    private(set) var isPartialScan = false
    private(set) var restrictedPaths: [String] = []
    private(set) var availableCapacity: Int64?
    private var scanner: DiskScanner?
    private var scanTask: Task<Void, Never>?
    private var pendingFocusPath: String?
    private var lastRefresh = ContinuousClock.now
    private var lastVersion: UInt64 = .max

    // MARK: Navigation

    private(set) var focus: NodeID = 0
    private var backStack: [NodeID] = []
    private var forwardStack: [NodeID] = []
    var selection: Set<NodeID> = []
    /// Set when the chart selects something, so the table scrolls to it.
    private(set) var scrollTarget: NodeID?
    private(set) var breadcrumb: [Crumb] = []
    private(set) var focusInfo: NodeInfo?
    private(set) var zoom: Zoom = .none

    // MARK: View options

    var chartMode: ChartMode {
        didSet { if chartMode != oldValue { scheduleLayout() } }
    }
    var colorMode: ColorMode
    var sunburstRings: Int {
        didSet { if sunburstRings != oldValue { scheduleLayout() } }
    }
    var treemapDepth: Int {
        didSet { if treemapDepth != oldValue { scheduleLayout() } }
    }
    var layout: LayoutMode = .sideBySide
    var flattened = false {
        didSet { if flattened != oldValue { refreshRows() } }
    }
    var filterText = "" {
        didSet { if filterText != oldValue { refreshRows() } }
    }
    var sizeMode: SizeMode {
        didSet { if sizeMode != oldValue { refreshAll() } }
    }
    var sortOrder: [KeyPathComparator<ItemRow>] = [KeyPathComparator(\.size, order: .reverse)] {
        didSet { rows.sort(using: sortOrder) }
    }
    /// Bumped by ⌘F; the window focuses its filter field.
    private(set) var filterFocusRequest = 0
    var isShowingRestricted = false
    var isShowingLegend = false

    // MARK: Derived

    private(set) var rows: [ItemRow] = []
    private var rowIDs: Set<NodeID> = []
    private(set) var sunburst: SunburstGeometry?
    private(set) var treemap: TreemapGeometry?
    /// Bumped whenever a new chart geometry is shown, so views can drop segment indices into the old one.
    private(set) var chartRevision = 0
    var chartSize: CGSize = .zero {
        didSet {
            if chartSize != oldValue, chartMode == .treemap { scheduleLayout() }
        }
    }
    private var layoutGeneration = 0

    // MARK: Sheets and alerts

    var trashRequest: TrashRequest?
    var errorMessage: String?

    static let largestFilesLimit = 500

    init(defaults: UserDefaults = .standard) {
        chartMode = ChartMode(rawValue: defaults.string(forKey: PreferenceKey.chartMode) ?? "") ?? .sunburst
        colorMode = ColorMode(rawValue: defaults.string(forKey: PreferenceKey.colorMode) ?? "") ?? .size
        sunburstRings = min(max(defaults.integer(forKey: PreferenceKey.sunburstRings), 2), 8)
        treemapDepth = min(max(defaults.integer(forKey: PreferenceKey.treemapDepth), 1), 6)
        sizeMode = SizeMode(rawValue: defaults.string(forKey: PreferenceKey.sizeMode) ?? "") ?? .allocated
    }

    var title: String {
        guard let tree else { return "Parmesan" }
        return tree.read { $0.rootName }
    }

    var isScanning: Bool { phase == .scanning }
    var hasScan: Bool { tree != nil }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { focus != 0 && tree != nil }

    // MARK: - Scanning

    func startScan(_ url: URL) {
        stopScan()
        let scanner = DiskScanner(url: url, options: ScanPreferences.current())
        rootURL = URL(fileURLWithPath: scanner.rootPath, isDirectory: true)
        tree = scanner.tree
        focus = 0
        backStack = []
        forwardStack = []
        selection = []
        sunburst = nil
        treemap = nil
        restrictedPaths = []
        isPartialScan = false
        zoom = .none
        AppState.shared.addRecent(rootURL!)
        run(scanner)
    }

    func rescanAll() {
        guard let rootURL, !isScanning else { return }
        let focusPath = tree?.read { $0.path(focus) }
        startScan(rootURL)
        pendingFocusPath = focusPath
    }

    /// Rescans only the focused folder and splices the result into the tree (see specs.md → Rescan focus).
    func rescanFocus() {
        guard let tree, !isScanning else { return }
        if focus == 0 { return rescanAll() }
        let focus = focus
        tree.write { $0.resetForRescan(focus) }
        let stale: (NodeID) -> Bool = { id in tree.read { $0.isDescendant(id, of: focus) && id != focus } }
        backStack.removeAll(where: stale)
        forwardStack.removeAll(where: stale)
        selection = []
        isPartialScan = true
        run(DiskScanner(tree: tree, node: focus, options: ScanPreferences.current()))
    }

    func stopScan() {
        scanner?.cancel()
    }

    private func run(_ scanner: DiskScanner) {
        scanTask?.cancel()
        self.scanner = scanner
        phase = .scanning
        progress = ScanProgress()
        refreshAll()
        scanner.start()
        scanTask = Task { [weak self] in
            for await update in scanner.progressUpdates() {
                guard let self else { return }
                progress = update
                DockProgress.update(update, scanRootIsVolume: isVolumeRoot, volumeUsed: volumeUsed)
                if ContinuousClock.now - lastRefresh >= .milliseconds(250) { refreshIfChanged() }
                if pendingFocusPath != nil { restorePendingFocus() }
            }
            self?.scanFinished(scanner)
        }
    }

    private func scanFinished(_ scanner: DiskScanner) {
        guard self.scanner === scanner else { return }
        let final = scanner.progress()
        progress = final
        phase = final.wasCancelled ? .stopped : .finished
        restrictedPaths = tree?.read { s in s.restricted.map { s.path($0) } } ?? []
        availableCapacity = rootURL.flatMap {
            try? $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        }
        restorePendingFocus()
        pendingFocusPath = nil
        isPartialScan = false
        refreshAll()
        DockProgress.clear()
        if final.elapsed > 30 {
            AppState.shared.notifyScanFinished(name: title, progress: final, mode: sizeMode)
        }
    }

    private func restorePendingFocus() {
        guard let path = pendingFocusPath, let tree, let id = tree.read({ $0.find(path: path) }) else { return }
        pendingFocusPath = nil
        if id != focus {
            focus = id
            refreshAll()
        }
    }

    private var isVolumeRoot: Bool {
        (try? rootURL?.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true
    }

    private var volumeUsed: UInt64? {
        guard let values = try? rootURL?.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return UInt64(max(0, total - available))
    }

    // MARK: - Refreshing

    private func refreshIfChanged() {
        guard let tree, tree.version != lastVersion else { return }
        refreshAll()
    }

    /// Re-reads everything shown from the tree.
    func refreshAll() {
        lastRefresh = .now
        guard let tree else {
            rows = []
            breadcrumb = []
            focusInfo = nil
            return
        }
        lastVersion = tree.version
        let focus = focus
        let (crumbs, info) = tree.read { s in
            (s.lineage(focus).map { Crumb(id: $0, name: s.name($0)) }, s.info(focus))
        }
        breadcrumb = crumbs
        focusInfo = info
        selection = selection.filter { id in tree.read { s in s.contains(id) && !s.isRemoved(id) } }
        refreshRows()
        scheduleLayout()
    }

    func refreshRows() {
        guard let tree else { return }
        let focus = focus
        let mode = sizeMode
        let filter = RowFilter(text: filterText)
        let flattened = flattened
        let ids = tree.read { s in
            flattened ? s.largestFiles(under: focus, limit: Self.largestFilesLimit, mode) : s.children(focus)
        }
        var newRows: [ItemRow] = tree.read { s in
            let focusSize = s.size(focus, mode)
            var result: [ItemRow] = []
            result.reserveCapacity(ids.count)
            for id in ids where filter.isEmpty || filter.matches(s.name(id)) {
                result.append(ItemRow.make(s, id, focusSize: focusSize, mode))
            }
            return result
        }
        newRows.sort(using: sortOrder)
        rows = newRows
        rowIDs = Set(newRows.map(\.id))
    }

    /// Computes the active chart's geometry off the main actor; stale results are dropped.
    func scheduleLayout() {
        guard let tree else { return }
        layoutGeneration += 1
        let generation = layoutGeneration
        let focus = focus
        let mode = sizeMode
        let chartMode = chartMode
        let rings = sunburstRings
        let depth = treemapDepth
        let size = chartSize
        if chartMode == .treemap, size.width < 10 || size.height < 10 { return }
        Task.detached(priority: .userInitiated) {
            switch chartMode {
            case .sunburst:
                let geometry = tree.read { SunburstLayout.layout($0, focus: focus, rings: rings, mode: mode) }
                await self.apply(sunburst: geometry, generation: generation)
            case .treemap:
                let geometry = tree.read { TreemapLayout.layout($0, focus: focus, size: size, depth: depth, mode: mode) }
                await self.apply(treemap: geometry, generation: generation)
            }
        }
    }

    private func apply(sunburst geometry: SunburstGeometry, generation: Int) {
        guard generation == layoutGeneration else { return }
        animatingFocusChange(from: sunburst?.focus) { sunburst = geometry }
        chartRevision += 1
    }

    private func apply(treemap geometry: TreemapGeometry, generation: Int) {
        guard generation == layoutGeneration else { return }
        animatingFocusChange(from: treemap?.focus) { treemap = geometry }
        chartRevision += 1
    }

    /// Drilling in or out zooms the chart (~250 ms) unless animations are off or Reduce Motion is on.
    private func animatingFocusChange(from shown: NodeID?, _ update: () -> Void) {
        if shown != nil, shown != focus, zoom != .none, Self.animationsEnabled {
            withAnimation(.easeInOut(duration: 0.25)) { update() }
        } else {
            update()
        }
    }

    static var animationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.animations)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Navigation

    private func setFocus(_ id: NodeID, recordHistory: Bool = true) {
        guard let tree, id != focus, tree.read({ $0.contains(id) && $0.isDirectory(id) }) else { return }
        let deeper = tree.read { $0.isDescendant(id, of: focus) }
        zoom = deeper ? .zoomIn : .zoomOut
        if recordHistory {
            backStack.append(focus)
            forwardStack = []
        }
        let previous = focus
        focus = id
        flattened = false
        // Going up selects the folder you came from.
        let cameFrom = tree.read { s in s.lineage(previous).first { s.parent[Int($0)] == id } }
        selection = cameFrom.map { [$0] } ?? []
        if let cameFrom { scrollTarget = cameFrom }
        refreshAll()
    }

    func go(to id: NodeID) { setFocus(id) }

    /// Drills into a folder; opens a file with its default app.
    func activate(_ id: NodeID) {
        guard let tree else { return }
        let (isDirectory, isRestricted) = tree.read { ($0.isDirectory(id), $0.flags[Int(id)].contains(.restricted)) }
        if isDirectory {
            if !isRestricted { setFocus(id) }
        } else {
            OpenIn.open([tree.read { $0.url(id) }])
        }
    }

    func activate(_ ids: Set<NodeID>) {
        if ids.count == 1, let id = ids.first {
            activate(id)
        } else if !ids.isEmpty, let tree {
            OpenIn.open(ids.map { id in tree.read { $0.url(id) } })
        }
    }

    /// ⌘↓ / Return: drill into the selected folder (or open the selected file).
    func drillIntoSelection() {
        activate(selection)
    }

    func goUp() {
        guard let tree, focus != 0 else { return }
        setFocus(tree.read { $0.parent[Int(focus)] })
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(focus)
        setFocus(previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(focus)
        setFocus(next, recordHistory: false)
    }

    func goToRoot() { setFocus(0) }

    // MARK: - Selection

    /// Selects from the chart. The table shows the row the node sits in, scrolled into view.
    func select(_ id: NodeID, extending: Bool = false) {
        if extending {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        scrollTarget = tableRow(for: id)
    }

    /// The table's view of the selection: chart selections deeper than the table map to the row that
    /// contains them.
    var tableSelection: Set<NodeID> {
        get { Set(selection.compactMap(tableRow(for:))) }
        set { selection = newValue }
    }

    private func tableRow(for id: NodeID) -> NodeID? {
        if rowIDs.contains(id) { return id }
        guard !flattened, let tree else { return nil }
        let focus = focus
        return tree.read { s in s.lineage(id).first { s.parent[Int($0)] == focus } }
    }

    func requestFilterFocus() { filterFocusRequest += 1 }

    // MARK: - Actions (see specs.md → Actions & Shortcuts)

    /// The selection, or the focus folder when nothing is selected.
    var targets: [NodeID] {
        selection.isEmpty ? [focus] : selection.sorted()
    }

    func urls(_ ids: [NodeID]) -> [URL] {
        guard let tree else { return [] }
        return tree.read { s in ids.map { s.url($0) } }
    }

    func revealInFinder(_ ids: [NodeID]? = nil) {
        OpenIn.revealInFinder(urls(ids ?? targets))
    }

    func openInTerminal(_ ids: [NodeID]? = nil) {
        guard let url = urls(ids ?? targets).first else { return }
        let app = OpenIn.terminal(for: UserDefaults.standard.string(forKey: PreferenceKey.terminalApp) ?? "")
        Task {
            do { try await OpenIn.openInTerminal(url, app: app) } catch { errorMessage = error.localizedDescription }
        }
    }

    func open(_ ids: [NodeID]? = nil) {
        OpenIn.open(urls(ids ?? targets))
    }

    func quickLook(_ ids: [NodeID]? = nil) {
        QuickLook.shared.toggle(urls(ids ?? targets))
    }

    func getInfo(_ ids: [NodeID]? = nil) {
        do { try OpenIn.getInfo(urls(ids ?? targets)) } catch { errorMessage = error.localizedDescription }
    }

    func copyPaths(_ ids: [NodeID]? = nil) {
        Clipboard.copyPaths(urls(ids ?? targets).map(\.path))
    }

    func copySizeSummary(_ ids: [NodeID]? = nil) {
        guard let tree else { return }
        let mode = sizeMode
        Clipboard.copySizeSummary(tree.read { s in (ids ?? targets).map { (s.name($0), s.size($0, mode)) } })
    }

    func canTrash(_ ids: [NodeID]? = nil) -> Bool {
        tree != nil && !isScanning && !(ids ?? targets).contains(0)
    }

    /// Move to Trash, after a confirmation sheet unless that's turned off (protected items always ask).
    func requestTrash(_ ids: [NodeID]? = nil) {
        guard let tree, canTrash(ids) else { return }
        let mode = sizeMode
        let items = tree.read { s in
            (ids ?? targets).map { id in
                let path = s.path(id)
                return TrashItem(id: id, name: s.name(id), path: path, size: s.size(id, mode),
                                 isProtected: TrashSafety.isProtected(path))
            }
        }
        let request = TrashRequest(items: items)
        if UserDefaults.standard.bool(forKey: PreferenceKey.confirmTrash) || request.hasProtectedItems {
            trashRequest = request
        } else {
            performTrash(request)
        }
    }

    /// Moves the items to the Trash (never deletes) and takes them out of the tree in place.
    func performTrash(_ request: TrashRequest) {
        guard let tree else { return }
        var failures: [String] = []
        for item in request.items {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                tree.write { $0.remove(item.id) }
            } catch {
                failures.append("\(item.name): \(error.localizedDescription)")
            }
        }
        selection = []
        // The status bar's totals follow the tree, without a rescan.
        let (items, allocated, logical) = tree.read { (Int($0.items[0]), $0.allocated[0], $0.logical[0]) }
        progress.items = items
        progress.allocated = allocated
        progress.logical = logical
        refreshAll()
        if !failures.isEmpty {
            errorMessage = String(localized: "Some items couldn't be moved to the Trash:\n\(failures.joined(separator: "\n"))")
        }
    }

    /// For VoiceOver and tooltips: "Developer, folder, 48.2 GB, 31 percent".
    func accessibilityDescription(_ info: SegmentInfo) -> String {
        let kind = info.isOther ? String(localized: "group") : info.isDirectory ? String(localized: "folder") : String(localized: "file")
        let percent = Int((info.shareOfFocus * 100).rounded())
        return String(localized: "\(info.name), \(kind), \(Format.size(info.size)), \(percent) percent")
    }
}
