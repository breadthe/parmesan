import XCTest
@testable import Parmesan

final class LayoutTests: XCTestCase {
    /// A folder with 3 big children, 200 tiny files and a nested folder.
    private func sample() -> FileTreeStorage {
        var s = FileTreeStorage(rootPath: "/t", rootName: "t")
        var entries = [
            ScannedEntry(name: "big", kind: .folder, flags: [], allocated: 0, logical: 0, mtime: 0, willScan: true),
            ScannedEntry(name: "a.mov", kind: .video, flags: [], allocated: 400_000, logical: 400_000, mtime: 0, willScan: false),
            ScannedEntry(name: "b.zip", kind: .archive, flags: [], allocated: 200_000, logical: 200_000, mtime: 0, willScan: false),
        ]
        for i in 0 ..< 200 {
            entries.append(ScannedEntry(name: "tiny\(i)", kind: .other, flags: [], allocated: 10, logical: 10, mtime: 0, willScan: false))
        }
        let dirs = s.commit(entries, into: 0, scanRoot: 0)
        _ = s.commit([
            ScannedEntry(name: "c.jpg", kind: .image, flags: [], allocated: 250_000, logical: 250_000, mtime: 0, willScan: false),
            ScannedEntry(name: "d.jpg", kind: .image, flags: [], allocated: 150_000, logical: 150_000, mtime: 0, willScan: false),
        ], into: dirs[0], scanRoot: 0)
        return s
    }

    func testSunburstAnglesCoverTheCircle() {
        let s = sample()
        let geometry = SunburstLayout.layout(s, focus: 0, rings: 4, mode: .allocated)
        let ring1 = geometry.byRing[0].map { geometry.segments[$0] }
        XCTAssertEqual(ring1.count, 4) // big, a.mov, b.zip, "200 smaller items"
        XCTAssertEqual(ring1.first?.start ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(ring1.last?.end ?? 0, 2 * .pi, accuracy: 1e-9)
        let other = ring1.last!
        XCTAssertTrue(other.info.isOther)
        XCTAssertEqual(other.info.otherCount, 200)
        for (a, b) in zip(ring1, ring1.dropFirst()) {
            XCTAssertEqual(a.end, b.start, accuracy: 1e-9)
        }
        // Ring 2 holds big's children within big's arc.
        let big = ring1.first { $0.info.name == "big" }!
        let ring2 = geometry.byRing[1].map { geometry.segments[$0] }
        XCTAssertEqual(ring2.count, 2)
        XCTAssertEqual(ring2.first!.start, big.start, accuracy: 1e-9)
        XCTAssertEqual(ring2.last!.end, big.end, accuracy: 1e-9)
        XCTAssertTrue(big.hasChildren)

        let hit = geometry.segment(atAngle: (big.start + big.end) / 2, ring: 1)
        XCTAssertEqual(hit.map { geometry.segments[$0].info.name }, "big")
        let inner = geometry.segment(atAngle: ring2[0].start + 0.01, ring: 2)!
        XCTAssertEqual(geometry.lineage(of: inner).map { geometry.segments[$0].info.name }, ["big", "c.jpg"])
        XCTAssertNil(geometry.segment(atAngle: 1, ring: 3))
    }

    func testSunburstRespectsDepth() {
        let geometry = SunburstLayout.layout(sample(), focus: 0, rings: 1, mode: .allocated)
        XCTAssertTrue(geometry.segments.allSatisfy { $0.ring == 1 })
        XCTAssertFalse(geometry.segments.contains { $0.hasChildren })
    }

    func testSquarifyFillsTheRect() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1].map { $0 * 240_000 / 24 }
        let rects = TreemapLayout.squarify(values, in: rect)
        XCTAssertEqual(rects.count, values.count)
        for (r, v) in zip(rects, values) {
            XCTAssertEqual(Double(r.width * r.height), v, accuracy: 1)
            XCTAssertTrue(rect.insetBy(dx: -0.001, dy: -0.001).contains(r))
        }
        let total = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(total, 240_000, accuracy: 1)
        // Squarified rects stay reasonably square.
        XCTAssertLessThan(rects.map { max($0.width / $0.height, $0.height / $0.width) }.max()!, 4)
    }

    func testTreemapNestsAndHitTests() {
        let s = sample()
        let size = CGSize(width: 800, height: 600)
        let geometry = TreemapLayout.layout(s, focus: 0, size: size, depth: 3, mode: .allocated)
        let top = geometry.roots.map { geometry.segments[$0] }
        XCTAssertEqual(top.count, 4)
        XCTAssertTrue(top.last!.info.isOther)
        let big = top.first { $0.info.name == "big" }!
        XCTAssertNotNil(big.header)
        XCTAssertEqual(big.children.count, 2)
        for child in big.children {
            XCTAssertTrue(big.rect.contains(geometry.segments[child].rect))
        }
        let child = geometry.segments[big.children[0]]
        let hit = geometry.segment(at: CGPoint(x: child.rect.midX, y: child.rect.midY))
        XCTAssertEqual(hit.map { geometry.segments[$0].info.name }, child.info.name)
        let area = top.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        XCTAssertEqual(area, 480_000, accuracy: 1)
    }
}
