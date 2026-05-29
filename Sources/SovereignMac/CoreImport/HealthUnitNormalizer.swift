import Foundation

// MARK: - Duration Source

enum WorkoutDurationSource: String, Codable, CaseIterable {
    case appleHealthDuration = "Apple Health duration"
    case startEndDate = "Start/End Date"
    case reconciled = "Reconciled"
    case missing = "Missing"
}

// MARK: - Resolved Duration

struct ResolvedWorkoutDuration: Codable, Equatable {
    var rawDuration: Double?
    var rawDurationUnit: String?
    var rawDurationSeconds: Double?

    var startDate: Date?
    var endDate: Date?
    var dateBasedDurationSeconds: Double?

    var finalDurationSeconds: Double
    var finalDurationMinutes: Double
    var source: String  // WorkoutDurationSource.rawValue

    var mismatchSeconds: Double?
    var hasMismatch: Bool
    var warning: String?
}

// MARK: - Workout Duration Truth Resolver

enum WorkoutDurationTruthResolver {

    /// Resolve the true workout duration from raw Apple Health data.
    ///
    /// Rules (in priority order):
    /// 1. If raw duration + unit can be parsed → compute rawDurationSeconds
    /// 2. If start/end dates available → compute dateBasedDurationSeconds
    /// 3. If both exist and differ by >5min or >20%:
    ///    - If rawDurationUnit is empty/unknown → trust date-based
    ///    - If rawDurationSeconds is clearly implausible (< 60s for a multi-hour span) → trust date-based
    ///    - Otherwise, prefer Apple Health duration but record warning
    /// 4. If only one source → use it
    /// 5. If neither → mark as missing
    static func resolve(
        rawDuration: Double?,
        rawDurationUnit: String?,
        startDate: Date?,
        endDate: Date?
    ) -> ResolvedWorkoutDuration {
        let dateBasedSeconds: Double?
        if let start = startDate, let end = endDate {
            dateBasedSeconds = end.timeIntervalSince(start)
        } else {
            dateBasedSeconds = nil
        }

        // Try to parse raw duration
        let rawSeconds = parseRawDuration(value: rawDuration, unit: rawDurationUnit)

        // Use both + start/end diff to decide final duration
        let final: Double
        let source: WorkoutDurationSource
        var mismatchSeconds: Double? = nil
        var hasMismatch = false
        var warning: String? = nil

        switch (rawSeconds, dateBasedSeconds) {
        case (let .some(raw), let .some(dateBased)):
            let diff = abs(raw - dateBased)
            let pctDiff = dateBased > 0 ? diff / dateBased : 0
            let unitEmpty = (rawDurationUnit ?? "").trimmingCharacters(in: .whitespaces).isEmpty

            if diff > 300 || pctDiff > 0.20 {
                hasMismatch = true
                mismatchSeconds = diff

                // If unit was empty/unknown and dates are clearly more plausible
                // OR if raw is absurdly small compared to date span
                if unitEmpty || (raw < 60 && dateBased > 300) {
                    final = dateBased
                    source = .reconciled
                    warning = "Raw AH duration (\(String(format: "%.0f", raw))s) differs significantly from start/end span (\(String(format: "%.0f", dateBased))s). Using date-based duration (reconciled)."
                } else {
                    // Unit was known but values differ — still prefer dates if raw seems wrong
                    if raw < 60 && dateBased > 600 {
                        final = dateBased
                        source = .reconciled
                        warning = "AH duration (\(String(format: "%.0f", raw))s, unit: \(rawDurationUnit ?? "?")) is implausibly short for a \(String(format: "%.0f", dateBased / 60))min span. Using date-based duration."
                    } else {
                        final = raw
                        source = .appleHealthDuration
                        warning = "Duration mismatch: AH \(String(format: "%.0f", raw))s vs dates \(String(format: "%.0f", dateBased))s (\(String(format: "%.0f", pctDiff * 100))% diff). Using AH duration. Reimport or recompute to use date-based."
                    }
                }
            } else {
                // Close enough — use AH duration
                final = raw
                source = .appleHealthDuration
            }

        case (let .some(raw), .none):
            final = raw
            source = .appleHealthDuration

        case (.none, let .some(dateBased)):
            final = dateBased
            source = .startEndDate

        case (.none, .none):
            final = 0
            source = .missing
            warning = "No duration data available."
        }

        return ResolvedWorkoutDuration(
            rawDuration: rawDuration,
            rawDurationUnit: rawDurationUnit,
            rawDurationSeconds: rawSeconds,
            startDate: startDate,
            endDate: endDate,
            dateBasedDurationSeconds: dateBasedSeconds,
            finalDurationSeconds: max(0, final),
            finalDurationMinutes: max(0, final) / 60,
            source: source.rawValue,
            mismatchSeconds: mismatchSeconds,
            hasMismatch: hasMismatch,
            warning: warning
        )
    }

    /// Parse raw Apple Health duration + unit into seconds.
    /// Returns nil if value is nil.
    private static func parseRawDuration(value: Double?, unit: String?) -> Double? {
        guard let value = value else { return nil }
        let unitLower = (unit ?? "").lowercased().trimmingCharacters(in: .whitespaces)

        switch unitLower {
        case "s", "sec", "second", "seconds":
            return value
        case "min", "mins", "minute", "minutes":
            return value * 60
        case "h", "hr", "hrs", "hour", "hours":
            return value * 3600
        case "":
            // Empty unit — Apple Health almost always includes durationUnit.
            // If missing, the value MIGHT be in seconds but we can't be sure.
            // Return as seconds but flag for mismatch detection to override.
            return value
        default:
            // Unknown unit — return nil so date-based takes over
            return nil
        }
    }
}

// MARK: - Health Unit Normalizer (general purpose)

enum HealthUnitNormalizer {

    /// Format duration for display
    static func formatDuration(seconds: Double) -> String {
        if seconds <= 0 { return "0s" }
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        let minutes = Int((seconds / 60).rounded())
        if minutes == 0 { return "1m" }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(hours)h"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours > 0 {
            return "\(days)d \(remainingHours)h"
        }
        return "\(days)d"
    }

    // MARK: - Distance

    static func distanceToMeters(value: Double?, unit: String?) -> Double? {
        guard let value = value else { return nil }
        let unitLower = (unit ?? "m").lowercased().trimmingCharacters(in: .whitespaces)

        switch unitLower {
        case "m", "meter", "meters": return value
        case "km", "kilometer", "kilometers": return value * 1000
        case "mi", "mile", "miles": return value * 1609.34
        case "ft", "feet", "foot": return value * 0.3048
        case "yd", "yard", "yards": return value * 0.9144
        default: return value
        }
    }

    // MARK: - Energy

    static func energyToKcal(value: Double?, unit: String?) -> Double? {
        guard let value = value else { return nil }
        let unitLower = (unit ?? "kcal").lowercased().trimmingCharacters(in: .whitespaces)

        switch unitLower {
        case "kcal", "cal", "calorie", "calories": return value
        case "kj", "kilojoule", "kilojoules": return value / 4.184
        case "j", "joule", "joules": return value / 4184
        default: return value
        }
    }

    static func energyToKJ(value: Double?, unit: String?) -> Double? {
        guard let kcal = energyToKcal(value: value, unit: unit) else { return nil }
        return kcal * 4.184
    }
}
