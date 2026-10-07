import AppKit
import UniformTypeIdentifiers

/// Finder icons for table rows: by extension for files, per path for packages (apps have their own).
@MainActor
enum IconCache {
    private static var byType: [String: NSImage] = [:]
    private static var byPath: [String: NSImage] = [:]

    static func icon(for row: ItemRow) -> NSImage {
        if row.flags.contains(.symlink) { return typeIcon("symlink") { NSWorkspace.shared.icon(for: .symbolicLink) } }
        if row.kind == .package {
            if let cached = byPath[row.path] { return cached }
            let icon = NSWorkspace.shared.icon(forFile: row.path)
            if byPath.count > 2_000 { byPath.removeAll() }
            byPath[row.path] = icon
            return icon
        }
        if row.isDirectory { return typeIcon("folder") { NSWorkspace.shared.icon(for: .folder) } }
        let ext = KindClassifier.pathExtension(row.name) ?? ""
        return typeIcon("ext:" + ext) {
            NSWorkspace.shared.icon(for: ext.isEmpty ? .data : UTType(filenameExtension: ext) ?? .data)
        }
    }

    private static func typeIcon(_ key: String, make: () -> NSImage) -> NSImage {
        if let cached = byType[key] { return cached }
        let icon = make()
        byType[key] = icon
        return icon
    }
}
