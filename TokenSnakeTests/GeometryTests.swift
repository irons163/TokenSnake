import Foundation
import Testing
@testable import TokenSnake

struct GeometryTests {
    @Test func stadiumRectInsets() {
        let rect = StadiumGeometry.rect(in: CGSize(width: 200, height: 100))
        #expect(rect.origin.x == 22)
        #expect(rect.origin.y == 28)
        #expect(rect.width == 156)
        #expect(rect.height == 44)
    }

    @Test func stadiumPointStaysOnTrack() {
        let rect = CGRect(x: 20, y: 20, width: 200, height: 80)
        let start = StadiumGeometry.point(progress: 0, in: rect)
        #expect(abs(start.y - rect.minY) < 0.001)

        let bottom = StadiumGeometry.point(progress: 0.5, in: rect)
        #expect(abs(bottom.y - rect.maxY) < 1.5)

        let wrapped = StadiumGeometry.point(progress: 1, in: rect)
        #expect(abs(wrapped.x - start.x) < 0.01)
        #expect(abs(wrapped.y - start.y) < 0.01)

        let negative = StadiumGeometry.point(progress: -0.1, in: rect)
        #expect(rect.insetBy(dx: -2, dy: -2).contains(negative))

        let spilled = StadiumGeometry.point(progress: 2.4, in: rect)
        #expect(rect.insetBy(dx: -2, dy: -2).contains(spilled))
    }

    @Test func heatmapPalette() {
        #expect(HeatmapPalette.color(value: 1, isFuture: true) == .future)
        #expect(HeatmapPalette.color(value: 0, isFuture: false) == .empty)
        #expect(HeatmapPalette.color(value: 0.2, isFuture: false) == .low)
        #expect(HeatmapPalette.color(value: 0.5, isFuture: false) == .mid)
        #expect(HeatmapPalette.color(value: 1, isFuture: false) == .high)
    }

    @Test func heatmapGridTodayIsLastFridayColumn() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 28
        let friday = calendar.date(from: components)!
        let todayCell = HeatmapGrid.date(week: 12, day: 4, weeks: 13, today: friday, calendar: calendar)
        #expect(calendar.isDate(todayCell, inSameDayAs: friday))
        let tomorrow = HeatmapGrid.date(week: 12, day: 5, weeks: 13, today: friday, calendar: calendar)
        #expect(tomorrow > friday)
    }
}
