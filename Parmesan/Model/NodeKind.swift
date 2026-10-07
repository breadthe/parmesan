import Foundation
import Synchronization
import UniformTypeIdentifiers

/// Index of a node in a `FileTree`.
typealias NodeID = UInt32

/// What a node is, decided once at scan time from its type and name (see specs.md → Color Coding, By Kind).
enum NodeKind: UInt8, Sendable, CaseIterable {
    // Folders
    case folder, package, devFolder, systemFolder
    // Files
    case image, video, audio, document, archive, code, system, other

    var isDirectory: Bool { rawValue <= NodeKind.systemFolder.rawValue }

    var category: KindCategory {
        switch self {
        case .folder: .folders
        case .package: .packages
        case .devFolder, .code: .code
        case .systemFolder, .system: .system
        case .image: .images
        case .video: .video
        case .audio: .audio
        case .document: .documents
        case .archive: .archives
        case .other: .other
        }
    }
}

/// The By Kind color groups, in legend order.
enum KindCategory: Int, Sendable, CaseIterable, Identifiable {
    case folders, packages, images, video, audio, documents, archives, code, system, other

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .folders: String(localized: "Folders")
        case .packages: String(localized: "Apps & Packages")
        case .images: String(localized: "Images")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .documents: String(localized: "Documents")
        case .archives: String(localized: "Archives & Disk Images")
        case .code: String(localized: "Code & Dev Artifacts")
        case .system: String(localized: "System & Library")
        case .other: String(localized: "Other")
        }
    }

    /// Short tag drawn on the chart when Differentiate Without Color is on.
    var abbreviation: String {
        switch self {
        case .folders: "DIR"
        case .packages: "APP"
        case .images: "IMG"
        case .video: "VID"
        case .audio: "AUD"
        case .documents: "DOC"
        case .archives: "ZIP"
        case .code: "DEV"
        case .system: "SYS"
        case .other: "OTH"
        }
    }
}

struct NodeFlags: OptionSet, Sendable, Hashable {
    let rawValue: UInt16

    /// The folder couldn't be read (EACCES/EPERM); its contents aren't counted.
    static let restricted = NodeFlags(rawValue: 1 << 0)
    /// The folder hasn't been fully scanned yet (or the scan was stopped).
    static let incomplete = NodeFlags(rawValue: 1 << 1)
    static let package = NodeFlags(rawValue: 1 << 2)
    static let symlink = NodeFlags(rawValue: 1 << 3)
    /// An iCloud placeholder whose data isn't downloaded.
    static let dataless = NodeFlags(rawValue: 1 << 4)
    /// Another hard link to an inode already counted elsewhere in this scan; its size counts as 0.
    static let hardLinkDuplicate = NodeFlags(rawValue: 1 << 5)
    /// Moved to the Trash from Parmesan; skipped everywhere.
    static let removed = NodeFlags(rawValue: 1 << 6)
    /// A mount point of another volume that wasn't crossed.
    static let otherVolume = NodeFlags(rawValue: 1 << 7)
    /// Reading the folder failed for some other reason; it's skipped.
    static let failed = NodeFlags(rawValue: 1 << 8)
}

/// Allocated size on disk (default) or logical size (see specs.md → Core Concepts, Size).
enum SizeMode: String, Sendable, CaseIterable, Identifiable {
    case allocated, logical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allocated: String(localized: "Allocated size on disk")
        case .logical: String(localized: "Logical size")
        }
    }
}

/// Maps names to kinds. Lookups are by lowercase extension; no UTType work for plain files, it's too slow
/// for millions of them.
enum KindClassifier {
    static func kind(forFileNamed name: String) -> NodeKind {
        guard let ext = pathExtension(name) else { return .other }
        return fileKinds[ext] ?? .other
    }

    /// For a directory: package (by extension), a well-known dev or system folder, or a plain folder.
    static func kind(forDirectoryNamed name: String) -> NodeKind {
        if let ext = pathExtension(name), isPackageExtension(ext) { return .package }
        if devFolderNames.contains(name) { return .devFolder }
        if systemFolderNames.contains(name) { return .systemFolder }
        return .folder
    }

    static func pathExtension(_ name: String) -> String? {
        guard let dot = name.utf8.lastIndex(of: UInt8(ascii: ".")), dot != name.utf8.startIndex else { return nil }
        let ext = name.utf8[name.utf8.index(after: dot)...]
        guard !ext.isEmpty, ext.count <= 16 else { return nil }
        return String(decoding: ext, as: UTF8.self).lowercased()
    }

    private static let knownPackageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc", "qlgenerator", "mdimporter", "prefpane",
        "saver", "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary", "imovielibrary",
        "fcpbundle", "xcodeproj", "xcworkspace", "xcarchive", "playground", "rtfd", "pages", "numbers", "key",
        "sparsebundle", "logicx", "band", "dsym", "docarchive", "xcresult", "mlmodelc", "lproj"
    ]

    private static let packageCache = PackageExtensionCache()

    /// Known package extensions, else whether the system declares the extension as a package type.
    static func isPackageExtension(_ ext: String) -> Bool {
        if ext == "lproj" { return false }
        if knownPackageExtensions.contains(ext) { return true }
        return packageCache.isPackage(ext)
    }

    static let devFolderNames: Set<String> = [
        "node_modules", "DerivedData", ".git", ".svn", ".hg", ".build", "Pods", "Carthage", ".gradle",
        ".venv", "venv", "__pycache__", ".next", ".nuxt", ".turbo", ".cargo", ".rustup", ".npm", ".yarn",
        ".pnpm-store", "bower_components", ".tox", ".mypy_cache", ".pytest_cache", ".terraform"
    ]

    static let systemFolderNames: Set<String> = [
        "Library", "System", "Caches", "Application Support", "Containers", "Group Containers", "Preferences",
        "Logs", "private", "usr", "bin", "sbin", "cores", "Frameworks"
    ]

    private static let fileKinds: [String: NodeKind] = {
        var map: [String: NodeKind] = [:]
        func add(_ kind: NodeKind, _ list: String) {
            for ext in list.split(separator: " ") { map[String(ext)] = kind }
        }
        add(.image, "jpg jpeg png gif heic heif tif tiff bmp webp raw cr2 cr3 nef arw dng orf rw2 psd psb ai svg ico icns avif jxl xcf sketch fig")
        add(.video, "mov mp4 m4v avi mkv webm wmv flv mpg mpeg 3gp mts m2ts vob braw r3d")
        add(.audio, "mp3 m4a m4b m4r aac wav aif aiff aifc flac ogg oga opus caf alac wma mid midi ape")
        add(.document, "pdf doc docx xls xlsx ppt pptx txt rtf md markdown csv tsv epub odt ods odp tex mobi azw3 eml mbox vcf ics")
        add(.archive, "zip tar gz tgz bz2 tbz xz txz 7z rar dmg iso img sparseimage pkg mpkg xip zst lz4 lzma cpio ipsw cab apk ipa deb rpm toast vmdk qcow2 vdi")
        add(.code, "swift m mm h hh hpp c cc cpp cxx js mjs cjs ts tsx jsx py pyc pyo rb go rs java class jar kt kts php json yaml yml toml xml sh zsh bash fish css scss sass less html htm vue svelte map o a lib wasm lock gradle pbxproj swiftmodule swiftdoc swiftinterface swiftsourceinfo xcconfig sql ipynb pch pcm dia d gcda gcno lua pl r scala dart ex exs erl hs ml cs fs vb")
        add(.system, "dylib so kext plist car nib loctable dat db sqlite sqlite3 sqlite-wal sqlite-shm db-wal db-shm cache log asl tracev3 dyld_shared_cache bom sb mobileprovision")
        return map
    }()
}

/// Remembers which extensions the system calls packages, across scanner threads.
private final class PackageExtensionCache: Sendable {
    private let known = Mutex<[String: Bool]>([:])

    func isPackage(_ ext: String) -> Bool {
        if let cached = known.withLock({ $0[ext] }) { return cached }
        let result = UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) ?? false
        known.withLock { $0[ext] = result }
        return result
    }
}
