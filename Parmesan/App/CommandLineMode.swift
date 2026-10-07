import Darwin
import Foundation

/// `Parmesan.app/Contents/MacOS/Parmesan --scan <folder> [--top N] [--logical] [--cross-volumes]
/// [--threads N]`: scans without any UI, prints totals and the largest folders, then exits. Used to
/// benchmark the scanner and check it against `du -sk` (see specs.md → Milestones, M0).
enum CommandLineMode {
    static var isRequested: Bool { CommandLine.arguments.contains("--scan") }

    static func run() -> Never {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        guard let path = value(after: "--scan") else {
            print("usage: Parmesan --scan <folder> [--top N] [--logical] [--cross-volumes] [--threads N]")
            exit(2)
        }
        let top = value(after: "--top").flatMap(Int.init) ?? 20
        let mode: SizeMode = args.contains("--logical") ? .logical : .allocated
        var options = ScanOptions()
        options.crossVolumes = args.contains("--cross-volumes")
        options.threadCount = value(after: "--threads").flatMap(Int.init)

        let scanner = DiskScanner(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), options: options)
        scanner.start()
        while !scanner.isFinished { usleep(20_000) }
        let progress = scanner.progress()

        let (rows, restricted, memory, nodes) = scanner.tree.read { s in
            var heap = MinHeap<NodeID>(capacity: top) { s.size($0, mode) < s.size($1, mode) }
            for id in 1 ..< NodeID(s.count) where s.isDirectory(id) && !s.isRemoved(id) {
                heap.insert(id)
            }
            let rows = heap.sortedDescending().map { (s.path($0), s.size($0, mode)) }
            return (rows, s.restricted.count, s.approximateMemory, s.count)
        }
        print("\(scanner.rootPath)")
        print("\(progress.items) items, \(progress.bytes(mode)) bytes (\(Format.size(progress.bytes(mode))), \(mode.rawValue)) in \(Format.duration(progress.elapsed))")
        print("\(restricted) restricted folders; \(nodes) nodes, ~\(memory / max(nodes, 1)) bytes/node")
        print("du-style KiB: \(progress.bytes(mode) / 1024)")
        print("")
        for (path, size) in rows {
            print(String(format: "%12@  %@", Format.size(size), path))
        }
        exit(0)
    }
}
