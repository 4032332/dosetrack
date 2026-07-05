// DoseTrackTests/SupplyMathTests.swift
import XCTest
@testable import DoseTrack

final class SupplyMathTests: XCTestCase {
    func test_quantityPerDose_dividesTotalByScheduleCount() {
        // 2 tablets, 4x/day => totalDosesPerDay 8, 4 schedules => 2 per dose
        XCTAssertEqual(SupplyMath.quantityPerDose(totalDosesPerDay: 8, enabledScheduleCount: 4), 2)
    }
    func test_quantityPerDose_flooredAtOne_whenScheduleCountZero() {
        XCTAssertEqual(SupplyMath.quantityPerDose(totalDosesPerDay: 0, enabledScheduleCount: 0), 1)
    }
    func test_quantityPerDose_roundsDownButNeverBelowOne() {
        XCTAssertEqual(SupplyMath.quantityPerDose(totalDosesPerDay: 3, enabledScheduleCount: 2), 1)
    }
    func test_decrement_neverBelowZero() {
        XCTAssertEqual(SupplyMath.decrementedCount(current: 1, by: 2), 0)
    }
}
