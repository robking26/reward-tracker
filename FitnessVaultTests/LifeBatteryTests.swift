import XCTest
@testable import FitnessVault

final class LifeBatteryTests: XCTestCase {
    let london = PlannerFixtures().london
    /// Monday 2 November 2026.
    let monday = PlannerFixtures().monday

    private func day(_ offset: Int) -> DayKey { monday.adding(days: offset, calendar: london) }

    private func compute(_ days: [Int: BatteryDay], start: Int = 0, today: Int, perWeek: Int = 3) -> BatteryResult {
        var keyed: [DayKey: BatteryDay] = [:]
        for (offset, record) in days { keyed[day(offset)] = record }
        return LifeBattery.compute(start: day(start), today: day(today), days: keyed, gymPerWeek: perWeek, calendar: london)
    }

    private func walked(gym: Bool = false, swim: Bool = false, run: Bool = false, steps: Int = 9_000) -> BatteryDay {
        BatteryDay(gym: gym, swim: swim, run: run, steps: steps, stepTarget: 8_000)
    }

    func testStartsEmptyAndTheGymSwimsAndRunsCharge() {
        XCTAssertEqual(compute([:], today: 0).percent, 0)
        let result = compute([0: walked(gym: true), 1: walked(swim: true, run: true)], today: 1)
        XCTAssertEqual(result.percent, 1, "0.5 + 0.25 + 0.25")
        XCTAssertEqual(result.events.first?.kind, .run, "Newest first")
    }

    func testAFullWeekOnTargetNeverLoses() {
        let week = [0: walked(gym: true), 1: walked(), 2: walked(gym: true), 3: walked(), 4: walked(gym: true), 5: walked(),
                    6: walked()]
        XCTAssertEqual(compute(week, today: 7).percent, 1.5)
    }

    func testMissedGymSessionsCountAtTheEndOfTheWeek() {
        let week = [0: walked(gym: true), 1: walked(gym: true), 2: walked(gym: true), 3: walked(gym: true), 4: walked(),
                    5: walked(), 6: walked()]
        let partWay = compute([0: walked(gym: true)], today: 3)
        XCTAssertEqual(partWay.percent, 0.5, "Nothing lost mid-week")
        let oneSession = (0...6).reduce(into: [Int: BatteryDay]()) { $0[$1] = walked(gym: $1 == 0) }
        XCTAssertEqual(compute(oneSession, today: 6).percent, 0.5, "Sunday isn't over yet")
        XCTAssertEqual(compute(oneSession, today: 7).percent, 0, "Two missed: −1%, floored at empty")
        XCTAssertEqual(compute(week, today: 7).percent, 2, "Four sessions: +2%, nothing missed")
    }

    func testMissedStepsDrainOnceTheDayIsOver() {
        let days = [0: walked(gym: true), 1: walked(gym: true), 2: walked(steps: 3_000)]
        XCTAssertEqual(compute(days, today: 2).percent, 1, "Today isn't over")
        XCTAssertEqual(compute(days, today: 3).percent, 0.75)
        XCTAssertEqual(compute([0: BatteryDay(steps: 100, stepTarget: nil)], today: 1).percent, 0, "No target known: no loss")
    }

    func testNeverBelowEmptyOrAboveFull() {
        let lazy = (0...13).reduce(into: [Int: BatteryDay]()) { $0[$1] = walked(steps: 0) }
        XCTAssertEqual(compute(lazy, today: 14).percent, 0)
        XCTAssertTrue(compute(lazy, today: 14).events.isEmpty, "Losses at 0% aren't listed")
        let keen = (0...400).reduce(into: [Int: BatteryDay]()) { $0[$1] = walked(gym: true, swim: true, run: true) }
        XCTAssertEqual(compute(keen, today: 400).percent, 100)
    }

    func testAPartWeekStartAsksForItsShare() {
        XCTAssertEqual(LifeBattery.weeklyTarget(3, days: 3), 1, "Friday to Sunday")
        XCTAssertEqual(LifeBattery.weeklyTarget(3, days: 7), 3)
        // Started on Friday with no gym: one session missed on Sunday, from empty, stays empty.
        let friday = [4: walked(), 5: walked(swim: true), 6: walked()]
        XCTAssertEqual(compute(friday, start: 4, today: 7).percent, 0)
        let fridayGym = [4: walked(gym: true), 5: walked(swim: true), 6: walked()]
        XCTAssertEqual(compute(fridayGym, start: 4, today: 7).percent, 0.75)
    }

    func testProjectionAndThisWeek() {
        let days = (0...13).reduce(into: [Int: BatteryDay]()) { $0[$1] = walked(gym: [0, 2, 4, 7, 9, 11].contains($1)) }
        let result = compute(days, today: 13)
        XCTAssertEqual(result.percent, 3)
        XCTAssertEqual(LifeBattery.change(result, since: day(7)), 1.5)
        let projected = LifeBattery.projection(result, today: day(13), end: day(365), calendar: london)
        XCTAssertNotNil(projected)
        XCTAssertGreaterThan(projected ?? 0, 70)
        XCTAssertNil(LifeBattery.projection(compute([:], today: 2), today: day(2), end: day(365), calendar: london))
    }

    func testFormatting() {
        XCTAssertEqual(BatteryStyle.percent(12), "12%")
        XCTAssertEqual(BatteryStyle.percent(12.5), "12.5%")
        XCTAssertEqual(BatteryStyle.percent(12.25), "12.25%")
        XCTAssertEqual(BatteryStyle.signed(-0.75), "−0.75%")
        XCTAssertEqual(BatteryStyle.signed(0), "±0%")
    }
}
