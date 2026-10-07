import SwiftUI

/// Draws a `TreemapGeometry` with cushion shading and folder header strips (see specs.md → Visualization, Treemap).
struct TreemapCanvas: View {
    let geometry: TreemapGeometry
    let style: ChartStyle

    var body: some View {
        Canvas { context, _ in
            let highlighted = Set(style.hovered.map(geometry.lineage(of:)) ?? [])
            // Parents come before their children, so folders are painted first and their contents on top.
            for (index, segment) in geometry.segments.enumerated() {
                let rect = segment.rect
                guard rect.width >= 0.5, rect.height >= 0.5 else { continue }
                let path = Path(rect)
                let isFolder = !segment.children.isEmpty || segment.header != nil
                let fill = style.fill(segment.info, inner: isFolder)
                context.fill(path, with: .color(isFolder ? fill.mixed(with: RGB(r: 0, g: 0, b: 0), 0.12).color : fill.color))
                if !isFolder, rect.width > 6, rect.height > 6 {
                    cushion(rect, in: &context)
                }
                if segment.info.flags.contains(.restricted) { style.hatch(path, in: &context) }
                if segment.info.flags.contains(.incomplete) {
                    context.fill(path, with: .color(.white.opacity(0.12 + 0.18 * style.pulse)))
                }
                if let header = segment.header {
                    context.fill(Path(header), with: .color(fill.color))
                    if let label = style.label(for: segment.info) {
                        let text = "\(label)  \(Format.size(segment.info.size))"
                        style.drawFitted(text, at: CGPoint(x: header.midX, y: header.midY), maxWidth: header.width - 8,
                                         color: fill.labelColor, in: &context)
                    }
                } else if !isFolder, rect.width > 44, rect.height > 26, let label = style.label(for: segment.info) {
                    style.drawFitted(label, at: CGPoint(x: rect.midX, y: rect.midY - 6), maxWidth: rect.width - 8,
                                     color: fill.labelColor, in: &context)
                    style.drawFitted(Format.size(segment.info.size), at: CGPoint(x: rect.midX, y: rect.midY + 7),
                                     maxWidth: rect.width - 8, color: fill.labelColor.opacity(0.75),
                                     font: .system(size: 9.5), in: &context)
                }
                if highlighted.contains(index) {
                    context.fill(path, with: .color(.white.opacity(index == style.hovered ? 0.3 : 0.12)))
                }
                context.stroke(path, with: .color(style.separator), lineWidth: style.separatorWidth)
            }
            for segment in geometry.segments where style.isSelected(segment.node, isOther: segment.info.isOther) {
                context.stroke(Path(segment.rect.insetBy(dx: 1, dy: 1)), with: .color(.accentColor), lineWidth: 2.5)
            }
        }
    }

    /// A soft radial highlight towards the top left and darker edges, so neighbours read as separate pillows.
    private func cushion(_ rect: CGRect, in context: inout GraphicsContext) {
        let gradient = Gradient(stops: [
            .init(color: .white.opacity(0.22), location: 0),
            .init(color: .white.opacity(0.0), location: 0.55),
            .init(color: .black.opacity(0.16), location: 1),
        ])
        let center = CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.32)
        context.fill(Path(rect), with: .radialGradient(gradient, center: center, startRadius: 0,
                                                       endRadius: max(rect.width, rect.height) * 0.8))
    }
}
