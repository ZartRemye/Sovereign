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
    @Published var dataSource: DataSource = .empty
    @Published var lastAnalysisDate: Date?
    @Published var lastImportDiagnostic: ImportDiagnostic?

    // Database counts for diagnostics
    @Published var dbMetricCount: Int = 0
    @Published var dbWorkoutCount: Int = 0
    @Published var dbSleepCount: Int = 0
    @Published var dbSummaryCount: Int = 0

    private var _modelContext: ModelContext?

    /// Exposed for ImportCoordinator checkpoint access
    var modelContext: ModelContext? { _modelContext }

    private init() {}

    func configure(with context: ModelContext) {
        self._modelContext = context
        ImportCoordinator.shared.configure(with: context)
        Task { await detectDataSource() }
    }

    // MARK: - Data Source Detection

    func detectDataSource() async {
        guard let context = modelContext else { return }

        let metricCount = (try? context.fetchCount(FetchDescriptor<HealthMetricSample>())) ?? 0
        let workoutCount = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        let summaryCount = (try? context.fetchCount(FetchDescriptor<DailySummary>())) ?? 0

        dbMetricCount = metricCount
        dbWorkoutCount = workoutCount
        dbSummaryCount = summaryCount

        if metricCount == 0 && workoutCount == 0 && summaryCount == 0 {
            dataSource = .empty
        } else {
            // Check if data is from import or mock (use string predicates to avoid enum limitation)
            let importRaw = DataSource.appleHealthImport.rawValue
            let importDescriptors = FetchDescriptor<HealthMetricSample>(predicate: #Predicate { $0.sourceRaw == importRaw })
            let importCount = (try? context.fetchCount(importDescriptors)) ?? 0

            if importCount > 0 {
                dataSource = .appleHealthImport
            } else {
                let mockRaw = DataSource.mockLive.rawValue
                let mockDescriptors = FetchDescriptor<HealthMetricSample>(predicate: #Predicate { $0.sourceRaw == mockRaw })
                let mockCount = (try? context.fetchCount(mockDescriptors)) ?? 0
                dataSource = mockCount > 0 ? .mockLive : .empty
            }
        }

        await refresh()
    }

    // MARK: - Load Demo Data (explicit action only)

    func loadMockData() async {
        isLoading = true
        defer { isLoading = false }

        let mockData = await MockHealthDataProvider.shared.generateAllData()
        dataSource = .mockLive

        guard let context = modelContext else { return }

        // Don't clear real imported data — only clear mock data
        let mockRaw = DataSource.mockLive.rawValue
        try? context.delete(model: HealthMetricSample.self, where: #Predicate<HealthMetricSample> { $0.sourceRaw == mockRaw })
        try? context.delete(model: WorkoutSession.self, where: #Predicate<WorkoutSession> { $0.sourceRaw == mockRaw })
        try? context.delete(model: SleepSession.self, where: #Predicate<SleepSession> { $0.sourceRaw == mockRaw })
        try? context.delete(model: DailySummary.self, where: #Predicate<DailySummary> { $0.sourceRaw == mockRaw })

        // Insert mock data
        for metric in mockData.metrics { context.insert(metric) }
        for workout in mockData.workouts { context.insert(workout) }
        for sleep in mockData.sleepSessions { context.insert(sleep) }
        for summary in mockData.dailySummaries { context.insert(summary) }

        try? context.save()

        dailySummaries = mockData.dailySummaries.sorted { $0.date > $1.date }
        recentWorkouts = mockData.workouts.sorted { $0.startDate > $1.startDate }
        recentSleep = mockData.sleepSessions.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Legacy import (for backward compat)

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

    // MARK: - Rebuild Daily Summaries

    func rebuildDailySummaries() async {
        guard let context = modelContext else { return }
        isLoading = true
        defer { isLoading = false }

        let allMetrics = (try? context.fetch(FetchDescriptor<HealthMetricSample>())) ?? []
        let allWorkouts = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let allSleep = (try? context.fetch(FetchDescriptor<SleepSession>())) ?? []

        guard !allMetrics.isEmpty else { return }

        let dates = allMetrics.map(\.date)
        guard let startDate = dates.min(), let endDate = dates.max() else { return }

        // Delete old summaries
        try? context.delete(model: DailySummary.self)

        let summaries = DailySummaryBuilder.buildAll(
            from: startDate,
            to: endDate,
            metrics: allMetrics,
            workouts: allWorkouts,
            sleepSessions: allSleep
        )

        for summary in summaries {
            context.insert(summary)
        }
        try? context.save()

        dailySummaries = summaries.sorted { $0.date > $1.date }
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

        let alertDescriptor = FetchDescriptor<AlertRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        alerts = (try? context.fetch(alertDescriptor)) ?? []

        // Update counts
        dbMetricCount = (try? context.fetchCount(FetchDescriptor<HealthMetricSample>())) ?? 0
        dbWorkoutCount = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        dbSleepCount = (try? context.fetchCount(FetchDescriptor<SleepSession>())) ?? 0
        dbSummaryCount = dailySummaries.count

        // Load latest import diagnostic
        var diagDescriptor = FetchDescriptor<ImportDiagnostic>(sortBy: [SortDescriptor(\.importTime, order: .reverse)])
        diagDescriptor.fetchLimit = 1
        lastImportDiagnostic = (try? context.fetch(diagDescriptor))?.first
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
        try? context.delete(model: ImportDiagnostic.self)
        try? context.save()

        dataSource = .empty
        dailySummaries = []
        recentWorkouts = []
        recentSleep = []
        healthInsights = []
        alerts = []
        dbMetricCount = 0
        dbWorkoutCount = 0
        dbSleepCount = 0
        dbSummaryCount = 0
        lastImportDiagnostic = nil
    }

    func clearDemoData() async {
        guard let context = modelContext else { return }
        let mockRaw = DataSource.mockLive.rawValue
        try? context.delete(model: HealthMetricSample.self, where: #Predicate<HealthMetricSample> { $0.sourceRaw == mockRaw })
        try? context.delete(model: WorkoutSession.self, where: #Predicate<WorkoutSession> { $0.sourceRaw == mockRaw })
        try? context.delete(model: SleepSession.self, where: #Predicate<SleepSession> { $0.sourceRaw == mockRaw })
        try? context.delete(model: DailySummary.self, where: #Predicate<DailySummary> { $0.sourceRaw == mockRaw })
        try? context.save()
        await detectDataSource()
    }

    func clearImportedData() async {
        guard let context = modelContext else { return }
        let importRaw = DataSource.appleHealthImport.rawValue
        try? context.delete(model: HealthMetricSample.self, where: #Predicate<HealthMetricSample> { $0.sourceRaw == importRaw })
        try? context.delete(model: WorkoutSession.self, where: #Predicate<WorkoutSession> { $0.sourceRaw == importRaw })
        try? context.delete(model: SleepSession.self, where: #Predicate<SleepSession> { $0.sourceRaw == importRaw })
        try? context.delete(model: DailySummary.self, where: #Predicate<DailySummary> { $0.sourceRaw == importRaw })
        try? context.delete(model: ImportDiagnostic.self)
        try? context.save()
        lastImportDiagnostic = nil
        await detectDataSource()
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

    // MARK: - Data Status

    var hasRealData: Bool {
        dataSource == .appleHealthImport
    }

    var hasAnyData: Bool {
        dataSource != .empty
    }

    var isDemoData: Bool {
        dataSource == .mockLive
    }
}
