import XCTest
@testable import Parmesan

final class FileTreeTests: XCTestCase {
    /// root ─ big (dir: x 600, y 300) ─ mid.txt 80 ─ tiny.txt 20
    private func sample() -> FileTreeStorage {
        var s = FileTreeStorage(rootPath: "/tmp/sample", rootName: "sample")
        func entry(_ name: String, _ size: UInt64, dir: Bool = false, mtime: Int32 = 1_000) -> ScannedEntry {
            ScannedEntry(name: name, kind: dir ? .folder : KindClassifier.kind(forFileNamed: name), flags: [],
                         allocated: size, logical: size / 2, mtime: mtime, willScan: dir)
        }
        let top = s.commit([entry("big", 0, dir: true), entry("mid.txt", 80), entry("tiny.txt", 20)], into: 0, scanRoot: 0)
        _ = s.commit([entry("x.mov", 600, mtime: 5_000), entry("y.jpg", 300)], into: top[0], scanRoot: 0)
        return s
    }

    func testAggregationAndPaths() {
        let s = sample()
        XCTAssertEqual(s.size(0, .allocated), 1_000)
        XCTAssertEqual(s.size(0, .logical), 500)
        XCTAssertEqual(s.items[0], 5)
        XCTAssertFalse(s.flags[0].contains(.incomplete))
        let x = s.find(path: "/tmp/sample/big/x.mov")!
        XCTAssertEqual(s.name(x), "x.mov")
        XCTAssertEqual(s.path(x), "/tmp/sample/big/x.mov")
        XCTAssertEqual(s.lineage(x).map { s.name($0) }, ["sample", "big", "x.mov"])
        XCTAssertEqual(s.find(path: "/tmp/sample"), 0)
        XCTAssertNil(s.find(path: "/tmp/sample/nope"))
        let big = s.find(path: "/tmp/sample/big")!
        XCTAssertEqual(s.dominant[Int(big)], .video)
        // Size-weighted: (5000*600 + 1000*300) / 900
        XCTAssertEqual(s.ageTime[Int(big)], 3_666)
        XCTAssertEqual(s.sortedChildren(0, .allocated).map { s.name($0) }, ["big", "mid.txt", "tiny.txt"])
    }

    func testRemoveUpdatesTotalsInPlace() {
        var s = sample()
        let x = s.find(path: "/tmp/sample/big/x.mov")!
        s.remove(x)
        XCTAssertEqual(s.size(0, .allocated), 400)
        XCTAssertEqual(s.items[0], 4)
        XCTAssertNil(s.find(path: "/tmp/sample/big/x.mov"))
        XCTAssertEqual(s.dominant[Int(s.find(path: "/tmp/sample/big")!)], .image)
        XCTAssertTrue(s.isConsistent())

        let big = s.find(path: "/tmp/sample/big")!
        s.remove(big)
        XCTAssertEqual(s.size(0, .allocated), 100)
        XCTAssertEqual(s.items[0], 2)
        XCTAssertTrue(s.isConsistent())
    }

    func testLargestFiles() {
        let s = sample()
        XCTAssertEqual(s.largestFiles(under: 0, limit: 3, .allocated).map { s.name($0) }, ["x.mov", "y.jpg", "mid.txt"])
        XCTAssertEqual(s.largestFiles(under: 0, limit: 10, .allocated).count, 4)
        XCTAssertEqual(s.largestFiles(under: s.find(path: "/tmp/sample/big")!, limit: 1, .allocated).map { s.name($0) }, ["x.mov"])
    }

    func testMemoryPerNodeStaysSmall() {
        var s = FileTreeStorage(rootPath: "/", rootName: "root")
        let entries = (0 ..< 10_000).map {
            ScannedEntry(name: "file-\($0).dat", kind: .other, flags: [], allocated: 4096, logical: 4000, mtime: 0, willScan: false)
        }
        _ = s.commit(entries, into: 0, scanRoot: 0)
        XCTAssertLessThanOrEqual(s.approximateMemory / s.count, 64)
    }

    func testKindClassifier() {
        XCTAssertEqual(KindClassifier.kind(forFileNamed: "IMG_0001.HEIC"), .image)
        XCTAssertEqual(KindClassifier.kind(forFileNamed: "installer.dmg"), .archive)
        XCTAssertEqual(KindClassifier.kind(forFileNamed: "main.swift"), .code)
        XCTAssertEqual(KindClassifier.kind(forFileNamed: ".zshrc"), .other)
        XCTAssertEqual(KindClassifier.kind(forFileNamed: "README"), .other)
        XCTAssertEqual(KindClassifier.kind(forDirectoryNamed: "Safari.app"), .package)
        XCTAssertEqual(KindClassifier.kind(forDirectoryNamed: "node_modules"), .devFolder)
        XCTAssertEqual(KindClassifier.kind(forDirectoryNamed: "Library"), .systemFolder)
        XCTAssertEqual(KindClassifier.kind(forDirectoryNamed: "Photos 2024"), .folder)
        XCTAssertEqual(KindClassifier.kind(forDirectoryNamed: "en.lproj"), .folder)
    }

    func testGlobAndSkipList() {
        XCTAssertTrue(Glob.matches("*.dmg", "Installer.DMG"))
        XCTAssertFalse(Glob.matches("*.dmg", "Installer.DMG", caseInsensitive: false))
        XCTAssertTrue(Glob.isPattern("*.dmg"))
        XCTAssertFalse(Glob.isPattern("report"))
        let skip = SkipList(["node_modules", "~/Library/Caches/*", "  ", "# comment"])
        XCTAssertTrue(skip.skips(name: "node_modules", path: "/x/node_modules"))
        XCTAssertTrue(skip.skips(name: "com.apple.foo", path: NSHomeDirectory() + "/Library/Caches/com.apple.foo"))
        XCTAssertFalse(skip.skips(name: "Caches", path: NSHomeDirectory() + "/Library/Caches"))
    }

    func testFormatting() {
        XCTAssertEqual(Format.percent(0.312), "31%")
        XCTAssertEqual(Format.percent(0.004), "<1%")
        XCTAssertEqual(Format.clock(14), "00:14")
        XCTAssertEqual(Format.clock(3_725), "1:02:05")
        XCTAssertEqual(Format.middleTruncated("abcdefghijklmnopqrstuvwxyz", limit: 9), "abcd…wxyz")
    }
}
