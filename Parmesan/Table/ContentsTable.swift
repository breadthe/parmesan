import SwiftUI

/// The focus folder's direct children (or the largest files below it), sortable, with the selection
/// mirrored in the chart (see specs.md → Table).
struct ContentsTable: View {
    @Bindable var model: BrowserModel
    @Environment(\.chartPalette) private var palette

    var body: some View {
        ScrollViewReader { proxy in
            Table(model.rows, selection: $model.tableSelection, sortOrder: $model.sortOrder) {
                TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
                    NameCell(row: row)
                }
                .width(min: 140, ideal: 220)
                TableColumn("Size", value: \.size) { row in
                    Text(Format.size(row.size))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(Format.exactBytes(row.size))
                }
                .width(min: 64, ideal: 80)
                TableColumn("%", value: \.fraction) { row in
                    PercentCell(fraction: row.fraction, color: palette.fill(row.colorInputs, mode: model.colorMode).color)
                }
                .width(min: 80, ideal: 100)
                TableColumn("Items", value: \.itemCount) { row in
                    Text(row.isDirectory ? Format.count(Int(row.itemCount)) : "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 44, ideal: 60)
                TableColumn("Kind", value: \.kindDescription, comparator: .localizedStandard) { row in
                    Text(row.kindDescription).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 60, ideal: 100)
                TableColumn("Modified", value: \.modified) { row in
                    Text(Format.date(row.modified)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 130)
                if model.flattened {
                    TableColumn("Path", value: \.path, comparator: .localizedStandard) { row in
                        Text((row.path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.path)
                    }
                    .width(min: 120, ideal: 280)
                }
            }
            .contextMenu(forSelectionType: NodeID.self) { ids in
                ItemActionsMenu(model: model, ids: Array(ids).sorted())
            } primaryAction: { ids in
                model.activate(ids)
            }
            .onKeyPress(.space) {
                model.quickLook()
                return .handled
            }
            .onKeyPress(.delete) {
                model.goUp()
                return .handled
            }
            .onChange(of: model.scrollTarget) { _, target in
                if let target { proxy.scrollTo(target) }
            }
            .overlay {
                if model.rows.isEmpty, !model.isScanning {
                    ContentUnavailableView(emptyTitle, systemImage: model.filterText.isEmpty ? "tray" : "magnifyingglass")
                }
            }
            .accessibilityLabel(model.flattened ? "Largest files" : "Folder contents")
        }
    }

    private var emptyTitle: String {
        if !model.filterText.isEmpty { return String(localized: "No Matches") }
        if model.focusInfo?.flags.contains(.restricted) == true { return String(localized: "Restricted") }
        return model.flattened ? String(localized: "No Files") : String(localized: "Empty Folder")
    }
}

private struct NameCell: View {
    let row: ItemRow

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(for: row))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
            badges
        }
        .help(row.path)
    }

    @ViewBuilder
    private var badges: some View {
        let flags = row.flags
        if flags.contains(.restricted) { badge("lock.fill", "Restricted: Parmesan can't read this folder") }
        if flags.contains(.package) { badge("shippingbox", "Package") }
        if flags.contains(.symlink) { badge("arrowshape.turn.up.right", "Symbolic link, not followed") }
        if flags.contains(.dataless) { badge("icloud", "In iCloud, not downloaded") }
        if flags.contains(.hardLinkDuplicate) { badge("link", "Hard link; its size is counted at another link") }
        if flags.contains(.otherVolume) { badge("externaldrive", "Another volume, not scanned") }
        if flags.contains(.incomplete) { badge("hourglass", "Not fully scanned") }
        if flags.contains(.failed) { badge("exclamationmark.circle", "Couldn't be read") }
    }

    private func badge(_ symbol: String, _ help: LocalizedStringKey) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(help)
    }
}

/// An inline bar in the row's chart color, with the percentage.
private struct PercentCell: View {
    let fraction: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * min(fraction, 1)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                }
            }
            .frame(height: 7)
            Text(Format.percent(fraction))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(Format.percent(fraction))
    }
}
