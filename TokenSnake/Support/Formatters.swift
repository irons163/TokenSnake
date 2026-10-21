import Foundation

enum Formatters {
    static func compactTokens(_ value: Int) -> String {
        let n = Double(value)
        if abs(n) >= 1_000_000_000 { return String(format: "%.2fB", n / 1_000_000_000) }
        if abs(n) >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if abs(n) >= 1_000 { return String(format: "%.1fk", n / 1_000) }
        return "\(value)"
    }

    static func currency(_ value: Double, code: String = "USD") -> String {
        if value == 0 { return "$0" }
        if abs(value) < 0.01 { return String(format: "$%.3f", value) }
        if abs(value) < 10 { return String(format: "$%.2f", value) }
        return String(format: "$%.0f", value)
    }

    static func monthlyCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hant")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
