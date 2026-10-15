import XCTest
@testable import FitnessVault

final class MealRewardTests: XCTestCase {
    func testFirstThreeDistinctMealsEarn() {
        let earlier: [(hash: UInt64, eligible: Bool)] = [(0x0000_0000_0000_FFFF, true), (0xFFFF_0000_0000_0000, true)]
        XCTAssertEqual(MealRewardPolicy.outcome(hash: 0x0000_FFFF_0000_0000, earlierMealsToday: earlier, limit: 3), .eligible)
    }

    func testFourthMealDoesNotEarn() {
        let earlier: [(hash: UInt64, eligible: Bool)] = [
            (0x0000_0000_0000_FFFF, true), (0xFFFF_0000_0000_0000, true), (0x0000_FFFF_0000_0000, true),
        ]
        XCTAssertEqual(MealRewardPolicy.outcome(hash: 0x0000_0000_FFFF_0000, earlierMealsToday: earlier, limit: 3), .dailyLimitReached)
    }

    func testRepeatPhotoOfSameMealDoesNotEarn() {
        let earlier: [(hash: UInt64, eligible: Bool)] = [(0x0F0F_0F0F_0F0F_0F0F, true)]
        XCTAssertEqual(MealRewardPolicy.outcome(hash: 0x0F0F_0F0F_0F0F_0F0E, earlierMealsToday: earlier, limit: 3), .duplicate)
    }

    func testHammingDistance() {
        XCTAssertEqual(ImageFingerprint.distance(0b1010, 0b0101), 4)
        XCTAssertEqual(ImageFingerprint.distance(42, 42), 0)
    }
}
