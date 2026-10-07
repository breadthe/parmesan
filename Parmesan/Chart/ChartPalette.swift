import AppKit
import SwiftUI

/// An sRGB color the chart can interpolate and test for contrast.
struct RGB: Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        (self.r, self.g, self.b) = (r, g, b)
    }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .gray
        self.init(r: Double(srgb.redComponent), g: Double(srgb.greenComponent), b: Double(srgb.blueComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Moves towards gray of the same lightness; folders in inner rings use this so leaves stand out.
    func desaturated(_ amount: Double) -> RGB {
        let gray = 0.299 * r + 0.587 * g + 0.114 * b
        return mixed(with: RGB(r: gray, g: gray, b: gray), amount)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// Black or white, whichever contrasts more with this fill (see specs.md → Color Coding, WCAG AA).
    var labelColor: Color {
        let l = luminance
        let onBlack = (l + 0.05) / 0.05
        let onWhite = 1.05 / (l + 0.05)
        return onBlack >= onWhite ? Color.black.opacity(0.85) : .white
    }

    static func ramp(_ stops: [RGB], _ t: Double) -> RGB {
        guard stops.count > 1 else { return stops.first ?? RGB(r: 0.5, g: 0.5, b: 0.5) }
        let x = min(max(t, 0), 1) * Double(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        return stops[i].mixed(with: stops[i + 1], x - Double(i))
    }
}

/// What a chart color is worked out from; shared by chart segments and table rows.
struct ColorInputs {
    var share: Double
    var dominant: NodeKind
    var ageTime: Int32
    var flags: NodeFlags
    var isOther = false
}

/// The chart colors for one appearance, resolved from the asset catalog (see specs.md → Color Coding).
struct ChartPalette: Equatable {
    var sizeRamp: [RGB]
    var kinds: [RGB]
    var ageRamp: [RGB]
    var restricted: RGB
    var smaller: RGB

    static func resolve(dark: Bool) -> ChartPalette {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var palette = ChartPalette.fallback
        appearance.performAsCurrentDrawingAppearance {
            func named(_ name: String) -> RGB {
                NSColor(named: name).map(RGB.init) ?? RGB(r: 0.6, g: 0.6, b: 0.6)
            }
            palette = ChartPalette(
                sizeRamp: (1 ... 5).map { named("SizeRamp\($0)") },
                kinds: ["Folders", "Packages", "Images", "Video", "Audio", "Documents", "Archives", "Code", "System", "Other"]
                    .map { named("Kind\($0)") },
                ageRamp: (1 ... 5).map { named("Age\($0)") },
                restricted: named("Restricted"),
                smaller: named("SmallerItems"))
        }
        return palette
    }

    static let fallback = ChartPalette(
        sizeRamp: [RGB(r: 0.96, g: 0.93, b: 0.82), RGB(r: 0.55, g: 0.23, b: 0.11)],
        kinds: Array(repeating: RGB(r: 0.6, g: 0.6, b: 0.6), count: KindCategory.allCases.count),
        ageRamp: [RGB(r: 0.24, g: 0.49, b: 0.85), RGB(r: 0.64, g: 0.14, b: 0.17)],
        restricted: RGB(r: 0.7, g: 0.7, b: 0.7), smaller: RGB(r: 0.86, g: 0.86, b: 0.86))

    func fill(_ input: ColorInputs, mode: ColorMode, now: Date = .now) -> RGB {
        if input.isOther { return smaller }
        if input.flags.contains(.restricted) { return restricted }
        switch mode {
        case .size:
            return RGB.ramp(sizeRamp, Self.sizePosition(input.share))
        case .kind:
            return kinds[input.dominant.category.rawValue]
        case .age:
            return RGB.ramp(ageRamp, Self.agePosition(input.ageTime, now: now))
        }
    }

    /// Share of the parent on a log scale: 0.3% or less is palest, the whole parent is darkest.
    static func sizePosition(_ share: Double) -> Double {
        guard share > 0 else { return 0 }
        return min(max((log10(share) + 2.5) / 2.5, 0), 1)
    }

    /// Recent is 0, a year old about 0.62 (warm), three years or more 1 (deep red).
    static func agePosition(_ time: Int32, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince1970 - TimeInterval(time)) / 86_400
        let points: [(Double, Double)] = [(0, 0), (7, 0.12), (30, 0.25), (180, 0.45), (365, 0.62), (1_095, 1)]
        for (a, b) in zip(points, points.dropFirst()) where days <= b.0 {
            return a.1 + (b.1 - a.1) * (days - a.0) / (b.0 - a.0)
        }
        return 1
    }

    /// Legend rows for a color mode: swatch and label.
    func legend(_ mode: ColorMode) -> [(RGB, String)] {
        switch mode {
        case .size:
            return [(sizeRamp[0], String(localized: "Small share of its folder")),
                    (RGB.ramp(sizeRamp, 0.35), String(localized: "About 3%")),
                    (RGB.ramp(sizeRamp, 0.6), String(localized: "About 10%")),
                    (RGB.ramp(sizeRamp, 0.8), String(localized: "About 30%")),
                    (sizeRamp[sizeRamp.count - 1], String(localized: "Most of its folder"))]
        case .kind:
            return KindCategory.allCases.map { (kinds[$0.rawValue], $0.label) }
        case .age:
            let now = Date.now
            func at(_ days: Double) -> RGB { RGB.ramp(ageRamp, Self.agePosition(Int32(now.timeIntervalSince1970 - days * 86_400), now: now)) }
            return [(at(0), String(localized: "Modified this week")), (at(30), String(localized: "About a month ago")),
                    (at(180), String(localized: "About six months ago")), (at(365), String(localized: "A year ago")),
                    (at(1_095), String(localized: "Three years or more"))]
        }
    }
}

extension EnvironmentValues {
    @Entry var chartPalette = ChartPalette.fallback
}

extension SegmentInfo {
    var colorInputs: ColorInputs {
        ColorInputs(share: shareOfParent, dominant: dominant, ageTime: ageTime, flags: flags, isOther: isOther)
    }
}
