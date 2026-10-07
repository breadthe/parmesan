import Darwin
import Foundation

/// Which folders a scan may enter, so nothing is counted twice and other volumes stay out
/// (see specs.md → Size accounting rules, Volume boundaries).
///
/// Since Catalina, `/` is the read-only System volume and user data lives on the Data volume, mounted at
/// `/System/Volumes/Data` and spliced into `/` with firmlinks (`/Users`, `/Applications`, `/private`, …,
/// listed in `/usr/share/firmlinks`). The two count as one volume, and when a firmlink's source is inside
/// the scan, its target under `/System/Volumes/Data` is skipped: those bytes are counted at the source.
struct VolumePolicy: Sendable {
    static let dataVolumePath = "/System/Volumes/Data"

    let crossVolumes: Bool
    let allowedDevices: Set<Int32>
    /// Full paths under the Data volume reached through a firmlink elsewhere in the scan.
    let skippedPaths: Set<String>

    init(rootPath: String, crossVolumes: Bool, firmlinks: [(source: String, target: String)] = VolumePolicy.firmlinks()) {
        self.crossVolumes = crossVolumes
        let rootDevice = Self.device(rootPath)
        let systemDevice = Self.device("/")
        let dataDevice = Self.device(Self.dataVolumePath)
        var allowed: Set<Int32> = []
        if let rootDevice { allowed.insert(rootDevice) }
        if let systemDevice, let dataDevice, rootDevice == systemDevice || rootDevice == dataDevice {
            allowed.formUnion([systemDevice, dataDevice])
        }
        allowedDevices = allowed

        let root = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let dataRoot = Self.dataVolumePath + "/"
        var skipped: Set<String> = []
        // Only matters when the scan reaches the Data volume's mount point as well as the firmlink.
        if dataRoot.hasPrefix(root) {
            for link in firmlinks where (link.source + "/").hasPrefix(root) {
                skipped.insert(dataRoot + link.target)
            }
        }
        skippedPaths = skipped
    }

    /// May the scan enter a folder on this device?
    func allows(device: Int32) -> Bool {
        crossVolumes || allowedDevices.contains(device)
    }

    /// May the scan enter this mount point? Other volumes only when crossing is on; the Data volume when
    /// it's part of the same volume group as the scan root.
    func entersMountPoint(_ path: String) -> Bool {
        if crossVolumes { return true }
        guard path == Self.dataVolumePath, let device = Self.device(path) else { return false }
        return allowedDevices.contains(device)
    }

    func skips(_ path: String) -> Bool {
        !skippedPaths.isEmpty && skippedPaths.contains(path)
    }

    static func device(_ path: String) -> Int32? {
        var st = stat()
        return stat(path, &st) == 0 ? st.st_dev : nil
    }

    /// `/usr/share/firmlinks`: one `source<TAB>target` per line, target relative to the Data volume.
    static func firmlinks(at path: String = "/usr/share/firmlinks") -> [(source: String, target: String)] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
    }
}
