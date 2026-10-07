import Foundation
import UniformTypeIdentifiers

/// One row of the contents table: a direct child of the focus, or a file in the largest-files view.
struct ItemRow: Identifiable, Hashable {
    let id: NodeID
    let name: String
    let path: String
    let size: UInt64
    /// Share of the focus folder (the % column).
    let fraction: Double
    /// Share of the row's own folder, for By Size colors.
    let shareOfParent: Double
    /// Recursive item count; 0 for files.
    let itemCount: UInt32
    let kind: NodeKind
    let dominant: NodeKind
    let ageTime: Int32
    let flags: NodeFlags
    let kindDescription: String
    let modified: Date

    var isDirectory: Bool { kind.isDirectory }

    var colorInputs: ColorInputs {
        ColorInputs(share: shareOfParent, dominant: dominant, ageTime: ageTime, flags: flags)
    }

    @MainActor
    static func make(_ s: borrowing FileTreeStorage, _ id: NodeID, focusSize: UInt64, _ mode: SizeMode) -> ItemRow {
        let i = Int(id)
        let size = s.size(id, mode)
        let parentSize = s.size(s.parent[i], mode)
        let name = s.name(id)
        return ItemRow(
            id: id, name: name, path: s.path(id), size: size,
            fraction: focusSize > 0 ? Double(size) / Double(focusSize) : 0,
            shareOfParent: parentSize > 0 ? Double(size) / Double(parentSize) : 0,
            itemCount: s.kind[i].isDirectory ? s.items[i] : 0, kind: s.kind[i], dominant: s.dominant[i],
            ageTime: s.ageTime[i], flags: s.flags[i],
            kindDescription: KindDescriptions.describe(name: name, kind: s.kind[i], flags: s.flags[i]),
            modified: Date(timeIntervalSince1970: TimeInterval(s.mtime[i])))
    }
}

/// The table filter: a name substring, or a glob when it has wildcards (`*.dmg`).
struct RowFilter {
    let text: String

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    func matches(_ name: String) -> Bool {
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return true }
        if Glob.isPattern(query) { return Glob.matches(query, name) }
        return name.localizedCaseInsensitiveContains(query)
    }
}

/// Localized kind names ("Folder", "PNG image", …), cached by extension.
@MainActor
enum KindDescriptions {
    private static var cache: [String: String] = [:]

    static func describe(name: String, kind: NodeKind, flags: NodeFlags) -> String {
        if flags.contains(.symlink) { return String(localized: "Symbolic Link") }
        let ext = KindClassifier.pathExtension(name) ?? ""
        if kind.isDirectory, kind != .package { return String(localized: "Folder") }
        let key = (kind == .package ? "pkg:" : "") + ext
        if let cached = cache[key] { return cached }
        let type: UTType? = ext.isEmpty ? nil
            : UTType(filenameExtension: ext, conformingTo: kind == .package ? .package : .data)
        let description = type?.localizedDescription
            ?? (kind == .package ? String(localized: "Package") : ext.isEmpty ? String(localized: "Document") : String(localized: "\(ext.uppercased()) File"))
        cache[key] = description
        return description
    }
}
