import XCTest
@testable import Sovereign

final class HealthPromptBuilderTests: XCTestCase {
    func testSystemPromptExists() {
        let prompt = HealthPromptBuilder.systemPrompt
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains("不是医生"), "System prompt must state not a doctor")
        XCTAssertTrue(prompt.contains("医疗诊断"), "System prompt must mention no medical diagnosis")
    }

    func testBuildsUserPrompt() {
        let context = minimalContext()
        let prompt = HealthPromptBuilder.buildUserPrompt(
            question: "我今天适合训练吗？",
            context: context
        )

        XCTAssertTrue(prompt.contains("我今天适合训练吗？"))
        XCTAssertTrue(prompt.contains("健康数据摘要"))
        XCTAssertTrue(prompt.contains("数据质量"))
    }

    func testPromptIncludesMockDataWarning() {
        var context = minimalContext()
        // context.isMockData is true by default for mockLive source
        let prompt = HealthPromptBuilder.buildUserPrompt(
            question: "test",
            context: context
        )
        XCTAssertTrue(prompt.contains("模拟数据"), "Must warn about mock data")
    }

    func testPromptIncludesWorkoutInfo() {
        let calendar = Calendar.current
        let workout = WorkoutSession(
            workoutType: .cycling,
            startDate: Date().addingTimeInterval(-86400),
            endDate: Date().addingTimeInterval(-84600),
            durationSeconds: 3600,
            distanceMeters: 20000,
            avgHeartRate: 140
        )
        var ctx = minimalContext()
        // Build with workout context
        let ctxWithWorkout = HealthContextBuilder.build(
            summaries: [],
            workouts: [workout],
            sleepSessions: [],
            insights: [],
            dataSource: .mockLive
        )
        let prompt = HealthPromptBuilder.buildUserPrompt(question: "test", context: ctxWithWorkout)
        XCTAssertTrue(prompt.contains("Cycling"))
    }

    private func minimalContext() -> HealthContext {
        HealthContext(
            generatedAt: Date(),
            dataSource: "Mock Live",
            isMockData: true,
            lastSyncDate: nil,
            sevenDaySummary: SevenDaySummary(
                dailySteps: [], dailySleep: [], dailyRestingHR: [],
                dailyExerciseMinutes: [], dailyActiveEnergy: [], dailyTrainingLoad: [],
                dailyRecoveryScore: []
            ),
            thirtyDaySummary: ThirtyDaySummary(
                avgSteps: 0, avgSleepHours: 0, avgRestingHR: 0,
                avgActiveEnergy: 0, workoutFrequency: 0,
                trainingLoadChange: "N/A", recoveryTrend: "N/A"
            ),
            recentWorkouts: [],
            localInsights: [],
            dataQuality: DataQualityInfo(
                dateRangeStart: "2024-01-01", dateRangeEnd: "2024-01-07",
                missingMetrics: [], lastSyncDate: nil,
                isMockData: true, dataSource: "Mock Live"
            )
        )
    }
}
