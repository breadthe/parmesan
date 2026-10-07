import Darwin
import Foundation
@testable import Parmesan

/// A throwaway folder tree in a temp dir, filled with real (non-sparse) files.
struct TestTree {
    let root: URL

    init() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("parmesan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        root = temp.resolvingSymlinksInPath()
    }

    var path: String { root.path }

    func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    func dir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: url(relative), withIntermediateDirectories: true)
    }

    /// Writes `bytes` of real data, so the file allocates that much (rounded up to the block size).
    func file(_ relative: String, bytes: Int, modified: Date? = nil) throws {
        try dir((relative as NSString).deletingLastPathComponent)
        try Data(repeating: 0x61, count: bytes).write(to: url(relative))
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url(relative).path)
        }
    }

    func hardLink(_ existing: String, _ new: String) throws {
        try dir((new as NSString).deletingLastPathComponent)
        try FileManager.default.linkItem(at: url(existing), to: url(new))
    }

    func symlink(_ relative: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: url(relative).path, withDestinationPath: destination)
    }

    func chmod(_ relative: String, _ mode: mode_t) {
        _ = Darwin.chmod(url(relative).path, mode)
    }

    /// Allocated bytes of a file, the way `du` counts it.
    func allocated(_ relative: String) -> UInt64 {
        var st = stat()
        lstat(url(relative).path, &st)
        return UInt64(st.st_blocks) * 512
    }

    func scan(_ options: ScanOptions = ScanOptions()) async -> DiskScanner {
        let scanner = DiskScanner(url: root, options: options)
        await scanner.run()
        return scanner
    }

    func remove() {
        // Restricted folders made by tests need their permissions back before they can be deleted.
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            while let item = enumerator.nextObject() as? String {
                _ = Darwin.chmod(url(item).path, 0o755)
            }
        }
        _ = Darwin.chmod(path, 0o755)
        try? FileManager.default.removeItem(at: root)
    }
}

extension FileTreeStorage {
    /// Every folder's size equals the sum of its children's: totals are internally consistent.
    func isConsistent(_ mode: SizeMode = .allocated) -> Bool {
        for id in 0 ..< NodeID(count) where isDirectory(id) && !isRemoved(id) {
            let sum = children(id).reduce(UInt64(0)) { $0 + size($1, mode) }
            if sum != size(id, mode) { return false }
        }
        return true
    }

    func node(named path: String) -> NodeID? {
        find(path: rootPath + "/" + path)
    }
}
