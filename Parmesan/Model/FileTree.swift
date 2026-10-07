import Foundation
import Synchronization

/// The scanned tree, shared between the scanner's threads and the UI.
///
/// Every access goes through one lock: the scanner holds it briefly per folder it commits, and the UI
/// holds it only long enough to copy out the small slices it shows (the focus's children, chart
/// geometry). See specs.md → Model.
final class FileTree: Sendable {
    private let storage: Mutex<FileTreeStorage>

    init(_ storage: FileTreeStorage) {
        self.storage = Mutex(storage)
    }

    convenience init(rootPath: String, rootName: String, rootMtime: Int32 = 0) {
        self.init(FileTreeStorage(rootPath: rootPath, rootName: rootName, rootMtime: rootMtime))
    }

    func read<Result: Sendable>(_ body: (borrowing FileTreeStorage) -> Result) -> Result {
        storage.withLock { body($0) }
    }

    func write<Result: Sendable>(_ body: (inout FileTreeStorage) -> Result) -> Result {
        storage.withLock { body(&$0) }
    }

    var version: UInt64 { read { $0.version } }
    var rootPath: String { read { $0.rootPath } }
}
