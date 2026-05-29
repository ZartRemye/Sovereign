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
        let daySleep = sleepSessions.filter {
            // Assign sleep to the morning date (when you wake up)
            let endHour = calendar.component(.hour, from: $0.endDate)
            if endHour >= 4 && endHour < 12 {
                return calendar.startOfDay(for: $0.endDate) == dayStart
            }
            return calendar.startOfDay(for: $0.startDate) == dayStart
        }

        let summary = DailySummary(date: dayStart)

        // --- Steps ---
        summary.steps = Int(dayMetrics.filter { $0.metricType == .stepCount }.map(\.value).reduce(0, +))

        // --- Heart Rate ---
        let restingHRValues = dayMetrics.filter { $0.metricType == .restingHeartRate }.map(\.value)
        if !restingHRValues.isEmpty {
            summary.restingHeartRate = restingHRValues.reduce(0, +) / Double(restingHRValues.count)
        }

        let hrValues = dayMetrics.filter { $0.metricType == .heartRate }.map(\.value)
        if !hrValues.isEmpty {
            summary.averageHeartRate = hrValues.reduce(0, +) / Double(hrValues.count)
        }

        // --- HRV ---
        let hrvValues = dayMetrics.filter { $0.metricType == .heartRateVariability }.map(\.value)
        if !hrvValues.isEmpty {
            summary.heartRateVariability = hrvValues.reduce(0, +) / Double(hrvValues.count)
        }

        // --- Sleep ---
        let totalAsleep = daySleep.map(\.durationSeconds).reduce(0, +)
        let totalInBed = daySleep.map(\.timeInBedSeconds).reduce(0, +)
        let totalDeep = daySleep.map(\.deepSleepSeconds).reduce(0, +)
        let totalREM = daySleep.map(\.remSleepSeconds).reduce(0, +)
        let totalAwake = daySleep.map(\.awakeSeconds).reduce(0, +)

        summary.sleepHours = totalAsleep / 3600
        summary.timeInBed = totalInBed > 0 ? totalInBed / 3600 : totalAsleep / 3600
        summary.deepSleep = totalDeep / 3600
        summary.remSleep = totalREM / 3600
        summary.awakeTime = totalAwake / 3600

        // Sleep data quality: average of sleep sessions' data quality
        if !daySleep.isEmpty {
            summary.sleepDataQuality = daySleep.map(\.sleepDataQuality).reduce(0, +) / Double(daySleep.count)
        }

        // --- Energy ---
        summary.activeEnergy = dayMetrics.filter { $0.metricType == .activeEnergy }.map(\.value).reduce(0, +)

        // --- Exercise ---
        summary.exerciseMinutes = Int(dayMetrics.filter { $0.metricType == .exerciseTime }.map(\.value).reduce(0, +))

        // --- Distance ---
        summary.walkingRunningDistance = dayMetrics.filter { $0.metricType == .distance }.map(\.value).reduce(0, +)

        // --- Body metrics ---
        let bodyMassValues = dayMetrics.filter { $0.metricType == .bodyMass }.map(\.value)
        if let lastMass = bodyMassValues.last {
            summary.bodyMass = lastMass
        }
        let heightValues = dayMetrics.filter { $0.metricType == .height }.map(\.value)
        if let lastHeight = heightValues.last {
            summary.height = lastHeight
        }
        let vo2MaxValues = dayMetrics.filter { $0.metricType == .vo2Max }.map(\.value)
        if !vo2MaxValues.isEmpty {
            summary.vo2Max = vo2MaxValues.reduce(0, +) / Double(vo2MaxValues.count)
        }

        // --- Workouts ---
        summary.workoutCount = dayWorkouts.count
        summary.workoutMinutes = dayWorkouts.map { $0.durationSeconds / 60 }.reduce(0, +)
        summary.trainingLoad = dayWorkouts.map(\.trainingLoad).reduce(0, +)

        // --- Recovery Score ---
        let sleepHours = summary.sleepHours
        let recentSleepValues = previousSummaries.suffix(2).map(\.sleepHours) + [sleepHours]

        let recentHRValues = previousSummaries.suffix(13).map(\.restingHeartRate)
        let hrHistory = recentHRValues + [summary.restingHeartRate]

        let recoveryComponents = RecoveryAnalyzer.calculate(
            recentSleepHours: recentSleepValues.filter { $0 > 0 },
            restingHeartRate: summary.restingHeartRate,
            restingHRHistory: hrHistory.filter { $0 > 0 },
            trainingLoadRatio: computeACWR(summary: summary, history: Array(previousSummaries.suffix(27))),
            hrvValues: summary.heartRateVariability.map { [$0] }
        )

        summary.recoveryScore = recoveryComponents.score

        // --- Data Completeness ---
        var completenessScore = 0.0
        var totalFields = 0.0
        if summary.steps > 0 { completenessScore += 1 }; totalFields += 1
        if summary.restingHeartRate > 0 { completenessScore += 1 }; totalFields += 1
        if summary.sleepHours > 0 { completenessScore += 1 }; totalFields += 1
        if summary.activeEnergy > 0 { completenessScore += 1 }; totalFields += 1
        if summary.exerciseMinutes > 0 { completenessScore += 1 }; totalFields += 1
        if summary.heartRateVariability != nil { completenessScore += 0.5 }; totalFields += 0.5
        if summary.vo2Max != nil { completenessScore += 0.5 }; totalFields += 0.5
        summary.dataCompleteness = totalFields > 0 ? completenessScore / totalFields : 0

        // --- Health Status ---
        summary.healthStatusRaw = determineHealthStatus(
            recoveryScore: recoveryComponents.score,
            sleepHours: sleepHours,
            trainingLoad: summary.trainingLoad,
            previousLoads: previousSummaries.suffix(7).map(\.trainingLoad),
            sleepDataQuality: summary.sleepDataQuality
        ).rawValue

        // --- Source ---
        let hasRealData = dayMetrics.contains { $0.source == .appleHealthImport }
            || dayWorkouts.contains { $0.source == .appleHealthImport }
            || daySleep.contains { $0.source == .appleHealthImport }
        summary.sourceRaw = hasRealData ? DataSource.appleHealthImport.rawValue : DataSource.mockLive.rawValue

        return summary
    }

    // MARK: - Bulk Build

    static func buildAll(
        from startDate: Date,
        to endDate: Date,
        metrics: [HealthMetricSample],
        workouts: [WorkoutSession],
        sleepSessions: [SleepSession]
    ) -> [DailySummary] {
        let calendar = Calendar.current
        var summaries: [DailySummary] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        while currentDate <= endDay {
            let summary = build(
                date: currentDate,
                metrics: metrics,
                workouts: workouts,
                sleepSessions: sleepSessions,
                previousSummaries: summaries
            )
            summaries.append(summary)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return summaries
    }

    // MARK: - Helpers

    private static func computeACWR(summary: DailySummary, history: [DailySummary]) -> Double {
        let loads = history.map(\.trainingLoad)
        let acute = (loads.suffix(7) + [summary.trainingLoad]).reduce(0, +) / max(Double(min(loads.suffix(7).count + 1, 7)), 1)
        let chronic = loads.reduce(0, +) / max(Double(loads.count), 1)
        return chronic > 0 ? acute / chronic : 1.0
    }

    private static func determineHealthStatus(recoveryScore: Double, sleepHours: Double,
                                               trainingLoad: Double, previousLoads: [Double],
                                               sleepDataQuality: Double) -> HealthStatus {
        if recoveryScore >= 75 { return .recoveringWell }
        if recoveryScore < 40 { return .mildFatigue }

        let avgLoad = previousLoads.reduce(0, +) / max(Double(previousLoads.count), 1)
        let sleepIsLowQuality = sleepHours < 6.5 && sleepDataQuality > 0

        if sleepIsLowQuality && recoveryScore < 60 { return .sleepDeprived }
        if trainingLoad > avgLoad * 1.5 && avgLoad > 0 { return .trainingLoadHigh }
        if recoveryScore < 60 { return .mildFatigue }
        return .recoveringWell
    }
}
