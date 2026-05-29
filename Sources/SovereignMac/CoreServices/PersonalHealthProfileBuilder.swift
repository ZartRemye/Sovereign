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

        // Tags
        var tags: [String] = []
        if let steps = baselineSteps, steps > 8000 { tags.append("Active Lifestyle") }
        if let sleep = baselineSleep, sleep < 7 { tags.append("Sleep Constrained") }
        if typeCounts.contains(where: { $0.contains("Running") || $0.contains("Cycling") }) { tags.append("Endurance Base") }
        if typeCounts.contains(where: { $0.contains("Strength") }) { tags.append("Strength Focused") }
        if acwr > 1.3 { tags.append("Elevated Load") }
        if let recovery = currentRecovery, recovery < 50 { tags.append("Recovery Limited") }
        if let recovery = currentRecovery, recovery >= 70 { tags.append("Recovering Well") }
        if workouts.count < 10 { tags.append("Building History") }

        // Strengths
        var strengths: [String] = []
        if let sleep = baselineSleep, sleep >= 7.5 { strengths.append("Consistent sleep duration") }
        if let steps = baselineSteps, steps > 9000 { strengths.append("High daily activity") }
        if let rhr = baselineRHR, rhr < 65 { strengths.append("Low resting heart rate") }
        if let hrv = baselineHRV, hrv > 45 { strengths.append("Good HRV") }
        if acwr >= 0.8 && acwr <= 1.2 { strengths.append("Balanced training load") }

        // Constraints
        var constraints: [String] = []
        if let sleep = baselineSleep, sleep < 6.5 { constraints.append("Sleep below 6.5h") }
        if acwr > 1.5 { constraints.append("High injury risk (ACWR)") }
        if let rhr = baselineRHR, let current = recent7.last?.restingHeartRate, current > rhr * 1.08 { constraints.append("Resting HR elevated") }
        if sleepConsistency != nil && sleepConsistency! < 0.5 { constraints.append("Irregular sleep pattern") }

        // Opportunities
        var opportunities: [String] = []
        if baselineSleep != nil && baselineSleep! < 7 { opportunities.append("Prioritize 7-8h sleep") }
        if activityConsistency != nil && activityConsistency! < 0.6 { opportunities.append("More consistent daily activity") }
        if workouts.count < 3 { opportunities.append("Add 2-3 weekly workouts") }
        if acwr < 0.8 { opportunities.append("Gradually increase training volume") }

        // Limitations
        var limitations: [String] = []
        if sorted.count < 14 { limitations.append("Less than 14 days of data") }
        if baselineHRV == nil { limitations.append("No HRV data") }
        if baselineSteps == nil { limitations.append("Limited step data") }

        // Readiness
        let readiness: String
        if let score = currentRecovery {
            if score >= 75 { readiness = "Ready" }
            else if score >= 50 { readiness = "Limited" }
            else { readiness = "Rest Day Recommended" }
        } else { readiness = "Insufficient Data" }

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
