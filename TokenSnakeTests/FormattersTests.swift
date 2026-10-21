import Foundation
import Testing
@testable import TokenSnake

struct FormattersTests {
    @Test func subscriptionPricesKeepCents() {
        #expect(Formatters.monthlyCurrency(12.5) == "$12.50")
        #expect(Formatters.monthlyCurrency(19.99) == "$19.99")
    }
    @Test(arguments: [
        (0, "0"),
        (999, "999"),
        (1_000, "1.0k"),
        (12_400, "12.4k"),
        (1_000_000, "1.0M"),
        (1_234_000_000, "1.23B"),
        (-2_500, "-2.5k")
    ])
    func compactTokens(_ value: Int, expected: String) {
        #expect(Formatters.compactTokens(value) == expected)
    }

    @Test func currencyBranches() {
        #expect(Formatters.currency(0) == "$0")
        #expect(Formatters.currency(0.004) == "$0.004")
        #expect(Formatters.currency(1.5) == "$1.50")
        #expect(Formatters.currency(12.3) == "$12")
        #expect(Formatters.currency(1.5, code: "TWD") == "$1.50")
    }

    @Test func datesAreNonEmpty() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(!Formatters.shortDate(date).isEmpty)
        #expect(!Formatters.time(date).isEmpty)
        #expect(!Formatters.relative(date).isEmpty)
    }

    @Test func calendarStartOfMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let start = calendar.startOfMonth(for: date)
        #expect(calendar.component(.day, from: start) == 1)
    }

    @Test func safeSubscript() {
        let values = [1, 2]
        #expect(values[safe: 0] == 1)
        #expect(values[safe: 1] == 2)
        #expect(values[safe: 2] == nil)
        #expect(values[safe: -1] == nil)
    }
}
