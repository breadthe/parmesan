import Foundation

/// Sunburst geometry for a focus folder: each ring holds the children of the ring inside it, each arc's
/// angle proportional to its size (see specs.md → Visualization, Chart Layout Engines). A pure function of
/// the tree, so it runs off the main actor and is easy to test.
enum SunburstLayout {
    /// Arcs narrower than this are merged into one "smaller items" arc per folder.
    static let defaultMinAngle = 0.6 * Double.pi / 180

    static func layout(_ s: borrowing FileTreeStorage, focus: NodeID, rings: Int, mode: SizeMode,
                       minAngle: Double = defaultMinAngle) -> SunburstGeometry {
        let focusSize = s.size(focus, mode)
        var segments: [ArcSegment] = []
        var byRing = [[Int]](repeating: [], count: max(rings, 0))

        // Breadth-first, so each ring's arcs come out in angle order.
        struct Pending {
            var node: NodeID
            var ring: Int
            var start: Double
            var span: Double
            var parent: Int
        }
        var queue = [Pending(node: focus, ring: 1, start: 0, span: 2 * .pi, parent: -1)]
        var head = 0
        while head < queue.count {
            let item = queue[head]
            head += 1
            guard item.ring <= rings else { continue }
            let total = s.size(item.node, mode)
            guard total > 0 else { continue }
            var angle = item.start
            var otherSize: UInt64 = 0
            var otherCount = 0
            for child in s.sortedChildren(item.node, mode) {
                let size = s.size(child, mode)
                guard size > 0 else { continue }
                let span = item.span * Double(size) / Double(total)
                if span < minAngle || otherCount > 0 {
                    // Sorted largest first: everything from here on is smaller still.
                    otherSize += size
                    otherCount += 1
                    continue
                }
                let canDescend = s.isDirectory(child) && item.ring < rings
                let index = segments.count
                segments.append(ArcSegment(
                    node: child, ring: item.ring, start: angle, end: angle + span, parent: item.parent,
                    hasChildren: canDescend && !s.children(child).isEmpty,
                    info: .node(s, child, parentSize: total, focusSize: focusSize, mode)))
                byRing[item.ring - 1].append(index)
                if canDescend {
                    queue.append(Pending(node: child, ring: item.ring + 1, start: angle, span: span, parent: index))
                }
                angle += span
            }
            if otherCount > 0 {
                let span = item.span * Double(otherSize) / Double(total)
                byRing[item.ring - 1].append(segments.count)
                segments.append(ArcSegment(
                    node: item.node, ring: item.ring, start: angle, end: min(angle + span, item.start + item.span),
                    parent: item.parent, hasChildren: false,
                    info: .smaller(count: otherCount, size: otherSize, parentSize: total, focusSize: focusSize)))
            }
        }
        for ring in byRing.indices {
            byRing[ring].sort { segments[$0].start < segments[$1].start }
        }
        return SunburstGeometry(focus: focus, focusInfo: s.info(focus), rings: rings, mode: mode,
                                rootSize: s.size(0, mode), segments: segments, byRing: byRing)
    }
}
