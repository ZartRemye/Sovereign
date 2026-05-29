import Foundation

/// Normalize parsed Apple Health data into Sovereign's internal model types
struct HealthDataNormalizer {

    func normalizeMetrics(_ parsed: [ParsedHealthMetric]) -> [HealthMetricSample] {
        parsed.map { p in
            let metricType = HealthMetricType(rawValue: p.type) ?? .stepCount
            let value = convertValue(p.value, unit: p.unit, targetUnit: standardUnit(for: metricType))
            return HealthMetricSample(
                metricType: metricType,
                value: value,
                unit: standardUnit(for: metricType),
                date: p.startDate,
                source: .appleHealthImport,
                deviceName: p.device ?? p.sourceName
            )
        }
    }

    func normalizeWorkouts(_ parsed: [ParsedWorkout]) -> [WorkoutSession] {
        parsed.map { p in
            let workoutType = WorkoutType.allCases.first { $0.rawValue == p.type } ?? .other
            let load = TrainingLoadAnalyzer.calculateLoad(
                durationMinutes: p.durationSeconds / 60,
                avgHeartRate: p.avgHeartRate,
                maxHeartRate: p.maxHeartRate
            )
            return WorkoutSession(
                workoutType: workoutType,
                startDate: p.startDate,
                endDate: p.endDate,
                durationSeconds: p.durationSeconds,
                distanceMeters: p.distanceMeters,
                avgHeartRate: p.avgHeartRate,
                maxHeartRate: p.maxHeartRate,
                activeEnergyKJ: p.energyKJ,
                trainingLoad: load,
                source: .appleHealthImport
            )
        }
    }

    func normalizeSleep(_ parsed: [ParsedSleep]) -> [SleepSession] {
        // Group sleep records by date and merge overlapping
        let calendar = Calendar.current
        var grouped: [Date: [ParsedSleep]] = [:]

        for record in parsed {
            let day = calendar.startOfDay(for: record.startDate)
            grouped[day, default: []].append(record)
        }

        return grouped.map { (day, records) in
            let startDate = records.map(\.startDate).min() ?? day
            let endDate = records.map(\.endDate).max() ?? day
            let duration = endDate.timeIntervalSince(startDate)
            let deepSleep = records.filter { $0.value >= 4 }.map { $0.endDate.timeIntervalSince($0.startDate) }.reduce(0, +)

            return SleepSession(
                startDate: startDate,
                endDate: endDate,
                durationSeconds: max(0, duration),
                deepSleepSeconds: deepSleep,
                remSleepSeconds: duration * 0.2, // Estimated
                coreSleepSeconds: duration - deepSleep - (duration * 0.2),
                qualityScore: duration >= 25200 ? 85 : (duration >= 21600 ? 70 : 50),
                source: .appleHealthImport
            )
        }
    }

    // MARK: - Helpers

    private func standardUnit(for type: HealthMetricType) -> String {
        switch type {
        case .stepCount: return "count"
        case .heartRate, .restingHeartRate: return "bpm"
        case .heartRateVariability: return "ms"
        case .activeEnergy: return "kJ"
        case .exerciseTime: return "min"
        case .distance: return "km"
        case .vo2Max: return "mL/kg·min"
        case .sleep: return "hours"
        }
    }

    private func convertValue(_ value: Double, unit: String, targetUnit: String) -> Double {
        if unit == targetUnit { return value }

        // Common conversions
        switch (unit, targetUnit) {
        case ("kcal", "kJ"): return value * 4.184
        case ("Cal", "kJ"): return value * 4.184
        case ("mi", "km"): return value * 1.60934
        case ("m", "km"): return value / 1000
        default: return value
        }
    }
}
