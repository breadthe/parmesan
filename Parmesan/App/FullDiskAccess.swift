import AppKit
import Darwin
import SwiftUI

/// Detects Full Disk Access by trying to open a protected path (see specs.md → Permissions).
enum FullDiskAccess {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    private static let probes = [
        "/Library/Application Support/com.apple.TCC/TCC.db",
        "~/Library/Safari",
        "~/Library/Mail",
    ]

    static var isGranted: Bool {
        for probe in probes {
            let path = (probe as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            if errno == EPERM || errno == EACCES { return false }
        }
        return true
    }

    @MainActor
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

/// The first-launch sheet shown when Full Disk Access is missing.
struct FullDiskAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @AppStorage(PreferenceKey.skipAccessOnboarding) private var dontAskAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Give Parmesan Full Disk Access")
                    .font(.title2.bold())
            }
            Text("macOS keeps some folders private: Mail, Messages, Safari, other apps' containers, Time Machine, and parts of Library. Without Full Disk Access, Parmesan can't see inside them, so their size is left out of the totals and they're marked **Restricted**.")
            Text("Parmesan only reads sizes and names, never contents, and nothing ever leaves your Mac.")
                .foregroundStyle(.secondary)
            Text("In System Settings, turn on **Parmesan** under Privacy & Security → Full Disk Access (or click **+** and choose the app), then rescan.")
            Text("Rebuilt Parmesan yourself? With ad-hoc signing, each build needs to be granted again; see the README.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Don't show this again", isOn: $dontAskAgain)
            HStack {
                Spacer()
                Button("Continue Without") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open System Settings") {
                    FullDiskAccess.openSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
