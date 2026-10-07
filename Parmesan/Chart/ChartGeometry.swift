import Foundation

/// What a chart segment shows: a node, or a "N smaller items" group of a folder's small children.
struct SegmentInfo: Sendable, Hashable {
    var name: String
    var size: UInt64
    var shareOfParent: Double
    var shareOfFocus: Double
    var items: UInt32
    var kind: NodeKind
    var dominant: NodeKind
    var ageTime: Int32
    var flags: NodeFlags
    /// A group of small items (`otherCount` of them) rather than a single node.
    var isOther: Bool = false
    var otherCount: Int = 0

    var isDirectory: Bool { !isOther && kind.isDirectory }

    static func node(_ s: borrowing FileTreeStorage, _ id: NodeID, parentSize: UInt64, focusSize: UInt64,
                     _ mode: SizeMode) -> SegmentInfo {
        let i = Int(id)
        let size = s.size(id, mode)
        return SegmentInfo(name: s.name(id), size: size,
                           shareOfParent: parentSize > 0 ? Double(size) / Double(parentSize) : 0,
                           shareOfFocus: focusSize > 0 ? Double(size) / Double(focusSize) : 0,
                           items: s.items[i], kind: s.kind[i], dominant: s.dominant[i], ageTime: s.ageTime[i],
                           flags: s.flags[i])
    }

    static func smaller(count: Int, size: UInt64, parentSize: UInt64, focusSize: UInt64) -> SegmentInfo {
        SegmentInfo(name: String(localized: "\(count) smaller items"), size: size,
                    shareOfParent: parentSize > 0 ? Double(size) / Double(parentSize) : 0,
                    shareOfFocus: focusSize > 0 ? Double(size) / Double(focusSize) : 0,
                    items: UInt32(count), kind: .other, dominant: .other, ageTime: 0, flags: [],
                    isOther: true, otherCount: count)
    }
}

// MARK: - Sunburst

struct ArcSegment: Sendable {
    /// The node, or for a smaller-items group, the folder whose children it groups.
    var node: NodeID
    /// 1 is the ring around the center disc.
    var ring: Int
    /// Radians, 0 at 12 o'clock, increasing clockwise.
    var start: Double
    var end: Double
    /// Index of the segment one ring in, or -1 on the first ring.
    var parent: Int
    /// Whether the next ring shows this folder's children.
    var hasChildren: Bool
    var info: SegmentInfo
}

struct SunburstGeometry: Sendable {
    var focus: NodeID
    var focusInfo: NodeInfo
    var rings: Int
    var mode: SizeMode
    /// The scan root's size, for "% of root" in tooltips.
    var rootSize: UInt64
    var segments: [ArcSegment]
    /// Segment indices per ring (index 0 = ring 1), sorted by start angle.
    var byRing: [[Int]]

    /// The segment covering `angle` on `ring`, by binary search.
    func segment(atAngle angle: Double, ring: Int) -> Int? {
        guard ring >= 1, ring <= byRing.count else { return nil }
        let list = byRing[ring - 1]
        var low = 0, high = list.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let segment = segments[list[mid]]
            if angle < segment.start {
                high = mid - 1
            } else if angle >= segment.end {
                low = mid + 1
            } else {
                return list[mid]
            }
        }
        return nil
    }

    /// The segment and the ones it sits in, innermost last.
    func lineage(of index: Int) -> [Int] {
        var result: [Int] = []
        var current = index
        while current >= 0 {
            result.append(current)
            current = segments[current].parent
        }
        return result.reversed()
    }
}

// MARK: - Treemap

struct RectSegment: Sendable {
    var node: NodeID
    /// 1 for the focus's children.
    var depth: Int
    var rect: CGRect
    /// The label strip at the top of a folder that has room for one.
    var header: CGRect?
    var parent: Int
    var children: [Int] = []
    var info: SegmentInfo
}

struct TreemapGeometry: Sendable {
    var focus: NodeID
    var focusInfo: NodeInfo
    var size: CGSize
    var mode: SizeMode
    var rootSize: UInt64
    var segments: [RectSegment]
    /// The focus's children.
    var roots: [Int]

    /// The deepest segment containing `point`, found by descending from the top level.
    func segment(at point: CGPoint) -> Int? {
        var candidates = roots
        var found: Int?
        while let hit = candidates.first(where: { segments[$0].rect.contains(point) }) {
            found = hit
            candidates = segments[hit].children
        }
        return found
    }

    func lineage(of index: Int) -> [Int] {
        var result: [Int] = []
        var current = index
        while current >= 0 {
            result.append(current)
            current = segments[current].parent
        }
        return result.reversed()
    }
}
