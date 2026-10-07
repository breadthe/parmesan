import SwiftUI

/// The context menu for chart segments and table rows (see specs.md → Actions & Shortcuts).
struct ItemActionsMenu: View {
    let model: BrowserModel
    let ids: [NodeID]

    var body: some View {
        if !ids.isEmpty {
            if ids.count == 1, let id = ids.first, isFolder(id) {
                Button("Drill In") { model.activate(id) }
            }
            Button("Open") { model.open(ids) }
            Button("Reveal in Finder") { model.revealInFinder(ids) }
            Button("Open in Terminal") { model.openInTerminal(ids) }
            Button("Quick Look") { model.quickLook(ids) }
            Button("Get Info") { model.getInfo(ids) }
            Divider()
            Button("Copy Path") { model.copyPaths(ids) }
            Button("Copy Size Summary") { model.copySizeSummary(ids) }
            Divider()
            Button("Move to Trash…") { model.requestTrash(ids) }
                .disabled(!model.canTrash(ids))
        }
    }

    private func isFolder(_ id: NodeID) -> Bool {
        model.tree?.read { $0.isDirectory(id) && !$0.flags[Int(id)].contains(.restricted) } ?? false
    }
}
