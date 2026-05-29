import Foundation
import SwiftData
import SwiftUI

/// Central data access layer wrapping SwiftData for the Mac app.
@MainActor
final class MacHealthStore: ObservableObject {
    static let shared = MacHealthStore()

    @Published var dailySummaries: [DailySummary] = []
    @Published var recentWorkouts: [WorkoutSession] = []
    @Published var recentSleep: [SleepSession] = []
    @Published var healthInsights: [HealthInsight] = []
    @Published var alerts: [AlertRecord] = []
    @Published var recoveryScores: [RecoveryScoreRecord] = []
    @Published var isLoading = false
    @Published var dataSource: DataSource = .mockLive
    @Published var lastAnalysisDate: Date?

    private var modelContext: ModelContext?

    private init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Load Mock Data

    func loadMockData() async {
        isLoading = true
        defer { isLoading = false }

        let mockData = await MockHealthDataProvider.shared.generateAllData()
        dataSource = .mockLive

        guard let context = modelContext else { return }

        // Clear existing mock data
        try? context.delete(model: HealthMetricSample.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: SleepSession.self)
        try? context.delete(model: DailySummary.self)

        // Insert new data
        for metric in mockData.metrics { context.insert(metric) }
        for workout in mockData.workouts { context.insert(workout) }
        for sleep in mockData.sleepSessions { context.insert(sleep) }
        for summary in mockData.dailySummaries { context.insert(summary) }

        try? context.save()

        dailySummaries = mockData.dailySummaries.sorted { $0.date > $1.date }
        recentWorkouts = mockData.workouts.sorted { $0.startDate > $1.startDate }
        recentSleep = mockData.sleepSessions.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Import Health Data

    func importHealthData(metrics: [HealthMetricSample], workouts: [WorkoutSession],
                           sleep: [SleepSession], summaries: [DailySummary]) async {
        guard let context = modelContext else { return }
        dataSource = .appleHealthImport

        for metric in metrics { context.insert(metric) }
        for workout in workouts { context.insert(workout) }
        for s in sleep { context.insert(s) }
        for summary in summaries { context.insert(summary) }

        try? context.save()

        dailySummaries = summaries.sorted { $0.date > $1.date }
        recentWorkouts = workouts.sorted { $0.startDate > $1.startDate }
        recentSleep = sleep.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Analysis

    func runLocalAnalysis() async {
        let insights = await LocalRuleAIService.shared.generateLocalInsights(
            summaries: dailySummaries,
            workouts: recentWorkouts,
            sleepSessions: recentSleep
        )

        guard let context = modelContext else { return }

        // Remove old insights
        try? context.delete(model: HealthInsight.self)

        for insight in insights {
            context.insert(insight)
        }

        try? context.save()
        healthInsights = insights
        lastAnalysisDate = Date()
    }

    // MARK: - Refresh

    func refresh() async {
        guard let context = modelContext else { return }

        let summaryDescriptor = FetchDescriptor<DailySummary>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        dailySummaries = (try? context.fetch(summaryDescriptor)) ?? []

        let workoutDescriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        recentWorkouts = (try? context.fetch(workoutDescriptor)) ?? []

        let sleepDescriptor = FetchDescriptor<SleepSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        recentSleep = (try? context.fetch(sleepDescriptor)) ?? []

        let insightDescriptor = FetchDescriptor<HealthInsight>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        healthInsights = (try? context.fetch(insightDescriptor)) ?? []
    }

    // MARK: - Clear Data

    func clearAllData() async {
        guard let context = modelContext else { return }
        try? context.delete(model: HealthMetricSample.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: SleepSession.self)
        try? context.delete(model: DailySummary.self)
        try? context.delete(model: HealthInsight.self)
        try? context.delete(model: AlertRecord.self)
        try? context.delete(model: AIAnalysisCache.self)
        try? context.save()

        dailySummaries = []
        recentWorkouts = []
        recentSleep = []
        healthInsights = []
        alerts = []
    }

    // MARK: - Today Summary

    var todaySummary: DailySummary? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return dailySummaries.first { calendar.startOfDay(for: $0.date) == today }
    }

    var latestRecoveryScore: Double {
        todaySummary?.recoveryScore ?? dailySummaries.first?.recoveryScore ?? 0
    }
}
