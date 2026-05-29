import Foundation

struct DailySummaryBuilder {
    /// Build a daily summary from raw metric samples, workouts, and sleep sessions
    static func build(
        date: Date,
        metrics: [HealthMetricSample],
        workouts: [WorkoutSession],
        sleepSessions: [SleepSession],
        previousSummaries: [DailySummary]
    ) -> DailySummary {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let dayMetrics = metrics.filter { $0.date >= dayStart && $0.date < dayEnd }
        let dayWorkouts = workouts.filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
        let daySleep = sleepSessions.filter { $0.startDate >= dayStart && $0.startDate < dayEnd }

        let summary = DailySummary(date: dayStart)

        // Aggregate metrics
        summary.steps = Int(dayMetrics.filter { $0.metricType == .stepCount }.map(\.value).reduce(0, +))

        let hrValues = dayMetrics.filter { $0.metricType == .restingHeartRate }.map(\.value)
        if let avgHR = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count) {
            summary.restingHeartRate = avgHR
        }

        let hrvValues = dayMetrics.filter { $0.metricType == .heartRateVariability }.map(\.value)
        if !hrvValues.isEmpty {
            summary.heartRateVariability = hrvValues.reduce(0, +) / Double(hrvValues.count)
        }

        summary.sleepDurationSeconds = daySleep.map(\.durationSeconds).reduce(0, +)
        summary.activeEnergyKJ = dayMetrics.filter { $0.metricType == .activeEnergy }.map(\.value).reduce(0, +)
        summary.exerciseMinutes = Int(dayMetrics.filter { $0.metricType == .exerciseTime }.map(\.value).reduce(0, +))

        // Calculate training load
        summary.trainingLoad = dayWorkouts.map(\.trainingLoad).reduce(0, +)

        // Calculate recovery score
        let sleepHours = summary.sleepDurationSeconds / 3600
        let recentSleep = previousSummaries.suffix(2).map { $0.sleepDurationSeconds / 3600 } + [sleepHours]

        let recentHRValues = previousSummaries.suffix(13).map(\.restingHeartRate)
        let hrHistory = recentHRValues + [summary.restingHeartRate]

        let recoveryComponents = RecoveryAnalyzer.calculate(
            recentSleepHours: recentSleep.filter { $0 > 0 },
            restingHeartRate: summary.restingHeartRate,
            restingHRHistory: hrHistory.filter { $0 > 0 },
            trainingLoadRatio: computeACWR(summary: summary, history: Array(previousSummaries.suffix(27))),
            hrvValues: summary.heartRateVariability.map { [$0] }
        )

        summary.recoveryScore = recoveryComponents.score

        // Determine health status
        summary.healthStatusRaw = determineHealthStatus(
            recoveryScore: recoveryComponents.score,
            sleepHours: sleepHours,
            trainingLoad: summary.trainingLoad,
            avgTrainingLoad: previousSummaries.suffix(7).map(\.trainingLoad).reduce(0, +) / 7
        ).rawValue

        return summary
    }

    private static func computeACWR(summary: DailySummary, history: [DailySummary]) -> Double {
        let loads = history.map(\.trainingLoad)
        let acute = (loads.suffix(7) + [summary.trainingLoad]).reduce(0, +) / 8
        let chronic = loads.reduce(0, +) / max(Double(loads.count), 1)
        return chronic > 0 ? acute / chronic : 1.0
    }

    private static func determineHealthStatus(recoveryScore: Double, sleepHours: Double,
                                               trainingLoad: Double, avgTrainingLoad: Double) -> HealthStatus {
        if recoveryScore >= 75 { return .recoveringWell }
        if recoveryScore < 40 { return .mildFatigue }
        if sleepHours < 6.5 && recoveryScore < 60 { return .sleepDeprived }
        if trainingLoad > avgTrainingLoad * 1.5 && avgTrainingLoad > 0 { return .trainingLoadHigh }
        return .recoveringWell
    }
}
