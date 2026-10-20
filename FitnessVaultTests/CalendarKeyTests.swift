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

    func testWallClockTimesSurviveTheClockChange() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        // The clocks go back at 02:00 on 25 October 2026, so that day is 25 hours long.
        let changeDay = DayKey(year: 2026, month: 10, day: 25)
        let eight = changeDay.date(atMinute: 8 * 60, calendar: london)
        XCTAssertEqual(london.component(.hour, from: eight), 8)
        XCTAssertEqual(london.component(.minute, from: eight), 0)
        XCTAssertEqual(DayKey(eight, calendar: london), changeDay)
    }

    @MainActor
    func testSettlementStaysAtEightOnTheClockChange() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let store = SettingsStore(defaults: UserDefaults(suiteName: "settle.\(UUID().uuidString)")!)
        let saturdayEvening = DayKey(year: 2026, month: 10, day: 24).date(atMinute: 20 * 60, calendar: london)
        let next = store.nextSettlement(after: saturdayEvening, calendar: london)
        XCTAssertEqual(DayKey(next, calendar: london), DayKey(year: 2026, month: 10, day: 25))
        XCTAssertEqual(london.component(.hour, from: next), 8)
    }
}
