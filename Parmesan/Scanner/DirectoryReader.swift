import Darwin
import Foundation

/// One directory entry as the file system reports it.
struct RawEntry {
    enum ObjectType { case file, directory, symlink, other }

    var name: String
    var type: ObjectType
    var device: Int32
    var fileID: UInt64
    var mtime: Int
    /// `st_flags` (UF_HIDDEN, SF_DATALESS, …).
    var flags: UInt32
    var linkCount: UInt32
    var logical: UInt64
    var allocated: UInt64
    /// The entry is a mount point (or an automount trigger) of another file system.
    var isMountPoint: Bool
}

/// Reads whole directories with `getattrlistbulk(2)`: name, type, device, file ID, link count, sizes,
/// modification date and flags for every entry in as few system calls as possible (see specs.md → DiskScanner).
/// Falls back to `readdir` + `lstat` on file systems that don't support it. One per thread: it owns its buffer.
final class DirectoryReader {
    private static let bufferSize = 256 * 1024
    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: DirectoryReader.bufferSize, alignment: 16)
    private var attributes: attrlist

    // sys/attr.h
    private static let cmnName: attrgroup_t = 0x0000_0001
    private static let cmnDevID: attrgroup_t = 0x0000_0002
    private static let cmnObjType: attrgroup_t = 0x0000_0008
    private static let cmnModTime: attrgroup_t = 0x0000_0400
    private static let cmnFlags: attrgroup_t = 0x0004_0000
    private static let cmnFileID: attrgroup_t = 0x0200_0000
    private static let cmnError: attrgroup_t = 0x2000_0000
    private static let cmnReturnedAttrs: attrgroup_t = 0x8000_0000
    private static let dirMountStatus: attrgroup_t = 0x0000_0004
    private static let fileLinkCount: attrgroup_t = 0x0000_0001
    private static let fileTotalSize: attrgroup_t = 0x0000_0002
    private static let fileAllocSize: attrgroup_t = 0x0000_0004
    private static let mountStatusMountPoint: UInt32 = 0x1
    private static let mountStatusTrigger: UInt32 = 0x2

    init() {
        attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = Self.cmnReturnedAttrs | Self.cmnName | Self.cmnError | Self.cmnDevID | Self.cmnObjType
            | Self.cmnModTime | Self.cmnFlags | Self.cmnFileID
        attributes.dirattr = Self.dirMountStatus
        attributes.fileattr = Self.fileLinkCount | Self.fileTotalSize | Self.fileAllocSize
    }

    deinit {
        buffer.deallocate()
    }

    /// Reads every entry of the open directory `fd` (at `path`, for the fallback) into `entries`.
    /// Returns 0, or the errno that stopped the read.
    func read(_ fd: Int32, path: String, device: Int32, into entries: inout [RawEntry]) -> Int32 {
        entries.removeAll(keepingCapacity: true)
        while true {
            let count = getattrlistbulk(fd, &attributes, buffer, Self.bufferSize, 0)
            if count == 0 { return 0 }
            if count < 0 {
                let error = errno
                if error == EINTR { continue }
                if (error == ENOTSUP || error == EINVAL), entries.isEmpty {
                    return readWithStat(path: path, device: device, into: &entries)
                }
                return error
            }
            parse(count: Int(count), into: &entries)
        }
    }

    private func parse(count: Int, into entries: inout [RawEntry]) {
        var entryStart = UnsafeRawPointer(buffer)
        for _ in 0 ..< count {
            let length = Int(entryStart.loadUnaligned(as: UInt32.self))
            defer { entryStart += length }
            var field = entryStart + 4
            let returned = field.loadUnaligned(as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size
            let common = returned.commonattr

            if common & Self.cmnError != 0 {
                let error = field.loadUnaligned(as: UInt32.self)
                field += 4
                if error != 0 { continue }
            }
            var name = ""
            if common & Self.cmnName != 0 {
                let offset = Int(field.loadUnaligned(as: Int32.self))
                let nameLength = Int(field.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
                let start = (field + offset).assumingMemoryBound(to: UInt8.self)
                name = String(decoding: UnsafeBufferPointer(start: start, count: max(0, nameLength - 1)), as: UTF8.self)
                field += 8
            }
            var device: Int32 = 0
            if common & Self.cmnDevID != 0 {
                device = field.loadUnaligned(as: Int32.self)
                field += 4
            }
            var type = RawEntry.ObjectType.other
            if common & Self.cmnObjType != 0 {
                switch field.loadUnaligned(as: UInt32.self) {
                case 1: type = .file // VREG
                case 2: type = .directory // VDIR
                case 5: type = .symlink // VLNK
                default: type = .other
                }
                field += 4
            }
            var mtime = 0
            if common & Self.cmnModTime != 0 {
                mtime = field.loadUnaligned(as: Int.self)
                field += MemoryLayout<timespec>.size
            }
            var flags: UInt32 = 0
            if common & Self.cmnFlags != 0 {
                flags = field.loadUnaligned(as: UInt32.self)
                field += 4
            }
            var fileID: UInt64 = 0
            if common & Self.cmnFileID != 0 {
                fileID = field.loadUnaligned(as: UInt64.self)
                field += 8
            }
            var isMountPoint = false
            if returned.dirattr & Self.dirMountStatus != 0 {
                let status = field.loadUnaligned(as: UInt32.self)
                isMountPoint = status & (Self.mountStatusMountPoint | Self.mountStatusTrigger) != 0
                field += 4
            }
            var linkCount: UInt32 = 1
            if returned.fileattr & Self.fileLinkCount != 0 {
                linkCount = field.loadUnaligned(as: UInt32.self)
                field += 4
            }
            var logical: UInt64 = 0
            if returned.fileattr & Self.fileTotalSize != 0 {
                logical = UInt64(max(0, field.loadUnaligned(as: Int64.self)))
                field += 8
            }
            var allocated: UInt64 = 0
            if returned.fileattr & Self.fileAllocSize != 0 {
                allocated = UInt64(max(0, field.loadUnaligned(as: Int64.self)))
                field += 8
            }
            if name.isEmpty || name == "." || name == ".." { continue }
            entries.append(RawEntry(name: name, type: type, device: device, fileID: fileID, mtime: mtime, flags: flags,
                                    linkCount: linkCount, logical: logical, allocated: allocated,
                                    isMountPoint: isMountPoint))
        }
    }

    /// The `FileManager`-style fallback: list names, then `lstat` each one.
    private func readWithStat(path: String, device: Int32, into entries: inout [RawEntry]) -> Int32 {
        guard let dir = opendir(path) else { return errno }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            var st = stat()
            guard lstat(path == "/" ? "/" + name : path + "/" + name, &st) == 0 else { continue }
            let type: RawEntry.ObjectType = switch st.st_mode & S_IFMT {
            case S_IFREG: .file
            case S_IFDIR: .directory
            case S_IFLNK: .symlink
            default: .other
            }
            let isDirectory = type == .directory
            entries.append(RawEntry(
                name: name, type: type, device: st.st_dev, fileID: st.st_ino, mtime: st.st_mtimespec.tv_sec,
                flags: st.st_flags, linkCount: UInt32(st.st_nlink),
                logical: isDirectory ? 0 : UInt64(max(0, st.st_size)),
                allocated: isDirectory ? 0 : UInt64(max(0, st.st_blocks)) * 512,
                isMountPoint: isDirectory && st.st_dev != device
            ))
        }
        return 0
    }
}
