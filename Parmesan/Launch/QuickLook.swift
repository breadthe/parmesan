import AppKit
import QuickLookUI

/// Feeds `QLPreviewPanel`. The app delegate takes control of the panel through the responder chain
/// (see `AppDelegate.acceptsPreviewPanelControl`) and hands it this data source.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()

    private(set) var urls: [URL] = []

    /// Shows the panel for `urls`, or hides it if it's already showing them (Space toggles, as in Finder).
    func toggle(_ urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible, urls == self.urls {
            panel.orderOut(nil)
            return
        }
        self.urls = urls
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
