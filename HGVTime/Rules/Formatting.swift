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
