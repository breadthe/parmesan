import SwiftUI

/// Toolbar ⓘ: what the current color scheme means (see specs.md → Color Coding).
struct LegendView: View {
    let mode: ColorMode
    @Environment(\.chartPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode.label).font(.headline)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(palette.legend(mode).enumerated()), id: \.offset) { _, entry in
                swatch(entry.0.color, entry.1)
            }
            Divider()
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(palette.restricted.color)
                    Hatch().stroke(.black.opacity(0.25), lineWidth: 1).clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(width: 18, height: 14)
                Text("Restricted (not counted)")
            }
            swatch(palette.smaller.color, String(localized: "Smaller items, grouped"))
            Text("Folders with their contents drawn around them are slightly muted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
    }

    private var explanation: String {
        switch mode {
        case .size: String(localized: "Each item's share of the folder it's in: pale cream for small, deep rind brown for most of it.")
        case .kind: String(localized: "What kind of file takes the space. Folders take the color of what fills them most.")
        case .age: String(localized: "When items were last modified. Folders show the size-weighted age of their contents.")
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.15)))
                .frame(width: 18, height: 14)
            Text(label)
        }
    }
}

private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return path
    }
}
