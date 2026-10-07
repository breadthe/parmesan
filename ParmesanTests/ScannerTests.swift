import Darwin
import XCTest
@testable import Parmesan

final class ScannerTests: XCTestCase {
    private var tree: TestTree!

    override func setUpWithError() throws {
        tree = try TestTree()
    }

    override func tearDown() {
        tree.remove()
    }

    func testTotalsMatchAllocatedSizes() async throws {
        try tree.file("a.bin", bytes: 100_000)
        try tree.file("docs/b.pdf", bytes: 30_000)
        try tree.file("docs/deep/c.txt", bytes: 5_000)
        try tree.file("media/d.mov", bytes: 250_000)
        try tree.dir("empty")

        let scanner = await tree.scan()
        let expected = ["a.bin", "docs/b.pdf", "docs/deep/c.txt", "media/d.mov"].reduce(UInt64(0)) { $0 + tree.allocated($1) }
        scanner.tree.read { s in
            XCTAssertEqual(s.size(0, .allocated), expected)
            XCTAssertEqual(s.size(0, .logical), 385_000)
            // a.bin, docs, b.pdf, deep, c.txt, media, d.mov, empty
            XCTAssertEqual(s.items[0], 8)
            XCTAssertTrue(s.isConsistent())
            XCTAssertFalse(s.flags[0].contains(.incomplete))
            XCTAssertEqual(s.kind[Int(s.node(named: "media/d.mov")!)], .video)
            XCTAssertEqual(s.dominant[Int(s.node(named: "media")!)], .video)
        }
        let progress = scanner.progress()
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.allocated, expected)
    }

    func testMatchesDu() async throws {
        for i in 0 ..< 40 {
            try tree.file("dir\(i % 7)/sub\(i % 3)/file\(i).dat", bytes: 1_000 + i * 7_919)
        }
        let scanner = await tree.scan()
        let du = Process()
        du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        du.arguments = ["-sk", tree.path]
        let pipe = Pipe()
        du.standardOutput = pipe
        try du.run()
        du.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let duKiB = Double(output.split(separator: "\t").first.flatMap { Double($0) } ?? 0)
        let ours = Double(scanner.progress().allocated) / 1024
        XCTAssertEqual(ours, duKiB, accuracy: max(duKiB * 0.01, 4), "scanner \(ours) KiB vs du \(duKiB) KiB")
    }

    func testHardLinksCountOnce() async throws {
        try tree.file("original.bin", bytes: 200_000)
        try tree.hardLink("original.bin", "copy/linked.bin")
        let once = await tree.scan()
        once.tree.read { s in
            XCTAssertEqual(s.size(0, .allocated), tree.allocated("original.bin"))
            let duplicates = (0 ..< NodeID(s.count)).filter { s.flags[Int($0)].contains(.hardLinkDuplicate) }
            XCTAssertEqual(duplicates.count, 1)
            XCTAssertTrue(s.isConsistent())
        }

        var options = ScanOptions()
        options.countHardLinksOnce = false
        let twice = await tree.scan(options)
        twice.tree.read { s in
            XCTAssertEqual(s.size(0, .allocated), tree.allocated("original.bin") * 2)
        }
    }

    func testSymlinksAreNotFollowed() async throws {
        let outside = try TestTree()
        defer { outside.remove() }
        try outside.file("huge.bin", bytes: 500_000)
        try tree.file("small.txt", bytes: 1_000)
        try tree.symlink("link-to-huge", to: outside.path)

        let scanner = await tree.scan()
        scanner.tree.read { s in
            let link = s.node(named: "link-to-huge")!
            XCTAssertTrue(s.flags[Int(link)].contains(.symlink))
            XCTAssertFalse(s.isDirectory(link))
            XCTAssertLessThan(s.size(0, .allocated), 100_000)
        }
    }

    func testRestrictedFoldersAreMarkedAndExcluded() async throws {
        try tree.file("open/a.bin", bytes: 10_000)
        try tree.file("locked/secret.bin", bytes: 300_000)
        tree.chmod("locked", 0o000)

        let scanner = await tree.scan()
        scanner.tree.read { s in
            let locked = s.node(named: "locked")!
            XCTAssertTrue(s.flags[Int(locked)].contains(.restricted))
            XCTAssertEqual(s.size(locked, .allocated), 0)
            XCTAssertEqual(s.restricted, [locked])
            XCTAssertEqual(s.size(0, .allocated), tree.allocated("open/a.bin"))
            XCTAssertFalse(s.flags[0].contains(.incomplete))
        }
    }

    func testCancellationKeepsAConsistentPartialTree() async throws {
        for i in 0 ..< 400 {
            try tree.file("d\(i % 20)/e\(i % 9)/f\(i).bin", bytes: 4_096)
        }
        var options = ScanOptions()
        options.threadCount = 1
        let scanner = DiskScanner(url: tree.root, options: options)
        scanner.start()
        scanner.cancel()
        await scanner.waitUntilFinished()
        XCTAssertTrue(scanner.isFinished)
        XCTAssertTrue(scanner.wasCancelled)
        XCTAssertTrue(scanner.progress().wasCancelled)
        scanner.tree.read { s in
            XCTAssertTrue(s.isConsistent())
            XCTAssertTrue(s.flags[0].contains(.incomplete))
        }
    }

    func testHiddenFilesAndSkipPatterns() async throws {
        try tree.file(".hidden/blob.bin", bytes: 50_000)
        try tree.file("node_modules/pkg/index.js", bytes: 20_000)
        try tree.file("keep/photo.jpg", bytes: 8_000)

        var options = ScanOptions()
        options.includeHidden = false
        options.skipList = SkipList(text: "node_modules\n# a comment\n")
        let scanner = await tree.scan(options)
        scanner.tree.read { s in
            XCTAssertNil(s.node(named: ".hidden"))
            XCTAssertNil(s.node(named: "node_modules"))
            XCTAssertEqual(s.size(0, .allocated), tree.allocated("keep/photo.jpg"))
        }

        var byPath = ScanOptions()
        byPath.skipList = SkipList(["\(tree.path)/keep/*"])
        let second = await tree.scan(byPath)
        second.tree.read { s in
            XCTAssertNotNil(s.node(named: "keep"))
            XCTAssertNil(s.node(named: "keep/photo.jpg"))
            XCTAssertEqual(s.kind[Int(s.node(named: "node_modules")!)], .devFolder)
        }
    }

    func testPackagesAreFoldersWithABadge() async throws {
        try tree.file("Tool.app/Contents/MacOS/Tool", bytes: 40_000)
        let scanner = await tree.scan()
        scanner.tree.read { s in
            let app = s.node(named: "Tool.app")!
            XCTAssertEqual(s.kind[Int(app)], .package)
            XCTAssertTrue(s.flags[Int(app)].contains(.package))
            XCTAssertEqual(s.size(app, .allocated), tree.allocated("Tool.app/Contents/MacOS/Tool"))
        }
    }

    func testRescanSplicesTheFocusedFolder() async throws {
        try tree.file("a/one.bin", bytes: 10_000)
        try tree.file("b/two.bin", bytes: 20_000)
        let scanner = await tree.scan()
        let a = scanner.tree.read { $0.node(named: "a")! }

        try tree.file("a/three.bin", bytes: 70_000)
        scanner.tree.write { $0.resetForRescan(a) }
        await DiskScanner(tree: scanner.tree, node: a).run()

        let expected = ["a/one.bin", "a/three.bin", "b/two.bin"].reduce(UInt64(0)) { $0 + tree.allocated($1) }
        scanner.tree.read { s in
            XCTAssertEqual(s.size(0, .allocated), expected)
            XCTAssertEqual(s.children(a).count, 2)
            XCTAssertEqual(s.items[0], 5)
            XCTAssertTrue(s.isConsistent())
            XCTAssertFalse(s.flags[Int(a)].contains(.incomplete))
        }
    }

    func testOtherVolumesAreNotCrossed() {
        // The boot volume's Data volume is part of the same group as "/", other devices aren't.
        let policy = VolumePolicy(rootPath: "/", crossVolumes: false)
        XCTAssertTrue(policy.allows(device: VolumePolicy.device("/")!))
        if let data = VolumePolicy.device(VolumePolicy.dataVolumePath) {
            XCTAssertTrue(policy.allows(device: data))
            XCTAssertTrue(policy.entersMountPoint(VolumePolicy.dataVolumePath))
            // Reached through the /Users firmlink, so not again under the Data volume.
            XCTAssertTrue(policy.skips("/System/Volumes/Data/Users"))
        }
        XCTAssertFalse(policy.entersMountPoint("/Volumes/Backup"))
        XCTAssertTrue(VolumePolicy(rootPath: "/", crossVolumes: true).entersMountPoint("/Volumes/Backup"))
        // Scanning Home never reaches the Data volume's mount point, so nothing is skipped.
        XCTAssertTrue(VolumePolicy(rootPath: NSHomeDirectory(), crossVolumes: false).skippedPaths.isEmpty)
    }

    func testFirmlinkTargetsInsideTheScanAreSkipped() {
        let links = [(source: "/Users", target: "Users"), (source: "/private/var", target: "private/var"),
                     (source: "/Applications", target: "Applications")]
        let policy = VolumePolicy(rootPath: "/", crossVolumes: false, firmlinks: links)
        XCTAssertEqual(policy.skippedPaths, ["/System/Volumes/Data/Users", "/System/Volumes/Data/private/var",
                                             "/System/Volumes/Data/Applications"])
        let system = VolumePolicy(rootPath: "/System", crossVolumes: false, firmlinks: links)
        XCTAssertTrue(system.skippedPaths.isEmpty)
    }
}
