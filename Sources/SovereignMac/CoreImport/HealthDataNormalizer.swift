import Foundation

/// Normalize parsed Apple Health data into Sovereign's internal model types
/// with comprehensive unit conversion.
struct HealthDataNormalizer {

    // MARK: - Public API

    func normalize(
        metrics: [ParsedHealthMetric],
        workouts: [ParsedWorkout],
        sleepRecords: [ParsedSleep]
    ) -> (metrics: [HealthMetricSample], workouts: [WorkoutSession], sleep: [SleepSession]) {
        let normalizedMetrics = normalizeMetrics(metrics)
        let normalizedWorkouts = normalizeWorkouts(workouts)
        let normalizedSleep = normalizeSleep(sleepRecords)
        return (normalizedMetrics, normalizedWorkouts, normalizedSleep)
    }

    func normalizeMetrics(_ parsed: [ParsedHealthMetric]) -> [HealthMetricSample] {
        parsed.compactMap { p in
            let mappedType = mapMetricType(p.type)
            let targetUnit = standardUnit(for: mappedType)
            let convertedValue = convertValue(p.value, fromUnit: p.unit, toUnit: targetUnit, metricType: mappedType)

            return HealthMetricSample(
                metricType: mappedType,
                value: convertedValue,
                unit: targetUnit,
                date: p.startDate,
                source: .appleHealthImport,
                deviceName: p.device ?? p.sourceName
            )
        }
    }

    func normalizeWorkouts(_ parsed: [ParsedWorkout]) -> [WorkoutSession] {
        parsed.map { p in
            let workoutType = mapWorkoutType(p.type)

            // Normalize duration using raw unit
            let (durationSeconds, durationSource, durationWarning) = HealthUnitNormalizer.durationToSeconds(
                value: p.rawDuration,
                unit: p.rawDurationUnit,
                dateBasedSeconds: p.dateBasedDurationSeconds
            )

            // Normalize distance to meters using raw unit
            let distanceMeters = HealthUnitNormalizer.distanceToMeters(
                value: p.rawDistance,
                unit: p.rawDistanceUnit
            )

            // Normalize energy to kcal using raw unit
            let activeEnergyKcal = HealthUnitNormalizer.energyToKcal(
                value: p.rawEnergy,
                unit: p.rawEnergyUnit
            )

            let load = TrainingLoadAnalyzer.calculateLoad(
                workoutType: workoutType,
                durationMinutes: durationSeconds / 60,
                avgHeartRate: p.avgHeartRate,
                maxHeartRate: p.maxHeartRate
            )

            return WorkoutSession(
                workoutType: workoutType,
                startDate: p.startDate,
                endDate: p.endDate,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                avgHeartRate: p.avgHeartRate,
                maxHeartRate: p.maxHeartRate,
                activeEnergyKcal: activeEnergyKcal,
                trainingLoad: load,
                source: .appleHealthImport,
                sourceName: p.sourceName,
                rawWorkoutActivityType: p.originalType,
                rawDuration: p.rawDuration,
                rawDurationUnit: p.rawDurationUnit,
                rawDistance: p.rawDistance,
                rawDistanceUnit: p.rawDistanceUnit,
                rawEnergy: p.rawEnergy,
                rawEnergyUnit: p.rawEnergyUnit,
                durationSource: durationSource.rawValue,
                durationWarning: durationWarning
            )
        }
    }

    func normalizeSleep(_ parsed: [ParsedSleep]) -> [SleepSession] {
        let calendar = Calendar.current
        // Group sleep records by sleep period (night)
        // A night's sleep typically spans across midnight, so we group by the morning date
        var nights: [Date: [ParsedSleep]] = [:]

        for record in parsed {
            // Assign to the morning date (the day you wake up)
            // If endDate is in the morning (4am-12pm), assign to that day
            // Otherwise, assign to the start date's day
            let endHour = calendar.component(.hour, from: record.endDate)
            let morningDate: Date
            if endHour >= 4 && endHour < 12 {
                morningDate = calendar.startOfDay(for: record.endDate)
            } else {
                // If end is late afternoon/evening, it might be a nap — group by start date
                morningDate = calendar.startOfDay(for: record.startDate)
            }
            nights[morningDate, default: []].append(record)
        }

        return nights.compactMap { (morningDate, records) -> SleepSession? in
            guard let startDate = records.map(\.startDate).min(),
                  let endDate = records.map(\.endDate).max() else { return nil }

            let duration = endDate.timeIntervalSince(startDate)
            guard duration > 0 else { return nil }

            // Calculate sleep stages
            var timeInBed: Double = 0
            var asleepTime: Double = 0
            var deepSleep: Double = 0
            var remSleep: Double = 0
            var coreSleep: Double = 0
            var awakeTime: Double = 0

            for record in records {
                let recordDuration = record.endDate.timeIntervalSince(record.startDate)
                guard recordDuration > 0 else { continue }

                switch Int(record.value) {
                case 0: // InBed
                    timeInBed += recordDuration
                case 1: // Asleep unspecified
                    asleepTime += recordDuration
                case 2: // AsleepCore
                    coreSleep += recordDuration
                    asleepTime += recordDuration
                case 3: // AsleepDeep
                    deepSleep += recordDuration
                    asleepTime += recordDuration
                case 4: // AsleepREM
                    remSleep += recordDuration
                    asleepTime += recordDuration
                case 5: // Awake
                    awakeTime += recordDuration
                    timeInBed += recordDuration
                default:
                    asleepTime += recordDuration
                }
            }

            // If no specific asleep stages but have in-bed data, estimate
            let totalSleepDuration: Double
            if asleepTime > 0 {
                totalSleepDuration = asleepTime
            } else if timeInBed > 0 {
                // Only InBed data — mark as low quality
                totalSleepDuration = timeInBed * 0.85 // Rough estimate
            } else {
                totalSleepDuration = duration
            }

            // Estimate stages if not parsed
            let effectiveDeep = deepSleep > 0 ? deepSleep : totalSleepDuration * 0.18
            let effectiveREM = remSleep > 0 ? remSleep : totalSleepDuration * 0.22
            let effectiveCore = coreSleep > 0 ? coreSleep : (totalSleepDuration - effectiveDeep - effectiveREM - awakeTime)

            // Quality score based on duration and data quality
            let hasRealStages = deepSleep > 0 || remSleep > 0 || coreSleep > 0
            let dataQuality: Double = hasRealStages ? 1.0 : (timeInBed > 0 && asleepTime == 0 ? 0.4 : 0.7)
            let qualityScore: Double
            if totalSleepDuration >= 28800 { qualityScore = 85 * dataQuality }
            else if totalSleepDuration >= 25200 { qualityScore = 75 * dataQuality }
            else if totalSleepDuration >= 21600 { qualityScore = 60 * dataQuality }
            else { qualityScore = 40 * dataQuality }

            return SleepSession(
                startDate: startDate,
                endDate: endDate,
                durationSeconds: totalSleepDuration,
                timeInBedSeconds: timeInBed > 0 ? timeInBed : duration,
                deepSleepSeconds: effectiveDeep,
                remSleepSeconds: effectiveREM,
                coreSleepSeconds: max(0, effectiveCore),
                awakeSeconds: awakeTime,
                sleepDataQuality: dataQuality,
                qualityScore: qualityScore,
                source: .appleHealthImport
            )
        }
    }

    // MARK: - Metric Type Mapping

    private func mapMetricType(_ raw: String) -> HealthMetricType {
        // Direct match
        if let matched = HealthMetricType(rawValue: raw) {
            return matched
        }

        // Case-insensitive
        let lowercased = raw.lowercased()
        for type in HealthMetricType.allCases {
            if type.rawValue.lowercased() == lowercased { return type }
        }

        // Partial match
        if lowercased.contains("stepcount") { return .stepCount }
        if lowercased.contains("restingheartrate") { return .restingHeartRate }
        if lowercased.contains("heartratevariability") { return .heartRateVariability }
        if lowercased.contains("activeenergy") { return .activeEnergy }
        if lowercased.contains("exercisetime") { return .exerciseTime }
        if lowercased.contains("distancewalkingrunning") { return .distance }
        if lowercased.contains("distancecycling") { return .distance }
        if lowercased.contains("vo2max") { return .vo2Max }
        if lowercased.contains("bodymass") { return .bodyMass }
        if lowercased.contains("height") { return .height }
        if lowercased.contains("heartrate") { return .heartRate }
        if lowercased.contains("sleep") { return .sleep }

        return .stepCount
    }

    private func mapWorkoutType(_ raw: String) -> WorkoutType {
        WorkoutType.allCases.first { $0.rawValue == raw } ?? .other
    }

    // MARK: - Standard Units

    private func standardUnit(for type: HealthMetricType) -> String {
        switch type {
        case .stepCount: return "count"
        case .heartRate: return "bpm"
        case .restingHeartRate: return "bpm"
        case .heartRateVariability: return "ms"
        case .activeEnergy: return "kJ"
        case .exerciseTime: return "min"
        case .distance: return "meter"
        case .vo2Max: return "mL/kg·min"
        case .sleep: return "hour"
        case .bodyMass: return "kg"
        case .height: return "cm"
        }
    }

    // MARK: - Unit Conversion (comprehensive)

    private func convertValue(_ value: Double, fromUnit: String, toUnit: String, metricType: HealthMetricType) -> Double {
        let from = fromUnit.lowercased().trimmingCharacters(in: .whitespaces)
        let to = toUnit.lowercased().trimmingCharacters(in: .whitespaces)
        if from == to { return value }

        // --- Distance ---
        if to == "meter" {
            switch from {
            case "km": return value * 1000
            case "m", "meter", "meters": return value
            case "mi", "mile", "miles": return value * 1609.34
            case "ft", "feet": return value * 0.3048
            case "yd", "yards": return value * 0.9144
            default: break
            }
        }

        if to == "km" {
            switch from {
            case "m", "meter", "meters": return value / 1000
            case "mi", "mile", "miles": return value * 1.60934
            default: break
            }
        }

        // --- Energy ---
        if to == "kj" {
            switch from {
            case "kcal", "cal": return value * 4.184
            case "kj": return value
            case "j", "joule", "joules": return value / 1000
            default: break
            }
        }

        if to == "kcal" {
            switch from {
            case "kj": return value / 4.184
            case "j", "joule", "joules": return value / 4184
            default: break
            }
        }

        // --- Heart Rate ---
        if to == "bpm" {
            switch from {
            case "count/min", "bpm", "beats/min": return value
            case "count/s", "hz": return value * 60
            default: break
            }
        }

        // --- Time ---
        if to == "min" || to == "minute" || to == "minutes" {
            switch from {
            case "s", "sec", "second", "seconds": return value / 60
            case "min", "minute", "minutes": return value
            case "h", "hr", "hour", "hours": return value * 60
            default: break
            }
        }

        if to == "hour" || to == "hours" {
            switch from {
            case "s", "sec", "second", "seconds": return value / 3600
            case "min", "minute", "minutes": return value / 60
            case "h", "hr", "hour", "hours": return value
            default: break
            }
        }

        // --- Mass ---
        if to == "kg" {
            switch from {
            case "lb", "lbs", "pound", "pounds": return value * 0.453592
            case "g", "gram", "grams": return value / 1000
            case "st", "stone": return value * 6.35029
            default: break
            }
        }

        // --- Height ---
        if to == "cm" {
            switch from {
            case "m", "meter", "meters": return value * 100
            case "in", "inch", "inches": return value * 2.54
            case "ft", "feet": return value * 30.48
            case "mm", "millimeter": return value / 10
            default: break
            }
        }

        // --- HRV ---
        if to == "ms" {
            switch from {
            case "s", "sec", "second", "seconds": return value * 1000
            default: break
            }
        }

        // If no conversion matched, return as-is
        return value
    }

    private func convertDistanceToMeters(_ value: Double, unit: String) -> Double {
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        switch u {
        case "m", "meter", "meters": return value
        case "km", "kilometer", "kilometers": return value * 1000
        case "mi", "mile", "miles": return value * 1609.34
        case "ft", "feet": return value * 0.3048
        default: return value // assume meters
        }
    }
}
