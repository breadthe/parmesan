import SwiftUI

/// The main window once a scan has started: chart and table in a split view, the toolbar with the
/// breadcrumb, and the status bar (see specs.md → Main Window Layout).
struct BrowserView: View {
    @Bindable var model: BrowserModel
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        // A VStack rather than a bottom safe-area inset: the AppKit split views don't respect insets.
        VStack(spacing: 0) {
            content
            StatusBar(model: model)
        }
            .toolbar { toolbar }
            .toolbar(removing: .title)
            .searchable(text: $model.filterText, placement: .toolbar, prompt: Text("Filter"))
            .searchFocused($isFilterFocused)
            .onChange(of: model.filterFocusRequest) { isFilterFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.layout {
        case .sideBySide:
            HSplitView {
                ChartView(model: model)
                    .frame(minWidth: 300, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                ContentsTable(model: model)
                    .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .stacked:
            VSplitView {
                ChartView(model: model)
                    .frame(minHeight: 220, idealHeight: 360, maxHeight: .infinity)
                ContentsTable(model: model)
                    .frame(minHeight: 160, idealHeight: 280, maxHeight: .infinity)
            }
        case .tableOnly:
            ContentsTable(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ControlGroup {
                Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .help("Back (⌘[)")
                Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .help("Forward (⌘])")
            }
            .controlGroupStyle(.navigation)
            Button { model.goUp() } label: { Label("Up to Parent", systemImage: "arrow.up") }
                .disabled(!model.canGoUp)
                .help("Up to Parent (⌘↑)")
        }
        ToolbarItem(placement: .navigation) {
            Breadcrumb(model: model)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Chart", selection: $model.chartMode) {
                ForEach(ChartMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Sunburst (⌘1) or Treemap (⌘2)")
            .disabled(model.layout == .tableOnly)

            Menu {
                Picker("Color", selection: $model.colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Color: \(model.colorMode.label)", systemImage: "paintpalette")
            }
            .help("Color the chart by size, kind or age")

            Button { model.isShowingLegend.toggle() } label: { Label("Legend", systemImage: "info.circle") }
                .help("What the colors mean")
                .popover(isPresented: $model.isShowingLegend, arrowEdge: .bottom) {
                    LegendView(mode: model.colorMode)
                }

            Button { model.revealInFinder() } label: { Label("Reveal in Finder", systemImage: "finder") }
                .help("Reveal in Finder (⌘R)")
            Button { model.openInTerminal() } label: { Label("Open in Terminal", systemImage: "terminal") }
                .help("Open in Terminal (⌥⌘T)")
            Toggle(isOn: $model.flattened) { Label("Largest Files", systemImage: "list.number") }
                .help("Show the largest files anywhere under this folder (⌘L)")
        }
    }
}

/// The path from the scan root to the focus; click a segment to jump there.
struct Breadcrumb: View {
    let model: BrowserModel
    private static let maxShown = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(visibleCrumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if let crumb {
                    let isLast = crumb.id == model.breadcrumb.last?.id
                    Button(crumb.name) { model.go(to: crumb.id) }
                        .buttonStyle(.borderless)
                        .fontWeight(isLast ? .semibold : .regular)
                        .foregroundStyle(isLast ? .primary : .secondary)
                        .lineLimit(1)
                        .disabled(isLast)
                        .help(crumb.name)
                } else {
                    Menu("…") {
                        ForEach(hiddenCrumbs) { crumb in
                            Button(crumb.name) { model.go(to: crumb.id) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 420, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }

    /// The root, "…" for the middle, then the last few; nil marks the "…".
    private var visibleCrumbs: [BrowserModel.Crumb?] {
        let crumbs = model.breadcrumb
        guard crumbs.count > Self.maxShown else { return crumbs }
        return [crumbs[0], nil] + crumbs.suffix(Self.maxShown - 2)
    }

    private var hiddenCrumbs: [BrowserModel.Crumb] {
        let crumbs = model.breadcrumb
        guard crumbs.count > Self.maxShown else { return [] }
        return Array(crumbs[1 ..< crumbs.count - (Self.maxShown - 2)])
    }
}
