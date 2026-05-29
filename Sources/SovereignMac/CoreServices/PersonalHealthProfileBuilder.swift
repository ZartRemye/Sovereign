import Foundation

// MARK: - Personal Health Profile

struct PersonalHealthProfile: Codable, Equatable {
    var dataRangeStart: Date?
    var dataRangeEnd: Date?
    var dataCompleteness: Double

    var baselineSteps: Double?
    var baselineSleepHours: Double?
    var baselineRestingHeartRate: Double?
    var baselineHRV: Double?
    var baselineTrainingLoad: Double?
    var baselineActiveEnergy: Double?

    var currentRecoveryScore: Double?
    var currentReadiness: String = "Insufficient Data"
    var acuteTrainingLoad7d: Double?
    var chronicTrainingLoad28d: Double?
    var acuteChronicRatio: Double?

    var sleepConsistencyScore: Double?
    var activityConsistencyScore: Double?
    var cardioStabilityScore: Double?
    var trainingRegularityScore: Double?

    var dominantWorkoutTypes: [String] = []
    var dominantTags: [String] = []
    var strengths: [String] = []
    var constraints: [String] = []
    var opportunities: [String] = []
    var dataLimitations: [String] = []
}

// MARK: - Builder

final class PersonalHealthProfileBuilder {
    func build(
        summaries: [DailySummary],
        workouts: [WorkoutSession],
        sleep: [SleepSession]
    ) -> PersonalHealthProfile {
        let sorted = summaries.sorted { $0.date < $1.date }
        let dates = sorted.map(\.date)
        let recent7 = Array(sorted.suffix(7))
        let recent28 = Array(sorted.suffix(28))

        let dataCompleteness = sorted.isEmpty ? 0 : Double(sorted.filter { $0.dataCompleteness > 0.3 }.count) / Double(sorted.count)

        // Baselines (30-day means)
        let baselineSteps = mean(recent28.map { Double($0.steps) }.filter { $0 > 0 })
        let baselineSleep = mean(recent28.map(\.sleepHours).filter { $0 > 0 })
        let baselineRHR = mean(recent28.map(\.restingHeartRate).filter { $0 > 0 })
        let baselineHRV = mean(recent28.compactMap(\.heartRateVariability).filter { $0 > 0 })
        let baselineLoad = mean(recent28.map(\.trainingLoad).filter { $0 > 0 })
        let baselineEnergy = mean(recent28.map(\.activeEnergy).filter { $0 > 0 })

        // Current
        let currentRecovery = mean(recent7.map(\.recoveryScore))

        // Acute/Chronic
        let acute7 = recent7.map(\.trainingLoad).reduce(0, +) / 7
        let chronic28 = recent28.map(\.trainingLoad).reduce(0, +) / max(Double(recent28.count), 1)
        let acwr = chronic28 > 0 ? acute7 / chronic28 : 1.0

        // Consistency scores
        let sleepConsistency = consistencyScore(recent7.map(\.sleepHours))
        let activityConsistency = consistencyScore(recent7.map { Double($0.steps) })
        let cardioStability = consistencyScore(recent7.map(\.restingHeartRate).filter { $0 > 0 })
        let trainingRegularity = workouts.isEmpty ? 0 : consistencyScoreByWorkouts(workouts, days: 28)

        // Workout types
        let typeCounts = Dictionary(grouping: workouts, by: \.workoutType.rawValue)
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map { $0.key }

        // Tags (Chinese)
        var tags: [String] = []
        if let steps = baselineSteps, steps > 8000 { tags.append("活跃生活型") }
        if let sleep = baselineSleep, sleep < 7 { tags.append("睡眠受限") }
        if typeCounts.contains(where: { $0.contains("Running") || $0.contains("Cycling") }) { tags.append("有氧基础型") }
        if typeCounts.contains(where: { $0.contains("Strength") }) { tags.append("力量训练导向") }
        if acwr > 1.3 { tags.append("负荷偏高") }
        if let recovery = currentRecovery, recovery < 50 { tags.append("恢复受限") }
        if let recovery = currentRecovery, recovery >= 70 { tags.append("恢复良好") }
        if workouts.count < 10 { tags.append("数据积累期") }

        // Strengths (Chinese)
        var strengths: [String] = []
        if let sleep = baselineSleep, sleep >= 7.5 { strengths.append("睡眠时长充足稳定") }
        if let steps = baselineSteps, steps > 9000 { strengths.append("日常活动量高") }
        if let rhr = baselineRHR, rhr < 65 { strengths.append("静息心率偏低，心肺效率好") }
        if let hrv = baselineHRV, hrv > 45 { strengths.append("心率变异性良好") }
        if acwr >= 0.8 && acwr <= 1.2 { strengths.append("训练负荷均衡") }

        // Constraints (Chinese)
        var constraints: [String] = []
        if let sleep = baselineSleep, sleep < 6.5 { constraints.append("平均睡眠不足 6.5 小时") }
        if acwr > 1.5 { constraints.append("急慢性负荷比偏高，受伤风险上升") }
        if let rhr = baselineRHR, let current = recent7.last?.restingHeartRate, current > rhr * 1.08 { constraints.append("静息心率较基线升高 8% 以上") }
        if sleepConsistency != nil && sleepConsistency! < 0.5 { constraints.append("睡眠时间不规律") }

        // Opportunities (Chinese)
        var opportunities: [String] = []
        if baselineSleep != nil && baselineSleep! < 7 { opportunities.append("优先保证每天 7-8 小时睡眠") }
        if activityConsistency != nil && activityConsistency! < 0.6 { opportunities.append("增加日常活动的规律性") }
        if workouts.count < 3 { opportunities.append("每周增加 2-3 次结构化训练") }
        if acwr < 0.8 { opportunities.append("可以逐步增加训练量") }

        // Limitations (Chinese)
        var limitations: [String] = []
        if sorted.count < 14 { limitations.append("有效数据少于 14 天") }
        if baselineHRV == nil { limitations.append("缺少 HRV 数据") }
        if baselineSteps == nil { limitations.append("步数数据有限") }

        // Readiness (Chinese)
        let readiness: String
        if let score = currentRecovery {
            if score >= 75 { readiness = "准备充分" }
            else if score >= 50 { readiness = "轻度受限" }
            else { readiness = "建议休息日" }
        } else { readiness = "数据不足" }

        return PersonalHealthProfile(
            dataRangeStart: dates.min(),
            dataRangeEnd: dates.max(),
            dataCompleteness: dataCompleteness,
            baselineSteps: baselineSteps,
            baselineSleepHours: baselineSleep,
            baselineRestingHeartRate: baselineRHR,
            baselineHRV: baselineHRV,
            baselineTrainingLoad: baselineLoad,
            baselineActiveEnergy: baselineEnergy,
            currentRecoveryScore: currentRecovery,
            currentReadiness: readiness,
            acuteTrainingLoad7d: acute7,
            chronicTrainingLoad28d: chronic28,
            acuteChronicRatio: acwr,
            sleepConsistencyScore: sleepConsistency,
            activityConsistencyScore: activityConsistency,
            cardioStabilityScore: cardioStability,
            trainingRegularityScore: trainingRegularity,
            dominantWorkoutTypes: typeCounts,
            dominantTags: tags,
            strengths: strengths,
            constraints: constraints,
            opportunities: opportunities,
            dataLimitations: limitations
        )
    }

    // MARK: - Helpers

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Consistency score 0-1: lower CV = higher consistency
    private func consistencyScore(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let avg = values.reduce(0, +) / Double(values.count)
        guard avg > 0 else { return nil }
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count)
        let cv = sqrt(variance) / avg
        return max(0, min(1, 1 - cv))
    }

    private func consistencyScoreByWorkouts(_ workouts: [WorkoutSession], days: Int) -> Double? {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for w in workouts { counts[calendar.startOfDay(for: w.startDate), default: 0] += 1 }
        let values = (0..<days).compactMap { day -> Double? in
            guard let date = calendar.date(byAdding: .day, value: -day, to: Date()) else { return nil }
            return Double(counts[calendar.startOfDay(for: date)] ?? 0)
        }
        return consistencyScore(values)
    }
}
