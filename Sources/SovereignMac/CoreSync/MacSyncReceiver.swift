import Foundation

/// Reserved for future iPhone/Watch sync via MultipeerConnectivity or iCloud.
/// Current phase: accepts JSON-encoded sync envelopes for development/testing.
actor MacSyncReceiver {
    static let shared = MacSyncReceiver()

    private var onMetricReceived: ((LiveMetricEvent) -> Void)?
    private var onWorkoutReceived: ((WorkoutSyncData) -> Void)?
    private var onSleepReceived: ((SleepSyncData) -> Void)?
    private var onSyncComplete: ((SyncEnvelope) -> Void)?

    private var isReceiving = false
    private(set) var lastSyncDate: Date?

    private init() {}

    // MARK: - Callbacks

    func setMetricHandler(_ handler: @escaping (LiveMetricEvent) -> Void) {
        onMetricReceived = handler
    }

    func setWorkoutHandler(_ handler: @escaping (WorkoutSyncData) -> Void) {
        onWorkoutReceived = handler
    }

    func setSleepHandler(_ handler: @escaping (SleepSyncData) -> Void) {
        onSleepReceived = handler
    }

    func setSyncCompleteHandler(_ handler: @escaping (SyncEnvelope) -> Void) {
        onSyncComplete = handler
    }

    // MARK: - JSON Sync (development/testing)

    func receiveJSON(_ jsonData: Data) throws -> SyncEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(SyncEnvelope.self, from: jsonData)

        // Process received data
        for metric in envelope.metrics {
            onMetricReceived?(metric)
        }
        for workout in envelope.workouts {
            onWorkoutReceived?(workout)
        }
        for sleep in envelope.sleepSessions {
            onSleepReceived?(sleep)
        }

        lastSyncDate = Date()
        onSyncComplete?(envelope)

        return envelope
    }

    /// Simulate a sync for development purposes
    func simulateSync() -> SyncEnvelope {
        let now = Date()
        let envelope = SyncEnvelope(
            source: "Mock iPhone Sync",
            deviceName: "iPhone 15 Pro (Simulated)",
            timestamp: now,
            metrics: [
                LiveMetricEvent(type: "heart_rate", value: 68, unit: "bpm", timestamp: now),
                LiveMetricEvent(type: "step_count", value: 8432, unit: "count", timestamp: now),
            ],
            workouts: [],
            sleepSessions: [
                SleepSyncData(
                    startDate: Calendar.current.date(byAdding: .hour, value: -8, to: now)!,
                    endDate: now,
                    durationSeconds: 28800,
                    deepSleepSeconds: 7200,
                    remSleepSeconds: 5400
                ),
            ]
        )

        for metric in envelope.metrics { onMetricReceived?(metric) }
        for workout in envelope.workouts { onWorkoutReceived?(workout) }
        for sleep in envelope.sleepSessions { onSleepReceived?(sleep) }

        lastSyncDate = now
        onSyncComplete?(envelope)

        return envelope
    }

    var dataSourceStatus: String {
        if lastSyncDate != nil {
            return "已连接"
        }
        return "待连接"
    }
}
