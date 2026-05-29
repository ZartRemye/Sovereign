import Foundation

/// Decodes sync messages from iPhone/Watch into Sovereign's internal types.
/// Reserved for future use with MultipeerConnectivity or iCloud sync.
struct SyncMessageDecoder {

    /// Decode a raw sync payload into a SyncEnvelope
    static func decode(_ data: Data) throws -> SyncEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncEnvelope.self, from: data)
    }

    /// Convert sync workout data into WorkoutSession model
    static func convertToWorkoutSession(_ syncWorkout: WorkoutSyncData) -> WorkoutSession {
        let workoutType = WorkoutType.allCases.first { $0.rawValue == syncWorkout.type } ?? .other
        return WorkoutSession(
            workoutType: workoutType,
            startDate: syncWorkout.startDate,
            endDate: syncWorkout.endDate,
            durationSeconds: syncWorkout.durationSeconds,
            distanceMeters: syncWorkout.distanceMeters,
            avgHeartRate: syncWorkout.avgHeartRate,
            maxHeartRate: syncWorkout.maxHeartRate,
            activeEnergyKcal: syncWorkout.activeEnergyKJ != nil ? syncWorkout.activeEnergyKJ! / 4.184 : nil,
            source: .iphoneSync
        )
    }

    /// Convert sync sleep data into SleepSession model
    static func convertToSleepSession(_ syncSleep: SleepSyncData) -> SleepSession {
        return SleepSession(
            startDate: syncSleep.startDate,
            endDate: syncSleep.endDate,
            durationSeconds: syncSleep.durationSeconds,
            deepSleepSeconds: syncSleep.deepSleepSeconds ?? 0,
            remSleepSeconds: syncSleep.remSleepSeconds ?? 0,
            source: .iphoneSync
        )
    }

    /// Convert live metric event into HealthMetricSample
    static func convertToMetricSample(_ event: LiveMetricEvent) -> HealthMetricSample? {
        let metricType = HealthMetricType.allCases.first { type in
            switch (type, event.type) {
            case (.heartRate, "heart_rate"): return true
            case (.stepCount, "step_count"): return true
            case (.restingHeartRate, "resting_heart_rate"): return true
            case (.heartRateVariability, "hrv"): return true
            case (.activeEnergy, "active_energy"): return true
            default: return false
            }
        }

        guard let type = metricType else { return nil }

        return HealthMetricSample(
            metricType: type,
            value: event.value,
            unit: event.unit,
            date: event.timestamp,
            source: .iphoneSync
        )
    }
}
