import Foundation

/// Generates realistic mock health data for development and demo purposes.
/// Covers ~90 days of data. ALL mock data is clearly marked with source .mockLive ("Demo Data").
actor MockHealthDataProvider {
    static let shared = MockHealthDataProvider()

    private init() {}

    // MARK: - Generate Full Dataset

    func generateAllData() -> MockDataSet {
        let metrics = generateMetrics(days: 90)
        let workouts = generateWorkouts(days: 90)
        let sleepSessions = generateSleepSessions(days: 90)
        let summaries = generateDailySummaries(days: 90, metrics: metrics, workouts: workouts, sleep: sleepSessions)
        return MockDataSet(
            metrics: metrics,
            workouts: workouts,
            sleepSessions: sleepSessions,
            dailySummaries: summaries
        )
    }

    func generateRecentMetrics(days: Int = 7) -> [HealthMetricSample] {
        generateMetrics(days: days)
    }

    // MARK: - Live Mock Data (for Live Monitor)

    func generateLiveHeartRate() -> Double {
        let baseHR = 62.0 + Double.random(in: -5...8)
        if Int.random(in: 1...20) == 1 {
            return baseHR + Double.random(in: 10...25)
        }
        return baseHR
    }

    func generateLiveSteps() -> Int {
        let hour = Calendar.current.component(.hour, from: Date())
        let maxSteps = 10000
        let progress = min(Double(hour) / 22.0, 1.0)
        return Int(Double(maxSteps) * progress + Double.random(in: -200...200))
    }

    // MARK: - Private Generators

    private func generateMetrics(days: Int) -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            // Daily steps
            let baseSteps = Double.random(in: 6000...12000)
            let isRestDay = dayOffset % 7 == 0 || dayOffset % 7 == 6
            let steps = isRestDay ? baseSteps * Double.random(in: 0.4...0.7) : baseSteps

            samples.append(HealthMetricSample(
                metricType: .stepCount,
                value: steps,
                unit: "count",
                date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date,
                source: .mockLive
            ))

            // Resting HR
            let trendHR = 62.0 + sin(Double(dayOffset) * 0.1) * 3.0
            let restingHR = trendHR + Double.random(in: -2...3)
            samples.append(HealthMetricSample(
                metricType: .restingHeartRate,
                value: restingHR,
                unit: "bpm",
                date: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: date) ?? date,
                source: .mockLive
            ))

            // HRV
            let hrv = 45.0 + Double.random(in: -15...20)
            samples.append(HealthMetricSample(
                metricType: .heartRateVariability,
                value: max(15, hrv),
                unit: "ms",
                date: calendar.date(bySettingHour: 7, minute: 35, second: 0, of: date) ?? date,
                source: .mockLive
            ))

            // Active energy
            let energy = isRestDay ? Double.random(in: 800...1500) : Double.random(in: 1800...3200)
            samples.append(HealthMetricSample(
                metricType: .activeEnergy,
                value: energy,
                unit: "kJ",
                date: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date,
                source: .mockLive
            ))

            // Exercise minutes
            let exercise = isRestDay ? Int.random(in: 0...15) : Int.random(in: 25...60)
            samples.append(HealthMetricSample(
                metricType: .exerciseTime,
                value: Double(exercise),
                unit: "min",
                date: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date,
                source: .mockLive
            ))

            // Distance (walking+running)
            let distance = Double(steps) * 0.0007 + Double.random(in: -0.5...0.5)
            samples.append(HealthMetricSample(
                metricType: .distance,
                value: max(0, distance * 1000), // store in meters
                unit: "meter",
                date: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date,
                source: .mockLive
            ))

            // VO2Max (every few days)
            if dayOffset % 3 == 0 {
                let vo2max = 42.0 + Double.random(in: -3...3)
                samples.append(HealthMetricSample(
                    metricType: .vo2Max,
                    value: vo2max,
                    unit: "mL/kg·min",
                    date: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date,
                    source: .mockLive
                ))
            }

            // Body mass (weekly)
            if dayOffset % 7 == 0 {
                samples.append(HealthMetricSample(
                    metricType: .bodyMass,
                    value: 72.0 + Double.random(in: -1.5...1.5),
                    unit: "kg",
                    date: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date,
                    source: .mockLive
                ))
            }

            // Height (only once)
            if dayOffset == 0 {
                samples.append(HealthMetricSample(
                    metricType: .height,
                    value: 175.0,
                    unit: "cm",
                    date: date,
                    source: .mockLive
                ))
            }
        }

        return samples
    }

    private func generateWorkouts(days: Int) -> [WorkoutSession] {
        var workouts: [WorkoutSession] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let types: [WorkoutType] = [.running, .walking, .cycling, .strength, .yoga, .hiit]

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            let workoutsToday: Int
            if dayOffset % 7 == 0 || dayOffset % 7 == 3 {
                workoutsToday = 0 // Rest days
            } else {
                workoutsToday = Int.random(in: 0...1)
            }

            for _ in 0..<workoutsToday {
                let type = types.randomElement()!
                let duration: Double
                let distance: Double?
                let avgHR: Double?
                let maxHR: Double?

                switch type {
                case .running:
                    duration = Double.random(in: 1500...3600)
                    distance = duration / 60 * Double.random(in: 0.15...0.25)
                    avgHR = Double.random(in: 140...165)
                    maxHR = avgHR.map { $0 + Double.random(in: 10...25) }
                case .cycling:
                    duration = Double.random(in: 2400...5400)
                    distance = duration / 60 * Double.random(in: 0.35...0.55)
                    avgHR = Double.random(in: 125...150)
                    maxHR = avgHR.map { $0 + Double.random(in: 10...20) }
                case .strength:
                    duration = Double.random(in: 2400...4200)
                    distance = nil
                    avgHR = Double.random(in: 110...140)
                    maxHR = avgHR.map { $0 + Double.random(in: 5...15) }
                case .walking:
                    duration = Double.random(in: 1800...4800)
                    distance = duration / 60 * Double.random(in: 0.08...0.12)
                    avgHR = Double.random(in: 90...115)
                    maxHR = avgHR.map { $0 + Double.random(in: 5...15) }
                default:
                    duration = Double.random(in: 1800...3600)
                    distance = nil
                    avgHR = Double.random(in: 100...140)
                    maxHR = avgHR.map { $0 + Double.random(in: 5...20) }
                }

                let startHour = Int.random(in: 6...19)
                let startDate = calendar.date(bySettingHour: startHour, minute: Int.random(in: 0...59), second: 0, of: date) ?? date
                let endDate = startDate.addingTimeInterval(duration)

                let load = TrainingLoadAnalyzer.calculateLoad(
                    workoutType: type,
                    durationMinutes: duration / 60,
                    avgHeartRate: avgHR,
                    maxHeartRate: maxHR
                )

                workouts.append(WorkoutSession(
                    workoutType: type,
                    startDate: startDate,
                    endDate: endDate,
                    durationSeconds: duration,
                    distanceMeters: distance.map { $0 * 1000 },
                    avgHeartRate: avgHR,
                    maxHeartRate: maxHR,
                    activeEnergyKcal: duration / 60 * Double.random(in: 15...40) / 4.184,
                    trainingLoad: load,
                    source: .mockLive
                ))
            }
        }

        return workouts
    }

    private func generateSleepSessions(days: Int) -> [SleepSession] {
        var sessions: [SleepSession] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            let bedtimeHour = Int.random(in: 22...23)
            let bedMinute = Int.random(in: 0...59)
            var bedComponents = calendar.dateComponents([.year, .month, .day], from: date)
            bedComponents.hour = bedtimeHour
            bedComponents.minute = bedMinute
            guard let bedDate = calendar.date(from: bedComponents) else { continue }
            let sleepStart = calendar.date(byAdding: .day, value: -1, to: bedDate) ?? bedDate

            let wakeHour = Int.random(in: 6...8)
            let wakeMinute = Int.random(in: 0...59)
            var wakeComponents = calendar.dateComponents([.year, .month, .day], from: date)
            wakeComponents.hour = wakeHour
            wakeComponents.minute = wakeMinute
            guard let wakeDate = calendar.date(from: wakeComponents) else { continue }

            let duration = wakeDate.timeIntervalSince(sleepStart)
            guard duration > 0 else { continue }

            let hasPoorSleep = dayOffset % 5 == 0
            let actualDuration = hasPoorSleep ? duration * Double.random(in: 0.65...0.85) : duration
            let quality = hasPoorSleep ? Double.random(in: 0.3...0.55) : Double.random(in: 0.65...0.9)

            sessions.append(SleepSession(
                startDate: sleepStart,
                endDate: wakeDate,
                durationSeconds: actualDuration,
                timeInBedSeconds: duration,
                deepSleepSeconds: actualDuration * Double.random(in: 0.12...0.22),
                remSleepSeconds: actualDuration * Double.random(in: 0.18...0.28),
                coreSleepSeconds: actualDuration * Double.random(in: 0.45...0.55),
                awakeSeconds: duration * 0.05,
                sleepDataQuality: 0.3, // Mock data is low quality
                qualityScore: quality * 100,
                source: .mockLive
            ))
        }

        return sessions
    }

    private func generateDailySummaries(days: Int, metrics: [HealthMetricSample],
                                         workouts: [WorkoutSession], sleep: [SleepSession]) -> [DailySummary] {
        var summaries: [DailySummary] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let summary = DailySummaryBuilder.build(
                date: date,
                metrics: metrics,
                workouts: workouts,
                sleepSessions: sleep,
                previousSummaries: summaries
            )
            // Ensure mock data is marked as mock
            summary.sourceRaw = DataSource.mockLive.rawValue
            summaries.append(summary)
        }

        return summaries.sorted { $0.date < $1.date }
    }
}

struct MockDataSet {
    let metrics: [HealthMetricSample]
    let workouts: [WorkoutSession]
    let sleepSessions: [SleepSession]
    let dailySummaries: [DailySummary]
}
