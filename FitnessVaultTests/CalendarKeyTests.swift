import XCTest
@testable import FitnessVault

final class CalendarKeyTests: XCTestCase {
    func testRoundTrip() {
        let day = DayKey(year: 2026, month: 3, day: 9)
        XCTAssertEqual(day.description, "2026-03-09")
        XCTAssertEqual(DayKey(string: "2026-03-09"), day)
    }

    func testDayFollowsLocalTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        // 23:30 UTC on 30 June is 00:30 BST on 1 July: activity belongs to 1 July.
        let date = ISO8601DateFormatter().date(from: "2026-06-30T23:30:00Z")!
        XCTAssertEqual(DayKey(date, calendar: calendar), DayKey(year: 2026, month: 7, day: 1))
    }

    func testMonthNavigation() {
        XCTAssertEqual(MonthKey(year: 2026, month: 12).next, MonthKey(year: 2027, month: 1))
        XCTAssertEqual(MonthKey(year: 2026, month: 1).previous, MonthKey(year: 2025, month: 12))
        XCTAssertEqual(MonthKey(year: 2028, month: 2).days().count, 29)
    }
}
