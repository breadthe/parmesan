import Foundation

/// Sizes, counts, percentages and durations, all through system formatters (see specs.md → Localization).
enum Format {
    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "1,234,567 bytes", for tooltips.
    static func exactBytes(_ bytes: UInt64) -> String {
        String(localized: "\(bytes.formatted(.number)) bytes")
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// 0.312 → "31%"; tiny non-zero shares show as "<1%".
    static func percent(_ fraction: Double) -> String {
        if fraction > 0, fraction < 0.01 { return "<1%" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "18.2 s", or "2 min 5 s" past a minute.
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            let digits = seconds < 1 ? 2 : 1
            return String(localized: "\(seconds.formatted(.number.precision(.fractionLength(digits)))) s")
        }
        return Duration.seconds(Int(seconds.rounded())).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    /// "00:14" for the live elapsed time in the status bar.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Compact count for the Dock badge: "1.2M", "48K".
    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
    }

    /// Shortens a path in the middle: "/Users/me/…/node_modules/react".
    static func middleTruncated(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 3 else { return text }
        let half = (limit - 1) / 2
        return text.prefix(half) + "…" + text.suffix(limit - 1 - half)
    }
}
