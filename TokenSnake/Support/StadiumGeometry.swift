import Foundation

enum StadiumGeometry {
    static func rect(in size: CGSize) -> CGRect {
        CGRect(x: 22, y: 28, width: size.width - 44, height: size.height - 56)
    }

    static func point(progress: Double, in rect: CGRect) -> CGPoint {
        let r = Double(rect.height / 2)
        let straight = max(Double(rect.width) - 2 * r, 1)
        let halfCircle = Double.pi * r
        let total = 2 * straight + 2 * halfCircle
        var d = progress.truncatingRemainder(dividingBy: 1)
        if d < 0 { d += 1 }
        var dist = d * total

        if dist <= straight {
            return CGPoint(x: Double(rect.minX) + r + dist, y: Double(rect.minY))
        }
        dist -= straight
        if dist <= halfCircle {
            let angle = -Double.pi / 2 + dist / r
            return CGPoint(
                x: Double(rect.maxX) - r + r * cos(angle),
                y: Double(rect.minY) + r + r * sin(angle)
            )
        }
        dist -= halfCircle
        if dist <= straight {
            return CGPoint(x: Double(rect.maxX) - r - dist, y: Double(rect.maxY))
        }
        dist -= straight
        let angle = Double.pi / 2 + dist / r
        return CGPoint(
            x: Double(rect.minX) + r + r * cos(angle),
            y: Double(rect.minY) + r + r * sin(angle)
        )
    }
}

enum HeatmapPalette {
    static func color(value: Double, isFuture: Bool) -> ColorToken {
        if isFuture { return .future }
        if value <= 0 { return .empty }
        if value < 0.4 { return .low }
        if value < 0.8 { return .mid }
        return .high
    }
}

enum ColorToken: String, Equatable {
    case future
    case empty
    case low
    case mid
    case high
}

enum HeatmapGrid {
    static func date(
        week: Int,
        day: Int,
        weeks: Int = 13,
        today: Date,
        calendar: Calendar = .current
    ) -> Date {
        let weekday = calendar.component(.weekday, from: today)
        let mondayIndex = (weekday + 5) % 7
        let offset = (weeks - 1 - week) * 7 + (mondayIndex - day)
        return calendar.date(byAdding: .day, value: -offset, to: today) ?? today
    }
}
