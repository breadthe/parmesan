import AppKit
import SwiftUI

/// Confirms Move to Trash with the space it frees (see specs.md → Actions & Shortcuts, Safety). Items in
/// system locations get a warning, and the button only works while ⌥ is held.
struct TrashSheet: View {
    let request: BrowserModel.TrashRequest
    let perform: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isOptionDown = NSEvent.modifierFlags.contains(.option)
    @State private var monitor: Any?

    private var isAllowed: Bool { !request.hasProtectedItems || isOptionDown }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.items.count == 1
                         ? String(localized: "Move “\(request.items[0].name)” to the Trash?")
                         : String(localized: "Move \(request.items.count) items to the Trash?"))
                        .font(.headline)
                    Text("This frees about \(Format.size(request.total)) once the Trash is emptied. You can put items back from the Trash in Finder.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if request.items.count > 1 {
                List(request.items) { item in
                    HStack {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.size(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .frame(height: min(CGFloat(request.items.count) * 24 + 10, 200))
            }
            if request.hasProtectedItems {
                Label {
                    Text("Some of these are system files. Removing them can break macOS or apps. Hold ⌥ to enable the button if you're sure.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) {
                    dismiss()
                    perform()
                }
                .keyboardShortcut(request.hasProtectedItems ? nil : .defaultAction)
                .disabled(!isAllowed)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionDown = event.modifierFlags.contains(.option)
                return event
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
