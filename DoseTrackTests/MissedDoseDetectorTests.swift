import XCTest
@testable import DoseTrack

final class MissedDoseDetectorTests: XCTestCase {
    func test_dosePastSixtyMinutesWithNoLogIsOverdue() {
        let scheduledAt = Date().addingTimeInterval(-61 * 60)
        let result = MissedDoseDetector.overdueOccurrences(
            scheduledTimes: [scheduledAt], loggedTimes: [], now: Date()
        )
        XCTAssertEqual(result, [scheduledAt])
    }

    func test_doseWithMatchingLogIsNotOverdue() {
        let scheduledAt = Date().addingTimeInterval(-61 * 60)
        let result = MissedDoseDetector.overdueOccurrences(
            scheduledTimes: [scheduledAt], loggedTimes: [scheduledAt], now: Date()
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_doseUnderSixtyMinutesIsNotYetOverdue() {
        let scheduledAt = Date().addingTimeInterval(-30 * 60)
        let result = MissedDoseDetector.overdueOccurrences(
            scheduledTimes: [scheduledAt], loggedTimes: [], now: Date()
        )
        XCTAssertTrue(result.isEmpty)
    }
}
