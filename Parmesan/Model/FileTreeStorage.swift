import Foundation

/// One scanned file or folder, as handed to the tree by the scanner.
struct ScannedEntry: Sendable {
    var name: String
    var kind: NodeKind
    var flags: NodeFlags
    var allocated: UInt64
    var logical: UInt64
    var mtime: Int32
    /// A folder the scanner will enumerate next (it starts out incomplete).
    var willScan: Bool
}

/// A read-only copy of one node's fields, for the UI.
struct NodeInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var parent: NodeID
    var name: String
    var allocated: UInt64
    var logical: UInt64
    /// Recursive count of everything below a folder; 0 for files.
    var items: UInt32
    var mtime: Int32
    /// Size-weighted modification time of a folder's contents (a file's own mtime); drives By Age.
    var ageTime: Int32
    var kind: NodeKind
    /// The kind that takes the most space in a folder (a file's own kind); drives By Kind.
    var dominant: NodeKind
    var flags: NodeFlags

    var isDirectory: Bool { kind.isDirectory }
    var modified: Date { Date(timeIntervalSince1970: TimeInterval(mtime)) }

    func size(_ mode: SizeMode) -> UInt64 { mode == .allocated ? allocated : logical }
}

/// The scanned tree as parallel arrays indexed by `NodeID` (see specs.md → Model (memory-efficient tree)).
///
/// Node 0 is the scan root. A folder's children are appended in one batch when it's enumerated, so they
/// sit next to each other: `firstChild ..< firstChild + childCount`. Children always get higher IDs than
/// their parent, so walking IDs backwards visits every folder after all of its descendants. Paths aren't
/// stored; they're rebuilt by walking parents.
struct FileTreeStorage: Sendable {
    static let noParent = NodeID.max

    /// The scan root's POSIX path, and the name shown for it (the volume name for `/`).
    let rootPath: String
    let rootName: String

    private(set) var parent: [NodeID] = []
    private(set) var firstChild: [NodeID] = []
    private(set) var childCount: [UInt32] = []
    private(set) var nameOffset: [UInt32] = []
    private(set) var allocated: [UInt64] = []
    private(set) var logical: [UInt64] = []
    private(set) var items: [UInt32] = []
    private(set) var mtime: [Int32] = []
    private(set) var ageTime: [Int32] = []
    private(set) var kind: [NodeKind] = []
    private(set) var dominant: [NodeKind] = []
    private(set) var flags: [NodeFlags] = []
    /// Scan bookkeeping, only for folders still being scanned: how many of the folder itself and its
    /// subfolders are still to be enumerated. Empty once a scan is done.
    private var pending: [NodeID: UInt32] = [:]
    /// Names as UTF-8, each prefixed with its length (2 bytes, little-endian).
    private var names: [UInt8] = []

    /// Folders that couldn't be read, in the order they were found.
    private(set) var restricted: [NodeID] = []
    /// Bumped on every change, so the UI knows when to redraw.
    private(set) var version: UInt64 = 0

    var count: Int { parent.count }

    init(rootPath: String, rootName: String, rootKind: NodeKind = .folder, rootMtime: Int32 = 0) {
        self.rootPath = rootPath
        self.rootName = rootName
        append(parent: Self.noParent, name: rootName, kind: rootKind, flags: [.incomplete], allocated: 0, logical: 0,
               mtime: rootMtime)
        pending[0] = 1
    }

    // MARK: - Reading

    func name(_ id: NodeID) -> String {
        let offset = Int(nameOffset[Int(id)])
        let length = Int(names[offset]) | Int(names[offset + 1]) << 8
        return names.withUnsafeBufferPointer { buffer in
            String(decoding: UnsafeBufferPointer(rebasing: buffer[(offset + 2) ..< (offset + 2 + length)]), as: UTF8.self)
        }
    }

    func path(_ id: NodeID) -> String {
        var components: [String] = []
        var node = id
        while node != 0 {
            components.append(name(node))
            node = parent[Int(node)]
        }
        guard !components.isEmpty else { return rootPath }
        let base = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return base + components.reversed().joined(separator: "/")
    }

    func url(_ id: NodeID) -> URL {
        URL(fileURLWithPath: path(id), isDirectory: kind[Int(id)].isDirectory)
    }

    func size(_ id: NodeID, _ mode: SizeMode) -> UInt64 {
        mode == .allocated ? allocated[Int(id)] : logical[Int(id)]
    }

    func isDirectory(_ id: NodeID) -> Bool { kind[Int(id)].isDirectory }

    func isRemoved(_ id: NodeID) -> Bool { flags[Int(id)].contains(.removed) }

    func contains(_ id: NodeID) -> Bool { Int(id) < count }

    func info(_ id: NodeID) -> NodeInfo {
        let i = Int(id)
        return NodeInfo(id: id, parent: parent[i], name: name(id), allocated: allocated[i], logical: logical[i],
                        items: items[i], mtime: mtime[i], ageTime: ageTime[i], kind: kind[i], dominant: dominant[i],
                        flags: flags[i])
    }

    /// The node's current children, skipping trashed ones.
    func children(_ id: NodeID) -> [NodeID] {
        let i = Int(id)
        let start = firstChild[i]
        return (start ..< start + childCount[i]).filter { !flags[Int($0)].contains(.removed) }
    }

    /// The node's children, largest first.
    func sortedChildren(_ id: NodeID, _ mode: SizeMode) -> [NodeID] {
        let sizes = mode == .allocated ? allocated : logical
        return children(id).sorted { sizes[Int($0)] > sizes[Int($1)] }
    }

    /// Root first, ending with `id`.
    func lineage(_ id: NodeID) -> [NodeID] {
        var result: [NodeID] = []
        var node = id
        while node != Self.noParent {
            result.append(node)
            node = parent[Int(node)]
        }
        return result.reversed()
    }

    func isDescendant(_ id: NodeID, of ancestor: NodeID) -> Bool {
        var node = id
        while node != Self.noParent {
            if node == ancestor { return true }
            node = parent[Int(node)]
        }
        return false
    }

    /// Looks a node up by POSIX path, or nil if it's not in the tree (or was trashed).
    func find(path: String) -> NodeID? {
        let base = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path == rootPath || path + "/" == base { return 0 }
        guard path.hasPrefix(base) else { return nil }
        var node: NodeID = 0
        for component in path.dropFirst(base.count).split(separator: "/") {
            guard let next = children(node).first(where: { name($0) == component }) else { return nil }
            node = next
        }
        return node
    }

    /// The `limit` largest files anywhere below `id`, largest first (a bounded min-heap over the subtree).
    func largestFiles(under id: NodeID, limit: Int, _ mode: SizeMode) -> [NodeID] {
        guard limit > 0 else { return [] }
        let sizes = mode == .allocated ? allocated : logical
        var heap = MinHeap<NodeID>(capacity: limit) { sizes[Int($0)] < sizes[Int($1)] }
        var stack = [id]
        while let node = stack.popLast() {
            let i = Int(node)
            let start = firstChild[i]
            for child in start ..< start + childCount[i] {
                let c = Int(child)
                if flags[c].contains(.removed) { continue }
                if kind[c].isDirectory {
                    stack.append(child)
                } else if sizes[c] > 0 {
                    heap.insert(child)
                }
            }
        }
        return heap.sortedDescending()
    }

    // MARK: - Building (scanner)

    @discardableResult
    private mutating func append(parent: NodeID, name: String, kind: NodeKind, flags: NodeFlags, allocated: UInt64,
                                 logical: UInt64, mtime: Int32) -> NodeID {
        let id = NodeID(self.parent.count)
        self.parent.append(parent)
        firstChild.append(0)
        childCount.append(0)
        nameOffset.append(UInt32(names.count))
        var utf8 = Array(name.utf8)
        if utf8.count > Int(UInt16.max) { utf8.removeLast(utf8.count - Int(UInt16.max)) }
        names.append(UInt8(utf8.count & 0xFF))
        names.append(UInt8(utf8.count >> 8))
        names.append(contentsOf: utf8)
        self.allocated.append(allocated)
        self.logical.append(logical)
        items.append(0)
        self.mtime.append(mtime)
        ageTime.append(mtime)
        self.kind.append(kind)
        dominant.append(kind)
        self.flags.append(flags)
        return id
    }

    /// Adds a folder's entries as its children and adds their sizes to every ancestor. Returns the IDs of
    /// the entries marked `willScan`, in entry order. `scanRoot` is where completion stops propagating
    /// (the node a rescan started from; 0 for a full scan).
    mutating func commit(_ entries: [ScannedEntry], into dir: NodeID, scanRoot: NodeID) -> [NodeID] {
        let d = Int(dir)
        firstChild[d] = NodeID(count)
        childCount[d] = UInt32(entries.count)
        var addedAllocated: UInt64 = 0
        var addedLogical: UInt64 = 0
        var toScan: [NodeID] = []
        for entry in entries {
            let id = append(parent: dir, name: entry.name, kind: entry.kind,
                            flags: entry.willScan ? entry.flags.union(.incomplete) : entry.flags,
                            allocated: entry.allocated, logical: entry.logical, mtime: entry.mtime)
            if entry.willScan { pending[id] = 1 }
            addedAllocated += entry.allocated
            addedLogical += entry.logical
            if entry.willScan { toScan.append(id) }
        }
        addToLineage(of: dir, allocated: addedAllocated, logical: addedLogical, items: UInt32(entries.count))
        pending[dir, default: 1] += UInt32(toScan.count)
        finishOne(dir, scanRoot: scanRoot)
        version &+= 1
        return toScan
    }

    /// A folder that couldn't be enumerated: restricted (permission denied) or failed (anything else).
    mutating func markUnreadable(_ dir: NodeID, restricted isRestricted: Bool, scanRoot: NodeID) {
        flags[Int(dir)].insert(isRestricted ? .restricted : .failed)
        if isRestricted { restricted.append(dir) }
        finishOne(dir, scanRoot: scanRoot)
        version &+= 1
    }

    /// A folder found to be on another volume only once opened (firmlinks and the like): not counted.
    mutating func markOtherVolume(_ dir: NodeID, scanRoot: NodeID) {
        flags[Int(dir)].insert(.otherVolume)
        finishOne(dir, scanRoot: scanRoot)
        version &+= 1
    }

    /// After a stopped scan: work out folder aggregates for everything left incomplete, children first.
    mutating func finalizeIncomplete(under scanRoot: NodeID) {
        pending = [:]
        for i in stride(from: count - 1, through: Int(scanRoot), by: -1)
        where flags[i].contains(.incomplete) && isDescendant(NodeID(i), of: scanRoot) {
            updateAggregates(NodeID(i))
        }
        version &+= 1
    }

    private mutating func addToLineage(of id: NodeID, allocated a: UInt64, logical l: UInt64, items n: UInt32) {
        var node = id
        while node != Self.noParent {
            let i = Int(node)
            allocated[i] &+= a
            logical[i] &+= l
            items[i] &+= n
            node = parent[i]
        }
    }

    private mutating func removeFromLineage(of id: NodeID, allocated a: UInt64, logical l: UInt64, items n: UInt32) {
        var node = id
        while node != Self.noParent {
            let i = Int(node)
            allocated[i] = allocated[i] >= a ? allocated[i] - a : 0
            logical[i] = logical[i] >= l ? logical[i] - l : 0
            items[i] = items[i] >= n ? items[i] - n : 0
            node = parent[i]
        }
    }

    /// One unit of a folder's pending work is done; when none is left, the folder is complete, and so on up.
    private mutating func finishOne(_ dir: NodeID, scanRoot: NodeID) {
        var node = dir
        while true {
            let i = Int(node)
            let left = pending[node, default: 1] - 1
            guard left == 0 else {
                pending[node] = left
                return
            }
            pending[node] = nil
            updateAggregates(node)
            flags[i].remove(.incomplete)
            guard node != scanRoot, parent[i] != Self.noParent else { return }
            node = parent[i]
        }
    }

    /// Dominant kind and size-weighted age of a folder, from its children.
    private mutating func updateAggregates(_ dir: NodeID) {
        let d = Int(dir)
        var weights = [UInt64](repeating: 0, count: NodeKind.allCases.count)
        var weightedAge = 0.0
        var total = 0.0
        let start = firstChild[d]
        for child in start ..< start + childCount[d] {
            let c = Int(child)
            if flags[c].contains(.removed) { continue }
            let size = allocated[c]
            weights[Int(dominant[c].rawValue)] &+= size
            weightedAge += Double(ageTime[c]) * Double(size)
            total += Double(size)
        }
        if total > 0 { ageTime[d] = Int32(clamping: Int64(weightedAge / total)) }
        switch kind[d] {
        case .package, .devFolder, .systemFolder:
            dominant[d] = kind[d]
        default:
            if let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0 {
                dominant[d] = NodeKind(rawValue: UInt8(best)) ?? .folder
            } else {
                dominant[d] = kind[d]
            }
        }
    }

    // MARK: - Editing

    /// Takes a trashed node out of the totals, in place (see specs.md → Move to Trash).
    mutating func remove(_ id: NodeID) {
        let i = Int(id)
        guard id != 0, contains(id), !flags[i].contains(.removed) else { return }
        flags[i].insert(.removed)
        removeFromLineage(of: parent[i], allocated: allocated[i], logical: logical[i], items: items[i] + 1)
        restricted = restricted.filter { !isDescendant($0, of: id) }
        var node = parent[i]
        while node != Self.noParent {
            updateAggregates(node)
            node = parent[Int(node)]
        }
        version &+= 1
    }

    /// Empties a folder so it can be scanned again; the new children are appended at the end and the old
    /// ones are left behind, unreachable (see specs.md → Rescan focus).
    mutating func resetForRescan(_ id: NodeID) {
        let i = Int(id)
        guard kind[i].isDirectory else { return }
        removeFromLineage(of: id, allocated: allocated[i], logical: logical[i], items: items[i])
        restricted = restricted.filter { !isDescendant($0, of: id) }
        childCount[i] = 0
        flags[i].subtract([.restricted, .failed, .otherVolume])
        flags[i].insert(.incomplete)
        pending[id] = 1
        version &+= 1
    }

    /// After a rescan of `id` finishes, refresh the aggregates of the folders above it.
    mutating func refreshAncestors(of id: NodeID) {
        var node = parent[Int(id)]
        while node != Self.noParent {
            updateAggregates(node)
            node = parent[Int(node)]
        }
        version &+= 1
    }

    // MARK: - Memory

    /// Approximate bytes used by the arrays, for the "≤ 64 bytes per node" target.
    var approximateMemory: Int {
        count * (MemoryLayout<NodeID>.stride * 2 + MemoryLayout<UInt32>.stride * 3 + MemoryLayout<UInt64>.stride * 2
            + MemoryLayout<Int32>.stride * 2 + 2 + MemoryLayout<NodeFlags>.stride)
            + names.count + pending.count * 16
    }
}

/// A fixed-capacity min-heap that keeps the largest `capacity` elements.
struct MinHeap<Element> {
    private var items: [Element] = []
    private let capacity: Int
    private let less: (Element, Element) -> Bool

    init(capacity: Int, less: @escaping (Element, Element) -> Bool) {
        self.capacity = capacity
        self.less = less
        items.reserveCapacity(capacity)
    }

    mutating func insert(_ element: Element) {
        if items.count < capacity {
            items.append(element)
            siftUp(items.count - 1)
        } else if let smallest = items.first, less(smallest, element) {
            items[0] = element
            siftDown(0)
        }
    }

    func sortedDescending() -> [Element] {
        items.sorted { less($1, $0) }
    }

    private mutating func siftUp(_ index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard less(items[child], items[parent]) else { return }
            items.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(_ index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1, right = left + 1
            var smallest = parent
            if left < items.count, less(items[left], items[smallest]) { smallest = left }
            if right < items.count, less(items[right], items[smallest]) { smallest = right }
            guard smallest != parent else { return }
            items.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
