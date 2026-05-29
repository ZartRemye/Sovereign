import XCTest
@testable import Sovereign

final class HealthContextBuilderTests: XCTestCase {
    func testBuildsContextFromData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var summaries: [DailySummary] = []
        for i in 0..<10 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let summary = DailySummary(
                date: date,
                steps: 8000 + Int.random(in: -500...500),
                restingHeartRate: 62,
                sleepDurationSeconds: 28800,
                activeEnergyKJ: 2000,
                exerciseMinutes: 30,
                recoveryScore: 70,
                trainingLoad: 50
            )
            summaries.append(summary)
        }

        let context = HealthContextBuilder.build(
            summaries: summaries,
            workouts: [],
            sleepSessions: [],
            insights: [],
            dataSource: .mockLive
        )

        XCTAssertTrue(context.isMockData)
        XCTAssertEqual(context.dataSource, "Mock Live")
        XCTAssertFalse(context.sevenDaySummary.dailySteps.isEmpty)
        XCTAssertFalse(context.thirtyDaySummary.recoveryTrend.isEmpty)
    }

    func testIdentifiesMissingData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Create summaries with only steps
        var summaries: [DailySummary] = []
        for i in 0..<8 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let summary = DailySummary(date: date, steps: 8000)
            summaries.append(summary)
        }

        let context = HealthContextBuilder.build(
            summaries: summaries,
            workouts: [],
            sleepSessions: [],
            insights: [],
            dataSource: .mockLive
        )

        XCTAssertTrue(context.dataQuality.missingMetrics.count > 0, "Should identify missing sleep, HR data")
        XCTAssertTrue(context.dataQuality.missingMetrics.contains("睡眠"))
    }

    func testWorkoutSummaries() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let workout = WorkoutSession(
            workoutType: .running,
            startDate: yesterday.addingTimeInterval(3600),
            endDate: yesterday.addingTimeInterval(5400),
            durationSeconds: 1800,
            distanceMeters: 5000,
            avgHeartRate: 155,
            maxHeartRate: 175
        )

        let context = HealthContextBuilder.build(
            summaries: [],
            workouts: [workout],
            sleepSessions: [],
            insights: [],
            dataSource: .appleHealthImport
        )

        XCTAssertFalse(context.recentWorkouts.isEmpty)
        XCTAssertEqual(context.recentWorkouts.first?.type, "Running")
        XCTAssertEqual(context.recentWorkouts.first?.durationMinutes, 30)
    }
}
