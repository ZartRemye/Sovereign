import XCTest
@testable import SovereignMac

final class HealthPromptBuilderTests: XCTestCase {
    private let mockRuntime = AIRuntimeStatus(
        providerMode: .localRules,
        hasAPIKey: false,
        isCloudAIEnabled: false,
        modelName: nil,
        hasRealHealthData: false,
        dataSource: .mockLive,
        dataDateRange: nil
    )
    private let mockModel = PersonalHealthModel(dataCompleteness: 0.5, sleepTrend: .stable, activityTrend: .stable, restingHeartRateTrend: .stable, hrvTrend: .insufficient, trainingLoadTrend: .stable, recoveryTrend: .stable, mainConstraints: [], mainOpportunities: [], dataLimitations: [])
    private let mockForecast = HealthForecast(horizonDays: 7, recoveryForecast: "Stable", trainingRiskForecast: "Low", sleepRiskForecast: "Low", confidence: "Low", assumptions: [])
    private let mockPrescription = ExercisePrescription(readiness: .limited, recommendedTrainingType: "Light", durationRangeMinutes: 20...40, intensity: "Low", targetHeartRateZone: nil, warmup: "", mainSession: "", cooldown: "", stopConditions: [], recoveryActions: [], rationale: [])

    func testSystemPromptExists() {
        let prompt = HealthPromptBuilder.systemPrompt(for: mockRuntime)
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains("不是医生") || prompt.contains("not a doctor") || prompt.contains("diagnose"), "Must state not a doctor")
    }

    func testBuildsUserPrompt() {
        let context = minimalContext()
        let prompt = HealthPromptBuilder.buildUserPrompt(
            question: "我今天适合训练吗？",
            context: context,
            runtime: mockRuntime,
            healthModel: mockModel,
            forecast: mockForecast,
            prescription: mockPrescription
        )

        XCTAssertTrue(prompt.contains("我今天适合训练吗？"))
        XCTAssertTrue(prompt.contains("Sovereign Runtime"))
    }

    func testPromptIncludesMockDataWarning() {
        let context = minimalContext()
        let prompt = HealthPromptBuilder.buildUserPrompt(
            question: "test",
            context: context,
            runtime: mockRuntime,
            healthModel: mockModel,
            forecast: mockForecast,
            prescription: mockPrescription
        )
        XCTAssertTrue(prompt.contains("DEMO") || prompt.contains("Demo"))
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
        let ctxWithWorkout = HealthContextBuilder.build(
            summaries: [],
            workouts: [workout],
            sleepSessions: [],
            insights: [],
            dataSource: .mockLive
        )
        let prompt = HealthPromptBuilder.buildUserPrompt(question: "test", context: ctxWithWorkout, runtime: mockRuntime, healthModel: mockModel, forecast: mockForecast, prescription: mockPrescription)
        XCTAssertTrue(prompt.contains("Cycling"))
    }

    private func minimalContext() -> HealthContext {
        HealthContext(
            generatedAt: Date(),
            dataSource: "Demo Data",
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
                totalWorkoutMinutes: 0,
                trainingLoadChange: "N/A", recoveryTrend: "N/A",
                sleepTrend: "N/A", activityTrend: "N/A"
            ),
            recentWorkouts: [],
            localInsights: [],
            dataQuality: DataQualityInfo(
                dateRangeStart: "2024-01-01", dateRangeEnd: "2024-01-07",
                missingMetrics: [], lastSyncDate: nil,
                isMockData: true, dataSource: "Demo Data"
            )
        )
    }
}
