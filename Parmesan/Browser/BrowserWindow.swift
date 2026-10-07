import SwiftUI

/// One window: the welcome screen until a scan starts, then the browser.
struct BrowserWindow: View {
    /// The window's scan root, restored with the window.
    @Binding var url: URL?
    @State private var model = BrowserModel()
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(PreferenceKey.sizeMode) private var sizeMode = SizeMode.allocated.rawValue
    @AppStorage(PreferenceKey.restoreLastScan) private var restoreLastScan = false
    @SceneStorage("sort") private var savedSort = "size:reverse"
    @State private var isShowingAccessSheet = false
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if model.hasScan {
                BrowserView(model: model)
            } else {
                WelcomeView(model: model, isDropTargeted: isDropTargeted)
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .environment(\.chartPalette, ChartPalette.resolve(dark: colorScheme == .dark))
        .navigationTitle(model.title)
        .focusedSceneValue(\.browserModel, model)
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { $0.hasDirectoryPath || isDirectory($0) }) else { return false }
            model.startScan(folder)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onAppear(perform: appeared)
        .onChange(of: appState.openRequests) { _, requests in
            if !requests.isEmpty, activeState == .key { takeOpenRequests() }
        }
        .onChange(of: model.rootURL) { _, root in url = root }
        .onChange(of: sizeMode) { _, value in model.sizeMode = SizeMode(rawValue: value) ?? .allocated }
        .onChange(of: model.sortOrder) { _, order in savedSort = Self.encode(order) }
        .sheet(item: $model.trashRequest) { request in
            TrashSheet(request: request) { model.performTrash(request) }
        }
        .sheet(isPresented: $isShowingAccessSheet) {
            FullDiskAccessSheet()
                .environment(appState)
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func appeared() {
        appState.openWindow = openWindow
        #if DEBUG
        DebugScript.register(model, openSettings: openSettings)
        #endif
        model.sortOrder = Self.decode(savedSort)
        if let url, !model.hasScan {
            model.startScan(url)
        } else if !appState.openRequests.isEmpty {
            takeOpenRequests()
        } else if !appState.hasHandledLaunchRestore, restoreLastScan, !Runtime.isRunningTests, let last = appState.recents.first {
            model.startScan(last)
        }
        appState.hasHandledLaunchRestore = true
        if appState.shouldShowAccessOnboarding {
            appState.hasShownAccessOnboarding = true
            isShowingAccessSheet = true
        }
    }

    /// Folders from the Dock or Finder: the first one here if this window is empty, the rest in new windows.
    private func takeOpenRequests() {
        var requests = appState.takeOpenRequests()
        if !model.hasScan, !requests.isEmpty {
            model.startScan(requests.removeFirst())
        }
        for request in requests {
            openWindow(id: WindowID.browser, value: request)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // Sort order persists per window as "column:order".
    private static func encode(_ order: [KeyPathComparator<ItemRow>]) -> String {
        guard let first = order.first else { return "size:reverse" }
        let column = columns.first { $0.value == first.keyPath }?.key ?? "size"
        return "\(column):\(first.order == .forward ? "forward" : "reverse")"
    }

    private static func decode(_ text: String) -> [KeyPathComparator<ItemRow>] {
        let parts = text.split(separator: ":").map(String.init)
        let order: SortOrder = parts.count > 1 && parts[1] == "forward" ? .forward : .reverse
        switch parts.first {
        case "name": return [KeyPathComparator(\.name, comparator: .localizedStandard, order: order)]
        case "items": return [KeyPathComparator(\.itemCount, order: order)]
        case "kind": return [KeyPathComparator(\.kindDescription, comparator: .localizedStandard, order: order)]
        case "modified": return [KeyPathComparator(\.modified, order: order)]
        case "path": return [KeyPathComparator(\.path, comparator: .localizedStandard, order: order)]
        case "fraction": return [KeyPathComparator(\.fraction, order: order)]
        default: return [KeyPathComparator(\.size, order: order)]
        }
    }

    private static let columns: [String: PartialKeyPath<ItemRow>] = [
        "name": \ItemRow.name, "size": \ItemRow.size, "fraction": \ItemRow.fraction, "items": \ItemRow.itemCount,
        "kind": \ItemRow.kindDescription, "modified": \ItemRow.modified, "path": \ItemRow.path,
    ]
}
