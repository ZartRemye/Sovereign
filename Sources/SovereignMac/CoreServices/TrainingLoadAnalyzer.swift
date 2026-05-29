import Foundation

struct TrainingLoadAnalyzer {
    /// Calculate training load from workout data
    /// Uses a simplified TRIMP (Training Impulse) model
    static func calculateLoad(
        durationMinutes: Double,
        avgHeartRate: Double?,
        maxHeartRate: Double?,
        estimatedMaxHR: Double = 190
    ) -> Double {
        guard let avgHR = avgHeartRate else {
            // Without HR data, estimate based on duration only
            return durationMinutes * 0.5
        }

        let hrReserve = estimatedMaxHR - 60.0 // Assume resting HR ~60
        guard hrReserve > 0 else { return durationMinutes * 0.5 }

        let hrRatio = (avgHR - 60) / hrReserve
        let intensity: Double

        if hrRatio < 0.5 {
            intensity = 1.0 // Low intensity
        } else if hrRatio < 0.7 {
            intensity = 1.5 // Moderate
        } else if hrRatio < 0.85 {
            intensity = 2.5 // High
        } else {
            intensity = 4.0 // Very high
        }

        // Gender factor could be applied here if we had the data
        return durationMinutes * intensity * hrRatio
    }

    /// Calculate acute:chronic workload ratio
    static func calculateACWR(
        acuteLoads: [Double],   // Last 7 days
        chronicLoads: [Double]  // Last 28 days
    ) -> (acute: Double, chronic: Double, ratio: Double, status: LoadStatus) {
        let acute = acuteLoads.reduce(0, +) / max(Double(acuteLoads.count), 1)
        let chronic = chronicLoads.reduce(0, +) / max(Double(chronicLoads.count), 1)

        let ratio = chronic > 0 ? acute / chronic : 1.0

        let status: LoadStatus
        if ratio > 1.5 {
            status = .highRisk
        } else if ratio > 1.2 {
            status = .moderateHigh
        } else if ratio >= 0.8 {
            status = .optimal
        } else if ratio >= 0.5 {
            status = .low
        } else {
            status = .veryLow
        }

        return (acute, chronic, ratio, status)
    }

    /// Aggregate daily loads from workouts
    static func dailyLoads(from workouts: [WorkoutSession]) -> [Date: Double] {
        var loads: [Date: Double] = [:]
        let calendar = Calendar.current

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let load = calculateLoad(
                durationMinutes: workout.durationSeconds / 60,
                avgHeartRate: workout.avgHeartRate,
                maxHeartRate: workout.maxHeartRate
            )
            loads[day, default: 0] += load
        }

        return loads
    }
}

enum LoadStatus: String {
    case highRisk = "高风险"
    case moderateHigh = "适中偏高"
    case optimal = "最佳"
    case low = "偏低"
    case veryLow = "很低"

    var color: String {
        switch self {
        case .highRisk: return "red"
        case .moderateHigh: return "orange"
        case .optimal: return "green"
        case .low: return "blue"
        case .veryLow: return "gray"
        }
    }
}
