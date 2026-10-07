import AppKit

/// Scan progress on the Dock tile (see specs.md → Status Bar & Feedback): a bar when scanning a whole
/// volume (scanned bytes against the volume's used space), else a badge with the item count.
@MainActor
enum DockProgress {
    private static let view = DockTileView()

    static func update(_ progress: ScanProgress, scanRootIsVolume: Bool, volumeUsed: UInt64?) {
        let tile = NSApp.dockTile
        if scanRootIsVolume, let volumeUsed, volumeUsed > 0 {
            view.fraction = min(1, Double(progress.allocated) / Double(volumeUsed))
            if tile.contentView !== view { tile.contentView = view }
            tile.badgeLabel = nil
        } else {
            tile.contentView = nil
            tile.badgeLabel = Format.compact(progress.items)
        }
        tile.display()
    }

    static func clear() {
        let tile = NSApp.dockTile
        tile.contentView = nil
        tile.badgeLabel = nil
        tile.display()
    }
}

private final class DockTileView: NSView {
    var fraction = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let bar = NSRect(x: bounds.width * 0.12, y: bounds.height * 0.08, width: bounds.width * 0.76, height: bounds.height * 0.09)
        let track = NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
        NSColor.black.withAlphaComponent(0.55).setFill()
        track.fill()
        let filled = bar.insetBy(dx: 2, dy: 2)
        let progress = NSRect(x: filled.minX, y: filled.minY, width: max(filled.height, filled.width * fraction), height: filled.height)
        NSColor(red: 0.95, green: 0.82, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(roundedRect: progress, xRadius: filled.height / 2, yRadius: filled.height / 2).fill()
    }
}
