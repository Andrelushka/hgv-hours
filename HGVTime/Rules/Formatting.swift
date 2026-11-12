import Foundation

/// Shared formatters for durations, times and money.
enum Fmt {
    /// 4h05, 0h45, 56h00
    static func hm(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((max(0, interval) / 60).rounded(.down))
        return String(format: "%dh%02d", totalMinutes / 60, totalMinutes % 60)
    }

    /// 4:05 — compact form for tables.
    static func hmCompact(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((max(0, interval) / 60).rounded(.down))
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    static func decimalHours(_ interval: TimeInterval) -> String {
        String(format: "%.2f", interval / 3600)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dayTime(_ date: Date) -> String {
        "\(day(date)) \(time(date))"
    }

    static func isoDate(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    static func money(_ value: Double, symbol: String) -> String {
        String(format: "%@%.2f", symbol, value)
    }
}

extension Fmt {
    /// Unit choices from Settings → Units (set when settings load or change).
    nonisolated(unsafe) static var heightUnit = "m+ft"
    nonisolated(unsafe) static var distanceBoth = false

    static func applyUnits(_ s: AppSettings) {
        heightUnit = s.heightUnit
        distanceBoth = s.distanceBoth
    }

    /// A height or length in the units chosen in Settings: "4.95 m (16′ 3″)", "16′ 3″ (4.95 m)", "4.95 m" or "16′ 3″".
    /// `feet: false` forces metres only.
    static func length(_ metres: Double, feet: Bool = true) -> String {
        guard metres > 0 else { return "—" }
        let m = String(format: "%.2f m", metres)
        guard feet else { return m }
        let ft = feetInches(metres)
        switch heightUnit {
        case "m": return m
        case "ft": return ft
        case "ft+m": return "\(ft) (\(m))"
        default: return "\(m) (\(ft))"
        }
    }

    /// 16′ 3″
    static func feetInches(_ metres: Double) -> String {
        let totalInches = Int((metres / 0.0254).rounded())
        return "\(totalInches / 12)′ \(totalInches % 12)″"
    }

    /// Distance in km or miles.
    static func distance(_ km: Double, miles: Bool) -> String {
        let mi = String(format: "%.0f mi", km / 1.609344), k = String(format: "%.0f km", km)
        guard distanceBoth else { return miles ? mi : k }
        return miles ? "\(mi) (\(k))" : "\(k) (\(mi))"
    }

    /// Odometer readings stay in one unit (they're what the dashboard shows).
    static func odometer(_ km: Double, miles: Bool) -> String {
        guard km > 0 else { return "—" }
        return miles ? String(format: "%.0f mi", km / 1.609344) : String(format: "%.0f km", km)
    }
}
