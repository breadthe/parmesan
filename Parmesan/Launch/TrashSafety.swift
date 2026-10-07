import Darwin
import Foundation

/// Extra caution for system locations (see specs.md → Safety). Items under these paths, or protected by
/// System Integrity Protection, get a warning, and Move to Trash only works while ⌥ is held.
enum TrashSafety {
    static let protectedPrefixes = ["/System", "/usr", "/bin", "/sbin", "/Library/Apple"]

    /// `SF_RESTRICTED`: the SIP flag.
    private static let restrictedFlag: UInt32 = 0x0008_0000

    static func isProtected(_ path: String) -> Bool {
        if protectedPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        var st = stat()
        return lstat(path, &st) == 0 && st.st_flags & restrictedFlag != 0
    }
}
