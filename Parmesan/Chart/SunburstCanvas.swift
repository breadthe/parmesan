import SwiftUI

/// Pixel geometry of a sunburst in a view: center disc, then equal-width rings.
struct SunburstFrame {
    let center: CGPoint
    let outer: CGFloat
    let inner: CGFloat
    let ringWidth: CGFloat

    enum Hit {
        case center
        case ring(Int, angle: Double)
        case outside
    }

    init(size: CGSize, rings: Int) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        outer = max(20, min(size.width, size.height) / 2 - 10)
        inner = max(outer * 0.2, min(44, outer * 0.4))
        ringWidth = (outer - inner) / CGFloat(max(rings, 1))
    }

    func radii(_ ring: Int) -> (CGFloat, CGFloat) {
        (inner + ringWidth * CGFloat(ring - 1), inner + ringWidth * CGFloat(ring))
    }

    /// `angle` is 0 at 12 o'clock, increasing clockwise.
    func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    func path(_ segment: ArcSegment) -> Path {
        let (r0, r1) = radii(segment.ring)
        var path = Path()
        path.move(to: point(segment.start, r1))
        // In a y-down space a positive delta runs clockwise, matching the layout's angles.
        path.addRelativeArc(center: center, radius: r1, startAngle: .radians(segment.start - .pi / 2),
                            delta: .radians(segment.end - segment.start))
        path.addLine(to: point(segment.end, r0))
        path.addRelativeArc(center: center, radius: r0, startAngle: .radians(segment.end - .pi / 2),
                            delta: .radians(segment.start - segment.end))
        path.closeSubpath()
        return path
    }

    func hit(_ location: CGPoint, rings: Int) -> Hit {
        let dx = location.x - center.x, dy = location.y - center.y
        let radius = hypot(dx, dy)
        if radius < inner { return .center }
        guard radius <= inner + ringWidth * CGFloat(rings) else { return .outside }
        var angle = atan2(Double(dx), Double(-dy))
        if angle < 0 { angle += 2 * .pi }
        return .ring(min(Int((radius - inner) / ringWidth) + 1, rings), angle: angle)
    }
}

/// Draws a `SunburstGeometry` (see specs.md → Visualization, Sunburst).
struct SunburstCanvas: View {
    let geometry: SunburstGeometry
    let style: ChartStyle

    var body: some View {
        Canvas { context, size in
            let frame = SunburstFrame(size: size, rings: geometry.rings)
            let separator = GraphicsContext.Shading.color(style.separator)
            let highlighted = Set(style.hovered.map(geometry.lineage(of:)) ?? [])

            for (index, segment) in geometry.segments.enumerated() {
                let path = frame.path(segment)
                let fill = style.fill(segment.info, inner: segment.hasChildren)
                context.fill(path, with: .color(fill.color))
                if segment.info.flags.contains(.restricted) { style.hatch(path, in: &context) }
                if segment.info.flags.contains(.incomplete) {
                    context.fill(path, with: .color(.white.opacity(0.12 + 0.18 * style.pulse)))
                }
                if highlighted.contains(index) {
                    context.fill(path, with: .color(.white.opacity(index == style.hovered ? 0.32 : 0.16)))
                }
                context.stroke(path, with: separator, lineWidth: style.separatorWidth)
            }
            for segment in geometry.segments where style.isSelected(segment.node, isOther: segment.info.isOther) {
                context.stroke(frame.path(segment), with: .color(.accentColor), lineWidth: 2.5)
            }
            if style.showLabels || style.differentiateWithoutColor {
                drawLabels(&context, frame: frame)
            }
            drawCenter(&context, frame: frame)
        }
    }

    private func drawLabels(_ context: inout GraphicsContext, frame: SunburstFrame) {
        guard frame.ringWidth >= 13 else { return }
        for segment in geometry.segments {
            let mid = (segment.start + segment.end) / 2
            let (r0, r1) = frame.radii(segment.ring)
            let radius = (r0 + r1) / 2
            let arcLength = CGFloat(segment.end - segment.start) * radius
            guard arcLength > 26 else { continue }
            // Horizontal text: near the top and bottom the arc runs sideways and limits the width; towards
            // the sides the ring does.
            let across = abs(CGFloat(cos(mid))), along = abs(CGFloat(sin(mid)))
            let width = min(arcLength, frame.ringWidth / max(along, 0.2)) - 6
            let height = min(frame.ringWidth / max(across, 0.2), arcLength) - 2
            guard width > 18, height > 11 else { continue }
            guard let label = style.label(for: segment.info) else { continue }
            let fill = style.fill(segment.info, inner: segment.hasChildren)
            style.drawFitted(label, at: frame.point(mid, radius), maxWidth: width, color: fill.labelColor, in: &context)
        }
    }

    private func drawCenter(_ context: inout GraphicsContext, frame: SunburstFrame) {
        let disc = Path(ellipseIn: CGRect(x: frame.center.x - frame.inner, y: frame.center.y - frame.inner,
                                          width: frame.inner * 2, height: frame.inner * 2).insetBy(dx: 1, dy: 1))
        context.fill(disc, with: .color(style.centerFill))
        if style.isHoveringCenter {
            context.fill(disc, with: .color(.primary.opacity(0.06)))
        }
        let width = frame.inner * 1.7
        style.drawFitted(geometry.focusInfo.name, at: CGPoint(x: frame.center.x, y: frame.center.y - 8), maxWidth: width,
                         color: .primary, font: .system(size: 12, weight: .semibold), in: &context)
        style.drawFitted(Format.size(geometry.focusInfo.size(geometry.mode)), at: CGPoint(x: frame.center.x, y: frame.center.y + 9),
                         maxWidth: width, color: .secondary, font: .system(size: 11), in: &context)
    }
}
