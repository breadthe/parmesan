import SwiftUI

/// What both chart canvases need to draw: colors, hover and selection, labels and accessibility options.
struct ChartStyle {
    var palette: ChartPalette
    var colorMode: ColorMode
    var hovered: Int?
    var isHoveringCenter = false
    var selection: Set<NodeID>
    var showLabels: Bool
    var differentiateWithoutColor: Bool
    var increaseContrast: Bool
    /// 0…1, for the "still scanning" pulse on unfinished folders.
    var pulse: Double
    var separator: Color
    var centerFill: Color
    var now = Date.now

    var separatorWidth: CGFloat { increaseContrast ? 1.6 : 0.8 }

    /// Folders that show their children around them are slightly desaturated, so leaves stand out.
    func fill(_ info: SegmentInfo, inner: Bool) -> RGB {
        let base = palette.fill(info.colorInputs, mode: colorMode, now: now)
        return inner && !info.isOther && !info.flags.contains(.restricted) ? base.desaturated(0.28) : base
    }

    func isSelected(_ node: NodeID, isOther: Bool) -> Bool {
        !isOther && selection.contains(node)
    }

    /// The text drawn on a segment: its name, prefixed with a kind tag when Differentiate Without Color
    /// is on in By Kind (see specs.md → Accessibility).
    func label(for info: SegmentInfo) -> String? {
        let tag = differentiateWithoutColor && colorMode == .kind && !info.isOther ? info.dominant.category.abbreviation : nil
        switch (showLabels, tag) {
        case (true, let tag?): return "\(tag) · \(info.name)"
        case (true, nil): return info.name
        case (false, let tag?): return tag
        case (false, nil): return nil
        }
    }

    /// Restricted folders: neutral gray with diagonal hatching.
    func hatch(_ path: Path, in context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.clip(to: path)
            let bounds = path.boundingRect
            var lines = Path()
            var x = bounds.minX - bounds.height
            while x < bounds.maxX {
                lines.move(to: CGPoint(x: x, y: bounds.maxY))
                lines.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
                x += 6
            }
            layer.stroke(lines, with: .color(.black.opacity(0.22)), lineWidth: 1.2)
        }
    }

    /// Draws `string` centered at `point`, shortened with "…" to fit `maxWidth`, or not at all.
    func drawFitted(_ string: String, at point: CGPoint, maxWidth: CGFloat, color: Color,
                    font: Font = .system(size: 10.5, weight: .medium), in context: inout GraphicsContext) {
        guard maxWidth > 12, !string.isEmpty else { return }
        var text = context.resolve(Text(string).font(font).foregroundStyle(color))
        var width = text.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100)).width
        if width > maxWidth {
            let keep = Int(Double(string.count) * Double(maxWidth / width)) - 1
            guard keep >= 3 else { return }
            text = context.resolve(Text(String(string.prefix(keep)) + "…").font(font).foregroundStyle(color))
            width = text.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 100)).width
            guard width <= maxWidth else { return }
        }
        context.draw(text, at: point, anchor: .center)
    }
}
