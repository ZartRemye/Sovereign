import XCTest
@testable import Sovereign

final class RecoveryAnalyzerTests: XCTestCase {
    func testGoodRecoveryScore() {
        let result = RecoveryAnalyzer.calculate(
            recentSleepHours: [8.0, 8.5, 7.5],
            restingHeartRate: 58,
            restingHRHistory: [60, 61, 59, 60, 62, 60, 61, 59, 60, 60],
            trainingLoadRatio: 0.9,
            hrvValues: [55, 58, 52]
        )

        XCTAssertGreaterThanOrEqual(result.score, 70, "Good sleep, stable HR, moderate load should give high score")
    }

    func testPoorRecoveryScore() {
        let result = RecoveryAnalyzer.calculate(
            recentSleepHours: [5.0, 5.5, 4.5],
            restingHeartRate: 75,
            restingHRHistory: [60, 61, 59, 60, 62, 60, 61, 59, 60, 60],
            trainingLoadRatio: 1.8,
            hrvValues: [20, 22, 18]
        )

        XCTAssertLessThanOrEqual(result.score, 40, "Poor sleep, elevated HR, high load should give low score")
    }

    func testScoreClampedToRange() {
        let result = RecoveryAnalyzer.calculate(
            recentSleepHours: [10, 10, 10],
            restingHeartRate: 45,
            restingHRHistory: [60, 61, 59, 60, 62, 60, 61, 59, 60, 60],
            trainingLoadRatio: 0.5,
            hrvValues: [80, 85, 82]
        )

        XCTAssertGreaterThanOrEqual(result.score, 0)
        XCTAssertLessThanOrEqual(result.score, 100, "Score must be clamped to 0-100")
    }

    func testWithoutHRV() {
        let result = RecoveryAnalyzer.calculate(
            recentSleepHours: [7.5, 8.0, 7.0],
            restingHeartRate: 62,
            restingHRHistory: [60, 61, 59, 60, 62, 60, 61, 59, 60, 60],
            trainingLoadRatio: 1.0,
            hrvValues: nil
        )

        XCTAssertGreaterThanOrEqual(result.score, 0, "Should work without HRV data")
        XCTAssertNil(result.hrvFactor)
    }

    func testProvidesExplanation() {
        let result = RecoveryAnalyzer.calculate(
            recentSleepHours: [8.0, 7.5, 8.0],
            restingHeartRate: 60,
            restingHRHistory: [60, 61, 59, 60, 62, 60, 61, 59, 60, 60],
            trainingLoadRatio: 1.0,
            hrvValues: [50, 55, 48]
        )

        XCTAssertFalse(result.explanation.isEmpty, "Should provide explanation")
        XCTAssertFalse(result.suggestion.isEmpty, "Should provide suggestion")
    }
}
