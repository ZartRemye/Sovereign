import XCTest
@testable import SovereignMac

final class DailySummaryBuilderTests: XCTestCase {
    func testBuildsSummaryFromMetrics() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let metrics: [HealthMetricSample] = [
            HealthMetricSample(metricType: .stepCount, value: 8000, unit: "count",
                             date: today.addingTimeInterval(43200), source: .mockLive),
            HealthMetricSample(metricType: .restingHeartRate, value: 62, unit: "bpm",
                             date: today.addingTimeInterval(25200), source: .mockLive),
            HealthMetricSample(metricType: .activeEnergy, value: 2000, unit: "kJ",
                             date: today.addingTimeInterval(64800), source: .mockLive),
        ]

        let summary = DailySummaryBuilder.build(
            date: today,
            metrics: metrics,
            workouts: [],
            sleepSessions: [],
            previousSummaries: []
        )

        XCTAssertEqual(summary.steps, 8000)
        XCTAssertEqual(summary.restingHeartRate, 62)
        XCTAssertEqual(summary.activeEnergyKJ, 2000)
    }

    func testFiltersByDate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let metrics: [HealthMetricSample] = [
            HealthMetricSample(metricType: .stepCount, value: 8000, unit: "count",
                             date: today.addingTimeInterval(43200), source: .mockLive),
            HealthMetricSample(metricType: .stepCount, value: 5000, unit: "count",
                             date: yesterday.addingTimeInterval(43200), source: .mockLive),
        ]

        let summary = DailySummaryBuilder.build(
            date: today,
            metrics: metrics,
            workouts: [],
            sleepSessions: [],
            previousSummaries: []
        )

        XCTAssertEqual(summary.steps, 8000, "Should only include today's metrics")
    }

    func testWithWorkouts() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let workout = WorkoutSession(
            workoutType: .running,
            startDate: today.addingTimeInterval(28800),
            endDate: today.addingTimeInterval(32400),
            durationSeconds: 3600,
            avgHeartRate: 155,
            trainingLoad: 120
        )

        let summary = DailySummaryBuilder.build(
            date: today,
            metrics: [],
            workouts: [workout],
            sleepSessions: [],
            previousSummaries: []
        )

        XCTAssertEqual(summary.trainingLoad, 120)
    }

    func testExerciseMinutes() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let metrics: [HealthMetricSample] = [
            HealthMetricSample(metricType: .exerciseTime, value: 45, unit: "min",
                             date: today.addingTimeInterval(54000), source: .mockLive),
        ]

        let summary = DailySummaryBuilder.build(
            date: today,
            metrics: metrics,
            workouts: [],
            sleepSessions: [],
            previousSummaries: []
        )

        XCTAssertEqual(summary.exerciseMinutes, 45)
    }
}
