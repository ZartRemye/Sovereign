import XCTest
@testable import Sovereign

final class TrainingLoadAnalyzerTests: XCTestCase {
    func testBasicLoadCalculation() {
        let load = TrainingLoadAnalyzer.calculateLoad(
            durationMinutes: 30,
            avgHeartRate: 150,
            maxHeartRate: 175,
            estimatedMaxHR: 190
        )
        XCTAssertGreaterThan(load, 0, "Load should be positive for any workout")
    }

    func testLowIntensityLoad() {
        let highLoad = TrainingLoadAnalyzer.calculateLoad(
            durationMinutes: 30, avgHeartRate: 150, maxHeartRate: 175
        )
        let lowLoad = TrainingLoadAnalyzer.calculateLoad(
            durationMinutes: 30, avgHeartRate: 90, maxHeartRate: 120
        )
        XCTAssertGreaterThan(highLoad, lowLoad, "Higher HR should produce higher load")
    }

    func testDurationProportionality() {
        let shortLoad = TrainingLoadAnalyzer.calculateLoad(
            durationMinutes: 15, avgHeartRate: 140, maxHeartRate: 160
        )
        let longLoad = TrainingLoadAnalyzer.calculateLoad(
            durationMinutes: 60, avgHeartRate: 140, maxHeartRate: 160
        )
        XCTAssertGreaterThan(longLoad, shortLoad, "Longer duration should produce higher load")
    }

    func testACWRCalculation() {
        let acute = [100.0, 110.0, 90.0, 105.0, 95.0, 115.0, 85.0] // avg = 100
        let chronic = [80.0, 82.0, 78.0, 85.0, 80.0, 83.0, 81.0, 79.0, 84.0, 80.0] // avg = 81.2

        let (acuteAvg, chronicAvg, ratio, status) = TrainingLoadAnalyzer.calculateACWR(
            acuteLoads: acute, chronicLoads: chronic
        )

        XCTAssertGreaterThan(acuteAvg, 0)
        XCTAssertGreaterThan(chronicAvg, 0)
        XCTAssertGreaterThan(ratio, 1.0, "Acute load higher, ratio should be > 1")
        XCTAssertEqual(status, .moderateHigh)
    }

    func testACWRBalanced() {
        let loads = [50.0, 55.0, 48.0, 52.0, 50.0, 53.0, 51.0]
        let (_, _, ratio, status) = TrainingLoadAnalyzer.calculateACWR(
            acuteLoads: loads, chronicLoads: loads
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.01)
        XCTAssertEqual(status, .optimal)
    }

    func testDailyLoadsAggregation() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let workout1 = WorkoutSession(
            workoutType: .running,
            startDate: today.addingTimeInterval(3600),
            endDate: today.addingTimeInterval(5400),
            durationSeconds: 1800,
            avgHeartRate: 150
        )
        let workout2 = WorkoutSession(
            workoutType: .cycling,
            startDate: today.addingTimeInterval(7200),
            endDate: today.addingTimeInterval(9000),
            durationSeconds: 1800,
            avgHeartRate: 140
        )

        let dailyLoads = TrainingLoadAnalyzer.dailyLoads(from: [workout1, workout2])
        XCTAssertEqual(dailyLoads.count, 1)
        XCTAssertGreaterThan(dailyLoads[today] ?? 0, 0)
    }
}
