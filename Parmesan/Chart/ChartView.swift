import AppKit
import SwiftUI

/// The chart pane: sunburst or treemap of the focus, with hover tooltips, click to select, double-click to
/// drill in or open, a context menu, and VoiceOver access to the segments (see specs.md → Visualization).
struct ChartView: View {
    @Bindable var model: BrowserModel
    @Environment(\.chartPalette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(PreferenceKey.showLabels) private var showLabels = true
    @State private var hovered: Int?
    @State private var isHoveringCenter = false
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if model.isScanning {
                    TimelineView(.animation(minimumInterval: 1.0 / 8)) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        chart(pulse: 0.5 - 0.5 * cos(phase * 2 * .pi))
                    }
                } else {
                    chart(pulse: 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverPoint = point
                    updateHover(point, size: geo.size)
                case .ended:
                    hovered = nil
                    isHoveringCenter = false
                }
            }
            .gesture(SpatialTapGesture().onEnded { click($0.location, size: geo.size) })
            .contextMenu { ItemActionsMenu(model: model, ids: contextTargets) }
            .overlay(alignment: .topLeading) { tooltip(in: geo.size) }
            .onChange(of: geo.size, initial: true) { _, size in model.chartSize = size }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            model.quickLook()
            return .handled
        }
        .onKeyPress(.delete) {
            model.goUp()
            return .handled
        }
        .onKeyPress(.return) {
            model.drillIntoSelection()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.chartMode == .sunburst ? "Sunburst chart" : "Treemap chart")
        .accessibilityChildren { accessibleSegments }
    }

    @ViewBuilder
    private func chart(pulse: Double) -> some View {
        let style = ChartStyle(
            palette: palette, colorMode: model.colorMode, hovered: hovered, isHoveringCenter: isHoveringCenter,
            selection: model.selection, showLabels: showLabels, differentiateWithoutColor: differentiateWithoutColor,
            increaseContrast: contrast == .increased, pulse: pulse,
            separator: Color(nsColor: .controlBackgroundColor), centerFill: Color(nsColor: .windowBackgroundColor))
        switch model.chartMode {
        case .sunburst:
            if let geometry = model.sunburst {
                SunburstCanvas(geometry: geometry, style: style)
                    .id(geometry.focus)
                    .transition(zoomTransition)
            } else {
                ProgressView()
            }
        case .treemap:
            if let geometry = model.treemap {
                TreemapCanvas(geometry: geometry, style: style)
                    .id(geometry.focus)
                    .transition(zoomTransition)
            } else {
                ProgressView()
            }
        }
    }

    /// Drilling in grows the new chart out of the middle; going up shrinks into it.
    private var zoomTransition: AnyTransition {
        switch model.zoom {
        case .none:
            .opacity
        case .zoomIn:
            .asymmetric(insertion: .scale(scale: 0.55).combined(with: .opacity),
                        removal: .scale(scale: 1.5).combined(with: .opacity))
        case .zoomOut:
            .asymmetric(insertion: .scale(scale: 1.5).combined(with: .opacity),
                        removal: .scale(scale: 0.55).combined(with: .opacity))
        }
    }

    // MARK: - Hit testing

    private enum Target {
        case center
        case segment(Int)
        case none
    }

    private func target(at point: CGPoint, size: CGSize) -> Target {
        switch model.chartMode {
        case .sunburst:
            guard let geometry = model.sunburst else { return .none }
            switch SunburstFrame(size: size, rings: geometry.rings).hit(point, rings: geometry.rings) {
            case .center: return .center
            case .ring(let ring, let angle):
                return geometry.segment(atAngle: angle, ring: ring).map(Target.segment) ?? .none
            case .outside: return .none
            }
        case .treemap:
            return model.treemap?.segment(at: point).map(Target.segment) ?? .none
        }
    }

    private func updateHover(_ point: CGPoint, size: CGSize) {
        switch target(at: point, size: size) {
        case .center:
            hovered = nil
            isHoveringCenter = true
        case .segment(let index):
            hovered = index
            isHoveringCenter = false
        case .none:
            hovered = nil
            isHoveringCenter = false
        }
    }

    /// A segment of whichever chart is showing.
    private struct Segment {
        var node: NodeID
        var info: SegmentInfo
    }

    private func segment(_ index: Int) -> Segment? {
        switch model.chartMode {
        case .sunburst:
            guard let geometry = model.sunburst, geometry.segments.indices.contains(index) else { return nil }
            return Segment(node: geometry.segments[index].node, info: geometry.segments[index].info)
        case .treemap:
            guard let geometry = model.treemap, geometry.segments.indices.contains(index) else { return nil }
            return Segment(node: geometry.segments[index].node, info: geometry.segments[index].info)
        }
    }

    private func click(_ point: CGPoint, size: CGSize) {
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        let modifiers = NSEvent.modifierFlags
        switch target(at: point, size: size) {
        case .center:
            model.goUp()
        case .segment(let index):
            guard let hit = segment(index) else { return }
            if clicks >= 2 {
                // A "smaller items" group drills into the folder it belongs to.
                model.activate(hit.node)
            } else if !hit.info.isOther {
                model.select(hit.node, extending: modifiers.contains(.command) || modifiers.contains(.shift))
            }
        case .none:
            model.selection = []
        }
    }

    /// The hovered segment, or the whole selection if the hovered segment is part of it.
    private var contextTargets: [NodeID] {
        guard let hovered, let hit = segment(hovered), !hit.info.isOther else {
            return model.selection.sorted()
        }
        return model.selection.contains(hit.node) ? model.selection.sorted() : [hit.node]
    }

    // MARK: - Tooltip

    @ViewBuilder
    private func tooltip(in size: CGSize) -> some View {
        if let hovered, let info = segment(hovered)?.info {
            tooltipCard(name: info.name, size: info.size, shareOfFocus: info.shareOfFocus, items: info.items,
                        isDirectory: info.isDirectory || info.isOther, flags: info.flags, in: size)
        } else if isHoveringCenter, let focus = model.focusInfo {
            tooltipCard(name: focus.name, size: focus.size(model.sizeMode), shareOfFocus: 1, items: focus.items,
                        isDirectory: true, flags: focus.flags, hint: model.canGoUp ? String(localized: "Click to go up") : nil, in: size)
        }
    }

    private func tooltipCard(name: String, size bytes: UInt64, shareOfFocus: Double, items: UInt32, isDirectory: Bool,
                             flags: NodeFlags, hint: String? = nil, in size: CGSize) -> some View {
        let rootSize = (model.chartMode == .sunburst ? model.sunburst?.rootSize : model.treemap?.rootSize) ?? 0
        let shareOfRoot = rootSize > 0 ? Double(bytes) / Double(rootSize) : 0
        let width: CGFloat = 240
        let x = hoverPoint.x + 16 + width > size.width ? hoverPoint.x - width - 12 : hoverPoint.x + 16
        let y = min(hoverPoint.y + 16, max(0, size.height - 96))
        return VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.headline).lineLimit(2)
            Text(Format.size(bytes)).monospacedDigit()
            Text("\(Format.percent(shareOfFocus)) of this folder · \(Format.percent(shareOfRoot)) of the scan")
                .foregroundStyle(.secondary)
            if isDirectory, items > 0 {
                Text("\(Format.count(Int(items))) items").foregroundStyle(.secondary)
            }
            if flags.contains(.restricted) {
                Label("Restricted: not counted", systemImage: "lock.fill").foregroundStyle(.orange)
            } else if flags.contains(.incomplete) {
                Label("Still scanning", systemImage: "hourglass").foregroundStyle(.secondary)
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(.tertiary) }
        }
        .font(.callout)
        .padding(10)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .offset(x: max(0, x), y: max(0, y))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - VoiceOver

    /// Each segment as an element, e.g. "Developer, folder, 48.2 GB, 31 percent", with the item actions.
    @ViewBuilder
    private var accessibleSegments: some View {
        let segments: [(Int, NodeID, SegmentInfo)] = switch model.chartMode {
        case .sunburst: (model.sunburst?.segments ?? []).enumerated().map { ($0.offset, $0.element.node, $0.element.info) }
        case .treemap: (model.treemap?.segments ?? []).enumerated().map { ($0.offset, $0.element.node, $0.element.info) }
        }
        ForEach(segments.prefix(400), id: \.0) { _, node, info in
            Rectangle()
                .accessibilityLabel(model.accessibilityDescription(info))
                .accessibilityAddTraits(model.selection.contains(node) && !info.isOther ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { if !info.isOther { model.select(node) } }
                .accessibilityAction(named: "Drill In") { model.activate(node) }
                .accessibilityAction(named: "Reveal in Finder") { model.revealInFinder([node]) }
                .accessibilityAction(named: "Open in Terminal") { model.openInTerminal([node]) }
                .accessibilityAction(named: "Quick Look") { model.quickLook([node]) }
                .accessibilityAction(named: "Get Info") { model.getInfo([node]) }
                .accessibilityAction(named: "Copy Path") { model.copyPaths([node]) }
                .accessibilityAction(named: "Move to Trash") { model.requestTrash([node]) }
        }
    }
}
