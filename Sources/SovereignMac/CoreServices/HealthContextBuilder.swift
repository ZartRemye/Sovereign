import Foundation

struct HealthContextBuilder {
    /// Build a compressed health context from daily summaries, workouts, and sleep data
    static func build(
        summaries: [DailySummary],
        workouts: [WorkoutSession],
        sleepSessions: [SleepSession],
        insights: [HealthInsight],
        dataSource: DataSource = .mockLive
    ) -> HealthContext {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!

        let recentSummaries = summaries.filter { $0.date >= sevenDaysAgo }
        let monthSummaries = summaries.filter { $0.date >= thirtyDaysAgo }

        // 7-day summary
        let sevenDay = SevenDaySummary(
            dailySteps: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: Double($0.steps)) },
            dailySleep: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: $0.sleepDurationSeconds / 3600) },
            dailyRestingHR: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: $0.restingHeartRate) },
            dailyExerciseMinutes: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: Double($0.exerciseMinutes)) },
            dailyActiveEnergy: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: $0.activeEnergyKJ) },
            dailyTrainingLoad: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: $0.trainingLoad) },
            dailyRecoveryScore: recentSummaries.map { DailyValue(date: $0.dateFormatted, value: $0.recoveryScore) }
        )

        // 30-day summary
        let thirtyDay = ThirtyDaySummary(
            avgSteps: monthSummaries.map(\.steps).reduce(0, +).doubleValue / max(monthSummaries.count, 1).doubleValue,
            avgSleepHours: monthSummaries.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / max(monthSummaries.count, 1).doubleValue,
            avgRestingHR: monthSummaries.map(\.restingHeartRate).reduce(0, +) / max(monthSummaries.count, 1).doubleValue,
            avgActiveEnergy: monthSummaries.map(\.activeEnergyKJ).reduce(0, +) / max(monthSummaries.count, 1).doubleValue,
            workoutFrequency: computeWorkoutFrequency(workouts: workouts, since: thirtyDaysAgo),
            trainingLoadChange: computeLoadChange(summaries: monthSummaries),
            recoveryTrend: computeRecoveryTrend(summaries: monthSummaries)
        )

        // Recent workouts
        let recentWorkouts = workouts
            .filter { $0.startDate >= sevenDaysAgo }
            .prefix(10)
            .map { w in
                WorkoutSummary(
                    type: w.workoutType.rawValue,
                    date: w.startDate.formatted(date: .numeric, time: .omitted),
                    durationMinutes: Int(w.durationSeconds / 60),
                    distanceKm: w.distanceMeters.map { $0 / 1000 },
                    avgHeartRate: w.avgHeartRate,
                    intensityEstimate: estimateIntensity(workout: w)
                )
            }

        // Local insights
        let localInsights = insights.map {
            LocalInsight(title: $0.title, message: $0.message, severity: $0.severity.rawValue)
        }

        // Data quality
        let dataQuality = DataQualityInfo(
            dateRangeStart: monthSummaries.first?.date.formatted(date: .numeric, time: .omitted) ?? "N/A",
            dateRangeEnd: monthSummaries.last?.date.formatted(date: .numeric, time: .omitted) ?? "N/A",
            missingMetrics: identifyMissingMetrics(summaries: recentSummaries),
            lastSyncDate: dataSource == .mockLive ? nil : Date().formatted(),
            isMockData: dataSource == .mockLive,
            dataSource: dataSource.rawValue
        )

        return HealthContext(
            generatedAt: Date(),
            dataSource: dataSource.rawValue,
            isMockData: dataSource == .mockLive,
            lastSyncDate: dataSource == .mockLive ? nil : Date(),
            sevenDaySummary: sevenDay,
            thirtyDaySummary: thirtyDay,
            recentWorkouts: recentWorkouts,
            localInsights: localInsights,
            dataQuality: dataQuality
        )
    }

    // MARK: - Helpers

    private static func computeWorkoutFrequency(workouts: [WorkoutSession], since date: Date) -> Int {
        let count = workouts.filter { $0.startDate >= date }.count
        return count
    }

    private static func computeLoadChange(summaries: [DailySummary]) -> String {
        let sorted = summaries.sorted { $0.date < $1.date }
        guard sorted.count >= 14 else { return "数据不足" }

        let recent14 = sorted.suffix(7).map(\.trainingLoad).reduce(0, +) / 7
        let prior14 = sorted.prefix(sorted.count - 7).suffix(7).map(\.trainingLoad).reduce(0, +) / 7

        guard prior14 > 0 else { return "基准数据不足" }

        let change = (recent14 - prior14) / prior14 * 100
        if change > 30 { return "增加 \(String(format: "%.0f", change))%" }
        if change < -30 { return "减少 \(String(format: "%.0f", abs(change)))%" }
        return "基本稳定"
    }

    private static func computeRecoveryTrend(summaries: [DailySummary]) -> String {
        let sorted = summaries.sorted { $0.date < $1.date }
        let recent = sorted.suffix(7).map(\.recoveryScore)
        let avg = recent.reduce(0, +) / max(recent.count.doubleValue, 1)
        if avg >= 80 { return "良好" }
        if avg >= 60 { return "正常" }
        if avg >= 40 { return "偏低" }
        return "不足"
    }

    private static func identifyMissingMetrics(summaries: [DailySummary]) -> [String] {
        var missing: [String] = []
        let total = summaries.count
        guard total > 0 else { return ["所有指标"] }

        if summaries.filter({ $0.steps > 0 }).count < total / 2 { missing.append("步数") }
        if summaries.filter({ $0.sleepDurationSeconds > 0 }).count < total / 2 { missing.append("睡眠") }
        if summaries.filter({ $0.restingHeartRate > 0 }).count < total / 2 { missing.append("静息心率") }
        if summaries.filter({ $0.heartRateVariability != nil }).count < total / 2 { missing.append("HRV") }

        return missing.isEmpty ? ["无"] : missing
    }

    private static func estimateIntensity(workout: WorkoutSession) -> String {
        guard let avgHR = workout.avgHeartRate else { return "未知" }
        let maxHR = workout.maxHeartRate ?? 190
        let ratio = avgHR / maxHR
        if ratio > 0.85 { return "很高" }
        if ratio > 0.75 { return "较高" }
        if ratio > 0.60 { return "中等" }
        return "较低"
    }
}

private extension Int {
    var doubleValue: Double { Double(self) }
}

private extension Array where Element == Int {
    var doubleValue: Double { Double(count) }
}
