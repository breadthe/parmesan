import SwiftUI

/// Live scan progress, then the totals, free space and restricted folders (see specs.md → Status Bar & Feedback).
struct StatusBar: View {
    @Bindable var model: BrowserModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(scanningText)
                    .monospacedDigit()
                Text(model.progress.currentPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Stop") { model.stopScan() }
                    .controlSize(.small)
                    .help("Stop Scan (⌘.)")
            } else {
                Text(summaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer()
            }
            if !model.restrictedPaths.isEmpty {
                Button {
                    model.isShowingRestricted.toggle()
                } label: {
                    Label("\(model.restrictedPaths.count) restricted", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Folders Parmesan couldn't read; their size isn't counted")
                .popover(isPresented: $model.isShowingRestricted, arrowEdge: .top) {
                    RestrictedList(paths: model.restrictedPaths)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var scanningText: String {
        let p = model.progress
        return String(localized: "Scanning… \(Format.count(p.items)) items · \(Format.size(p.bytes(model.sizeMode))) · \(Format.clock(p.elapsed))")
    }

    private var summaryText: String {
        let p = model.progress
        var text = model.phase == .stopped
            ? String(localized: "Stopped after \(Format.count(p.items)) items (\(Format.size(p.bytes(model.sizeMode)))) in \(Format.duration(p.elapsed)); unfinished folders are marked")
            : String(localized: "Scanned \(Format.count(p.items)) items (\(Format.size(p.bytes(model.sizeMode)))) in \(Format.duration(p.elapsed))")
        if let available = model.availableCapacity {
            text += " · " + String(localized: "\(Format.size(available)) available")
        }
        return text
    }
}

private struct RestrictedList: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Restricted folders")
                .font(.headline)
            Text("Parmesan couldn't read these, so their size isn't included in the totals. Full Disk Access lets it see most of them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(paths, id: \.self) { path in
                Label((path as NSString).abbreviatingWithTildeInPath, systemImage: "lock.fill")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contextMenu {
                        Button("Reveal in Finder") { OpenIn.revealInFinder([URL(fileURLWithPath: path)]) }
                        Button("Copy Path") { Clipboard.copy(path) }
                    }
            }
            .frame(height: min(CGFloat(paths.count) * 24 + 12, 260))
            HStack {
                Spacer()
                Button("Grant Full Disk Access…") { FullDiskAccess.openSettings() }
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}
