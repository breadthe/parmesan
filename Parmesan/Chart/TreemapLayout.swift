import Foundation

/// Squarified treemap (Bruls, Huizing & van Wijk) of a focus folder, nested a few levels deep, with a
/// label strip at the top of each folder that has room (see specs.md → Visualization, Chart Layout Engines).
enum TreemapLayout {
    struct Style: Sendable {
        var padding: CGFloat = 2
        var headerHeight: CGFloat = 16
        /// Rectangles smaller than this many points² are merged into one "smaller items" rectangle.
        var minArea: CGFloat = 36
        /// Upper bound on segments, so huge folders stay fast to draw.
        var maxSegments = 6000
    }

    static func layout(_ s: borrowing FileTreeStorage, focus: NodeID, size: CGSize, depth: Int, mode: SizeMode,
                       style: Style = Style()) -> TreemapGeometry {
        let focusSize = s.size(focus, mode)
        let bounds = CGRect(origin: .zero, size: size)
        // Keep the segment count bounded on big windows.
        let minArea = max(style.minArea, bounds.width * bounds.height / CGFloat(style.maxSegments))
        var segments: [RectSegment] = []
        var roots: [Int] = []

        struct Pending {
            var node: NodeID
            var rect: CGRect
            var depth: Int
            var parent: Int
        }
        var queue = [Pending(node: focus, rect: bounds, depth: 1, parent: -1)]
        var head = 0
        while head < queue.count {
            let item = queue[head]
            head += 1
            let total = s.size(item.node, mode)
            let area = item.rect.width * item.rect.height
            guard total > 0, area > 0, segments.count < style.maxSegments else { continue }
            let scale = Double(area) / Double(total)

            var placed: [NodeID] = []
            var values: [Double] = []
            var otherSize: UInt64 = 0
            var otherCount = 0
            for child in s.sortedChildren(item.node, mode) {
                let size = s.size(child, mode)
                guard size > 0 else { continue }
                let value = Double(size) * scale
                if value < Double(minArea) || otherCount > 0 {
                    otherSize += size
                    otherCount += 1
                } else {
                    placed.append(child)
                    values.append(value)
                }
            }
            if otherCount > 0 { values.append(Double(otherSize) * scale) }
            let rects = squarify(values, in: item.rect)

            for (offset, rect) in rects.enumerated() {
                let index = segments.count
                if offset < placed.count {
                    let child = placed[offset]
                    var segment = RectSegment(node: child, depth: item.depth, rect: rect, parent: item.parent,
                                              info: .node(s, child, parentSize: total, focusSize: focusSize, mode))
                    if s.isDirectory(child), item.depth < depth {
                        var inner = rect.insetBy(dx: style.padding, dy: style.padding)
                        if inner.height > style.headerHeight * 2.2, inner.width > 40 {
                            segment.header = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: style.headerHeight)
                            inner = CGRect(x: inner.minX, y: inner.minY + style.headerHeight, width: inner.width,
                                           height: inner.height - style.headerHeight)
                        }
                        if inner.width >= 4, inner.height >= 4 {
                            queue.append(Pending(node: child, rect: inner, depth: item.depth + 1, parent: index))
                        }
                    }
                    segments.append(segment)
                } else {
                    segments.append(RectSegment(
                        node: item.node, depth: item.depth, rect: rect, parent: item.parent,
                        info: .smaller(count: otherCount, size: otherSize, parentSize: total, focusSize: focusSize)))
                }
                if item.parent >= 0 {
                    segments[item.parent].children.append(index)
                } else {
                    roots.append(index)
                }
            }
        }
        return TreemapGeometry(focus: focus, focusInfo: s.info(focus), size: size, mode: mode,
                               rootSize: s.size(0, mode), segments: segments, roots: roots)
    }

    /// Lays out `values` (areas, largest first, summing to the rect's area) as rectangles with aspect
    /// ratios as close to 1 as possible. Rows go along the shorter side of what's left.
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result: [CGRect] = []
        result.reserveCapacity(values.count)
        var remaining = rect
        var index = 0
        let total = values.reduce(0, +)
        // Normalise, in case the values don't quite add up to the area.
        let scale = total > 0 ? Double(rect.width * rect.height) / total : 0
        let areas = values.map { $0 * scale }

        while index < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else {
                result.append(contentsOf: repeatElement(CGRect(origin: remaining.origin, size: .zero), count: areas.count - index))
                break
            }
            var rowEnd = index + 1
            var sum = areas[index]
            var smallest = areas[index]
            var largest = areas[index]
            var worst = worstRatio(sum: sum, smallest: smallest, largest: largest, side: side)
            while rowEnd < areas.count {
                let next = areas[rowEnd]
                let candidate = worstRatio(sum: sum + next, smallest: min(smallest, next), largest: max(largest, next), side: side)
                guard candidate <= worst else { break }
                sum += next
                smallest = min(smallest, next)
                largest = max(largest, next)
                worst = candidate
                rowEnd += 1
            }

            let isLast = rowEnd == areas.count
            if remaining.width >= remaining.height {
                // A column on the left.
                let width = isLast ? remaining.width : CGFloat(sum / Double(remaining.height))
                var y = remaining.minY
                for i in index ..< rowEnd {
                    let height = rowEnd - 1 == i ? remaining.maxY - y : CGFloat(areas[i] / Double(width))
                    result.append(CGRect(x: remaining.minX, y: y, width: width, height: height))
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // A row along the top.
                let height = isLast ? remaining.height : CGFloat(sum / Double(remaining.width))
                var x = remaining.minX
                for i in index ..< rowEnd {
                    let width = rowEnd - 1 == i ? remaining.maxX - x : CGFloat(areas[i] / Double(height))
                    result.append(CGRect(x: x, y: remaining.minY, width: width, height: height))
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(0, remaining.height - height))
            }
            index = rowEnd
        }
        return result
    }

    private static func worstRatio(sum: Double, smallest: Double, largest: Double, side: Double) -> Double {
        let side2 = side * side
        let sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }
}
