import Darwin
import Foundation
import os
import Synchronization

/// Settings → Scanning, captured when a scan starts.
struct ScanOptions: Sendable {
    var crossVolumes = false
    var countHardLinksOnce = true
    var includeHidden = true
    var skipList = SkipList([])
    /// Worker threads; nil picks from the core count and whether the volume is local.
    var threadCount: Int?
}

struct ScanProgress: Sendable, Equatable {
    var items: Int = 0
    var allocated: UInt64 = 0
    var logical: UInt64 = 0
    var currentPath: String = ""
    var elapsed: TimeInterval = 0
    var isFinished = false
    var wasCancelled = false

    func bytes(_ mode: SizeMode) -> UInt64 { mode == .allocated ? allocated : logical }
}

/// Walks a folder tree on a pool of threads and fills a `FileTree` as it goes (see specs.md → DiskScanner).
///
/// Each job is one directory: the worker reads all of its entries with `getattrlistbulk`, then commits
/// them to the tree in one step, which adds their sizes to every ancestor, so partial results are always
/// consistent. Subfolders become new jobs. Stopping is cooperative: unfinished folders keep their
/// `incomplete` flag. A folder that can't be read never stops the scan.
final class DiskScanner: Sendable {
    let tree: FileTree
    /// Where this scan started: 0 for a full scan, or the folder being rescanned.
    let scanRoot: NodeID
    let rootPath: String

    private let options: ScanOptions
    private let policy: VolumePolicy
    private let queue = WorkQueue()
    private let cancelled = Atomic<Bool>(false)
    private let hardLinks = Mutex<Set<HardLinkKey>>([])
    private let currentPath = Mutex<String>("")
    private let state = Mutex(RunState())
    private static let log = Logger(subsystem: "com.breadthe.Parmesan", category: "Scanner")

    private struct HardLinkKey: Hashable {
        var device: Int32
        var fileID: UInt64
    }

    private struct RunState {
        var started: ContinuousClock.Instant?
        var finished: ContinuousClock.Instant?
        var liveWorkers = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private struct Job {
        var node: NodeID
        var path: String
    }

    /// A new scan of `url`, with a fresh tree.
    convenience init(url: URL, options: ScanOptions = ScanOptions()) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path
        var st = stat()
        let mtime = lstat(path, &st) == 0 ? Int32(clamping: st.st_mtimespec.tv_sec) : 0
        let name = Self.displayName(for: resolved)
        let tree = FileTree(FileTreeStorage(rootPath: path, rootName: name, rootKind: KindClassifier.kind(forDirectoryNamed: resolved.lastPathComponent), rootMtime: mtime))
        self.init(tree: tree, node: 0, options: options)
    }

    /// A scan of `node` in an existing tree. For a rescan, call `FileTreeStorage.resetForRescan` first.
    init(tree: FileTree, node: NodeID, options: ScanOptions = ScanOptions()) {
        self.tree = tree
        scanRoot = node
        let treeRoot = tree.rootPath
        rootPath = tree.read { $0.path(node) }
        self.options = options
        policy = VolumePolicy(rootPath: treeRoot, crossVolumes: options.crossVolumes)
    }

    static func displayName(for url: URL) -> String {
        if url.path == "/" {
            return (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "/"
        }
        if let values = try? url.resourceValues(forKeys: [.isVolumeKey, .volumeLocalizedNameKey]), values.isVolume == true,
           let name = values.volumeLocalizedName {
            return name
        }
        return url.lastPathComponent
    }

    // MARK: - Running

    func start() {
        let threads = options.threadCount ?? defaultThreadCount()
        state.withLock {
            $0.started = .now
            $0.liveWorkers = threads
        }
        queue.add([Job(node: scanRoot, path: rootPath)])
        for index in 0 ..< threads {
            let thread = Thread { [self] in work() }
            thread.name = "Parmesan scanner \(index)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    /// Stops the scan; what's been read so far stays in the tree.
    func cancel() {
        cancelled.store(true, ordering: .relaxed)
        queue.cancel()
    }

    var isFinished: Bool { state.withLock { $0.finished != nil } }
    var wasCancelled: Bool { cancelled.load(ordering: .relaxed) }

    func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            let done = state.withLock { state in
                if state.finished != nil { return true }
                state.waiters.append(continuation)
                return false
            }
            if done { continuation.resume() }
        }
    }

    /// Runs the whole scan and returns when it's done (for tests and the command-line mode).
    func run() async {
        start()
        await waitUntilFinished()
    }

    func progress() -> ScanProgress {
        let (items, allocated, logical) = tree.read { s in
            (Int(s.items[Int(scanRoot)]), s.allocated[Int(scanRoot)], s.logical[Int(scanRoot)])
        }
        let (started, finished) = state.withLock { ($0.started, $0.finished) }
        let elapsed = started.map { start in
            let duration = (finished ?? .now) - start
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        } ?? 0
        return ScanProgress(items: items, allocated: allocated, logical: logical,
                            currentPath: currentPath.withLock { $0 }, elapsed: elapsed,
                            isFinished: finished != nil, wasCancelled: wasCancelled)
    }

    /// Progress snapshots about ten times a second, ending with one where `isFinished` is true.
    func progressUpdates(every interval: Duration = .milliseconds(100)) -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let snapshot = progress()
                    continuation.yield(snapshot)
                    if snapshot.isFinished { break }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func defaultThreadCount() -> Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let isLocal = (try? URL(fileURLWithPath: rootPath).resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? true
        // Rotational and network volumes don't like many concurrent readers.
        return isLocal ? min(max(cores * 2, 4), 16) : 3
    }

    // MARK: - Workers

    private func work() {
        let reader = DirectoryReader()
        var raw: [RawEntry] = []
        while let job = queue.take() {
            process(job, reader: reader, raw: &raw)
            queue.done()
        }
        let last = state.withLock { state in
            state.liveWorkers -= 1
            return state.liveWorkers == 0
        }
        if last { finish() }
    }

    private func finish() {
        let root = scanRoot
        let stopped = wasCancelled
        tree.write { storage in
            if stopped { storage.finalizeIncomplete(under: root) }
            if root != 0 { storage.refreshAncestors(of: root) }
        }
        let waiters = state.withLock { state in
            state.finished = .now
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    private func process(_ job: Job, reader: DirectoryReader, raw: inout [RawEntry]) {
        let root = scanRoot
        let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            let error = errno
            let isRestricted = error == EACCES || error == EPERM
            if !isRestricted { Self.log.error("Can't open \(job.path, privacy: .public): \(String(cString: strerror(error)), privacy: .public)") }
            tree.write { $0.markUnreadable(job.node, restricted: isRestricted, scanRoot: root) }
            return
        }
        defer { close(fd) }

        var st = stat()
        if fstat(fd, &st) == 0, !policy.allows(device: st.st_dev) {
            tree.write { $0.markOtherVolume(job.node, scanRoot: root) }
            return
        }
        currentPath.withLock { $0 = job.path }

        let error = reader.read(fd, path: job.path, device: st.st_dev, into: &raw)
        if error != 0, raw.isEmpty {
            let isRestricted = error == EACCES || error == EPERM
            if !isRestricted { Self.log.error("Can't read \(job.path, privacy: .public): \(String(cString: strerror(error)), privacy: .public)") }
            tree.write { $0.markUnreadable(job.node, restricted: isRestricted, scanRoot: root) }
            return
        }
        if cancelled.load(ordering: .relaxed) { return }

        let base = job.path == "/" ? "/" : job.path + "/"
        var entries: [ScannedEntry] = []
        entries.reserveCapacity(raw.count)
        var subfolderPaths: [String] = []
        for item in raw {
            if !options.includeHidden, item.name.hasPrefix(".") || item.flags & UInt32(UF_HIDDEN) != 0 { continue }
            let path = base + item.name
            if !options.skipList.isEmpty, options.skipList.skips(name: item.name, path: path) { continue }
            let mtime = Int32(clamping: item.mtime)
            switch item.type {
            case .directory:
                if policy.skips(path) { continue }
                let kind = KindClassifier.kind(forDirectoryNamed: item.name)
                var flags: NodeFlags = kind == .package ? [.package] : []
                var willScan = true
                if item.isMountPoint, !policy.entersMountPoint(path) {
                    flags.insert(.otherVolume)
                    willScan = false
                }
                if willScan { subfolderPaths.append(path) }
                entries.append(ScannedEntry(name: item.name, kind: kind, flags: flags, allocated: 0, logical: 0,
                                            mtime: mtime, willScan: willScan))
            case .file, .symlink, .other:
                var flags: NodeFlags = item.type == .symlink ? [.symlink] : []
                if item.flags & UInt32(SF_DATALESS) != 0 { flags.insert(.dataless) }
                var allocated = item.allocated
                var logical = item.logical
                // see specs.md → Size accounting rules: count each inode once per scan.
                if options.countHardLinksOnce, item.type == .file, item.linkCount > 1 {
                    let key = HardLinkKey(device: item.device, fileID: item.fileID)
                    let isFirst = hardLinks.withLock { $0.insert(key).inserted }
                    if !isFirst {
                        flags.insert(.hardLinkDuplicate)
                        allocated = 0
                        logical = 0
                    }
                }
                let kind = item.type == .symlink ? NodeKind.other : KindClassifier.kind(forFileNamed: item.name)
                entries.append(ScannedEntry(name: item.name, kind: kind, flags: flags, allocated: allocated,
                                            logical: logical, mtime: mtime, willScan: false))
            }
        }

        let subfolders = tree.write { $0.commit(entries, into: job.node, scanRoot: root) }
        queue.add(zip(subfolders, subfolderPaths).map { Job(node: $0, path: $1) })
    }

    // MARK: - Work queue

    /// A LIFO stack of directory jobs shared by the workers (depth-first keeps it small). `outstanding`
    /// counts queued plus in-progress jobs; when it reaches zero, everyone's done.
    private final class WorkQueue: @unchecked Sendable {
        private let condition = NSCondition()
        private var jobs: [Job] = []
        private var outstanding = 0
        private var isCancelled = false

        func add(_ new: [Job]) {
            guard !new.isEmpty else { return }
            condition.lock()
            jobs.append(contentsOf: new)
            outstanding += new.count
            if new.count == 1 { condition.signal() } else { condition.broadcast() }
            condition.unlock()
        }

        /// The next job, or nil once everything's done or the scan was stopped.
        func take() -> Job? {
            condition.lock()
            defer { condition.unlock() }
            while jobs.isEmpty, outstanding > 0, !isCancelled {
                condition.wait()
            }
            if isCancelled || jobs.isEmpty { return nil }
            return jobs.removeLast()
        }

        func done() {
            condition.lock()
            outstanding -= 1
            if outstanding == 0 { condition.broadcast() }
            condition.unlock()
        }

        func cancel() {
            condition.lock()
            isCancelled = true
            condition.broadcast()
            condition.unlock()
        }
    }
}
