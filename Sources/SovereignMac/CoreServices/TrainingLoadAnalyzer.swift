import Foundation

// MARK: - Training Load Result

enum TrainingLoadConfidence: String, Codable {
    case high = "High (HR-based)"
    case medium = "Medium (type + HR estimated)"
    case low = "Low (type-based estimate)"
}

struct TrainingLoadResult: Codable, Equatable {
    var load: Double
    var basis: String
    var confidence: TrainingLoadConfidence
    var intensityLabel: String
}

struct TrainingLoadAnalyzer {
    /// Full result with basis and confidence.
    static func calculateLoadResult(
        workoutType: WorkoutType,
        durationMinutes: Double,
        avgHeartRate: Double?,
        maxHeartRate: Double?,
        estimatedMaxHR: Double = 190,
        estimatedRestingHR: Double = 60
    ) -> TrainingLoadResult {
        guard durationMinutes > 0 else {
            return TrainingLoadResult(load: 0, basis: "Zero duration", confidence: .low, intensityLabel: "None")
        }

        if let avgHR = avgHeartRate {
            let hrReserve = max(estimatedMaxHR - estimatedRestingHR, 1)
            let hrRatio = max(0, (avgHR - estimatedRestingHR)) / hrReserve

            let intensityFactor: Double
            let label: String
            if hrRatio < 0.5 {
                intensityFactor = 0.5; label = "Very Low"
            } else if hrRatio < 0.65 {
                intensityFactor = 1.0; label = "Low"
            } else if hrRatio < 0.75 {
                intensityFactor = 1.8; label = "Moderate"
            } else if hrRatio < 0.85 {
                intensityFactor = 2.8; label = "High"
            } else {
                intensityFactor = 4.0; label = "Very High"
            }

            let load = durationMinutes * intensityFactor * hrRatio
            return TrainingLoadResult(
                load: load,
                basis: "TRIMP: \(String(format: "%.0f", durationMinutes))min × \(String(format: "%.1f", intensityFactor)) × HRratio \(String(format: "%.2f", hrRatio)) (avgHR \(String(format: "%.0f", avgHR)))",
                confidence: .high,
                intensityLabel: label
            )
        }

        // No HR — type-based estimation
        let factor = typeBasedIntensityFactor(workoutType)
        let load = durationMinutes * factor
        let label: String
        if factor < 1.0 { label = "Very Low" }
        else if factor < 1.5 { label = "Low" }
        else if factor < 2.0 { label = "Moderate" }
        else if factor < 2.5 { label = "High" }
        else { label = "Very High" }

        return TrainingLoadResult(
            load: load,
            basis: "Type-based: \(workoutType.rawValue) × \(String(format: "%.1f", factor)) × \(String(format: "%.0f", durationMinutes))min",
            confidence: .low,
            intensityLabel: label
        )
    }

    /// Legacy: returns load value only.
    static func calculateLoad(
        workoutType: WorkoutType,
        durationMinutes: Double,
        avgHeartRate: Double?,
        maxHeartRate: Double?,
        estimatedMaxHR: Double = 190,
        estimatedRestingHR: Double = 60
    ) -> Double {
        calculateLoadResult(workoutType: workoutType, durationMinutes: durationMinutes, avgHeartRate: avgHeartRate, maxHeartRate: maxHeartRate, estimatedMaxHR: estimatedMaxHR, estimatedRestingHR: estimatedRestingHR).load
    }

    /// Intensity factor by workout type when no HR data is available.
    /// These are conservative estimates based on typical MET values.
    private static func typeBasedIntensityFactor(_ type: WorkoutType) -> Double {
        switch type {
        case .walking: return 0.8
        case .yoga, .pilates, .taiChi: return 0.6
        case .running: return 2.5
        case .cycling: return 2.0
        case .swimming: return 2.2
        case .hiit: return 3.0
        case .strength, .functionalStrength: return 1.6
        case .hiking: return 2.0
        case .crossTraining: return 1.8
        case .rowing: return 2.3
        case .elliptical: return 1.5
        case .stairClimbing: return 2.5
        case .dance: return 1.5
        case .mixedCardio: return 1.8
        case .other: return 1.0
        }
    }

    /// Whether the load calculation has high confidence (HR data) or low confidence (type-based)
    static func confidence(avgHeartRate: Double?) -> String {
        avgHeartRate != nil ? "High (HR-based)" : "Low (type-based estimate)"
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
                workoutType: workout.workoutType,
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
