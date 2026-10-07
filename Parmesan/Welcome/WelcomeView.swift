import AppKit
import SwiftUI

/// The empty state: a drop zone, mounted volumes, common places and recent scans (see specs.md → Launch / Empty State).
struct WelcomeView: View {
    let model: BrowserModel
    var isDropTargeted: Bool
    @Environment(AppState.self) private var appState
    @State private var volumes: [VolumeInfo] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("Parmesan")
                        .font(.largeTitle.weight(.semibold))
                    Text("Grate your disk, find the big chunks.")
                        .foregroundStyle(.secondary)
                }

                dropZone

                HStack(alignment: .top, spacing: 18) {
                    section("Volumes") {
                        ForEach(volumes) { volume in
                            PlaceButton(icon: volume.icon, title: volume.name, subtitle: volume.capacityText,
                                        fraction: volume.usedFraction) { model.startScan(volume.url) }
                        }
                    }
                    section("Places") {
                        ForEach(Place.all) { place in
                            PlaceButton(icon: place.icon, title: place.name, subtitle: place.subtitle) {
                                model.startScan(place.url)
                            }
                        }
                    }
                    if !appState.recents.isEmpty {
                        section("Recent") {
                            ForEach(appState.recents, id: \.self) { url in
                                PlaceButton(icon: NSWorkspace.shared.icon(forFile: url.path),
                                            title: FileManager.default.displayName(atPath: url.path),
                                            subtitle: (url.path as NSString).abbreviatingWithTildeInPath) {
                                    model.startScan(url)
                                }
                                .contextMenu {
                                    Button("Remove from Recents") { appState.removeRecent(url) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 960)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .onAppear { volumes = VolumeInfo.mounted() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = VolumeInfo.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = VolumeInfo.mounted()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Drop a folder here, or choose a location.")
                .font(.title3)
            Button("Choose Folder…") {
                if let url = FolderPicker.choose() { model.startScan(url) }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 560)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .background(RoundedRectangle(cornerRadius: 14).fill(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear))
        }
        .frame(maxWidth: 560)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A clickable row: icon, name, detail line and an optional capacity bar.
private struct PlaceButton: View {
    let icon: NSImage
    let title: String
    let subtitle: String
    var fraction: Double?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .lineLimit(1)
                    if let fraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(fraction > 0.9 ? .red : .accentColor)
                            .frame(maxWidth: 200)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(isHovering ? Color.primary.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(subtitle)
    }
}

struct VolumeInfo: Identifiable {
    var id: URL { url }
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let icon: NSImage

    var usedFraction: Double { total > 0 ? Double(total - available) / Double(total) : 0 }

    var capacityText: String {
        String(localized: "\(Format.size(total - available)) used of \(Format.size(total))")
    }

    static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false else { return nil }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            return VolumeInfo(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, total: total,
                              available: min(total, values.volumeAvailableCapacityForImportantUsage ?? 0),
                              icon: NSWorkspace.shared.icon(forFile: url.path))
        }
    }
}

struct Place: Identifiable {
    var id: String { url.path }
    let name: String
    let url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var subtitle: String { (url.path as NSString).abbreviatingWithTildeInPath }

    static var all: [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Place(name: String(localized: "Home"), url: home),
            Place(name: String(localized: "Downloads"), url: home.appending(path: "Downloads")),
            Place(name: String(localized: "Library"), url: home.appending(path: "Library")),
            Place(name: String(localized: "Developer"), url: home.appending(path: "Library/Developer")),
        ].filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}
