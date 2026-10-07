#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: drives a window from `PARMESAN_SCRIPT` and saves window snapshots to
/// `PARMESAN_SNAPSHOT_DIR`, for checking layouts and making the README screenshots without screen
/// recording permission. Steps are separated by `;`, e.g.
///
///     PARMESAN_SNAPSHOT_DIR=/tmp/shots PARMESAN_SCRIPT='scan:demo;wait:3;snap:main;drill:Movies;snap:movies;quit' \
///       open build/Build/Products/Debug/Parmesan.app
///
/// Steps: `scan:<path>` (waits for it), `start:<path>` (doesn't), `trash:<name>`, `wait:<seconds>`, `select:<name>`, `drill:<name>`, `up`, `chart:<sunburst|treemap>`,
/// `color:<size|kind|age>`, `largest:<on|off>`, `layout:<sideBySide|stacked|tableOnly>`, `appearance:<light|dark|system>`,
/// `size:<width>x<height>`, `settings:<tab index>`, `legend`, `snap:<name>`, `quit`.
@MainActor
enum DebugScript {
    static weak var model: BrowserModel?
    private static var openSettings: OpenSettingsAction?
    private static var started = false

    static func register(_ model: BrowserModel, openSettings: OpenSettingsAction) {
        self.model = model
        self.openSettings = openSettings
        guard !started, let script = ProcessInfo.processInfo.environment["PARMESAN_SCRIPT"] else { return }
        started = true
        let steps = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task {
            try? await Task.sleep(for: .seconds(1))
            for step in steps { await run(step) }
        }
    }

    private static func run(_ step: String) async {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let command = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""
        guard let model else { return }
        switch command {
        case "scan":
            model.startScan(URL(fileURLWithPath: (argument as NSString).expandingTildeInPath))
            while model.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
        case "wait":
            try? await Task.sleep(for: .seconds(Double(argument) ?? 1))
            return
        case "select":
            if let row = model.rows.first(where: { $0.name == argument }) { model.select(row.id) }
        case "drill":
            if let row = model.rows.first(where: { $0.name == argument }) { model.activate(row.id) }
        case "up":
            model.goUp()
        case "trash":
            // Straight to the Trash, no sheet: checks totals update in place.
            if let row = model.rows.first(where: { $0.name == argument }) {
                model.performTrash(.init(items: [.init(id: row.id, name: row.name, path: row.path, size: row.size, isProtected: false)]))
            }
        case "start":
            // Starts a scan without waiting for it, to see the scanning state.
            model.startScan(URL(fileURLWithPath: (argument as NSString).expandingTildeInPath))
        case "chart":
            model.chartMode = ChartMode(rawValue: argument) ?? .sunburst
        case "color":
            model.colorMode = ColorMode(rawValue: argument) ?? .size
        case "largest":
            model.flattened = argument == "on"
        case "layout":
            model.layout = LayoutMode(rawValue: argument) ?? .sideBySide
        case "appearance":
            Appearance.apply(argument)
        case "size":
            let dims = argument.split(separator: "x").compactMap { Double($0) }
            if dims.count == 2, let window = mainWindow {
                var frame = window.frame
                frame.size = CGSize(width: dims[0], height: dims[1])
                window.setFrame(frame, display: true)
            }
        case "settings":
            openSettings?()
            try? await Task.sleep(for: .milliseconds(800))
            UserDefaults.standard.set(Int(argument) ?? 0, forKey: "settingsTab")
        case "legend":
            model.isShowingLegend.toggle()
        case "snap":
            try? await Task.sleep(for: .milliseconds(700))
            snapshot(argument)
        case "quit":
            NSApp.terminate(nil)
        default:
            print("DebugScript: unknown step \(step)")
        }
        try? await Task.sleep(for: .milliseconds(500))
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(WindowID.browser) == true }
            ?? NSApp.mainWindow
    }

    /// Saves every visible window, title bar and toolbar included, as `<name>-<n>.png`.
    private static func snapshot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PARMESAN_SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 200 }
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let suffix = windows.count > 1 ? "-\(index)" : ""
            let url = URL(fileURLWithPath: directory).appending(path: "\(name)\(suffix).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
#endif
