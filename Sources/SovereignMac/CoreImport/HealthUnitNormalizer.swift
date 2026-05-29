import Foundation

/// Normalizes Apple Health units to Sovereign's internal standard units.
enum HealthUnitNormalizer {

    // MARK: - Duration

    /// Convert Apple Health duration + durationUnit to seconds.
    /// Returns nil only if value is nil; if unit is unknown, tries date-based fallback.
    static func durationToSeconds(value: Double?, unit: String?, dateBasedSeconds: Double) -> (seconds: Double, source: DurationSource, warning: String?) {
        guard let value = value else {
            // No raw duration — use date-based
            return (dateBasedSeconds, .startEndDate, nil)
        }

        let unitLower = (unit ?? "").lowercased().trimmingCharacters(in: .whitespaces)

        let converted: Double
        switch unitLower {
        case "s", "sec", "second", "seconds", "":
            // Empty unit — Apple Health sometimes omits unit when value is seconds
            converted = value
        case "min", "mins", "minute", "minutes":
            converted = value * 60
        case "h", "hr", "hrs", "hour", "hours":
            converted = value * 3600
        default:
            // Unknown unit — fall back to date-based and warn
            return (dateBasedSeconds, .startEndDate, "Unknown duration unit '\(unit ?? "nil")'. Used start/end date instead.")
        }

        // Compare with date-based for mismatch detection
        var warning: String? = nil
        var source: DurationSource = .appleHealthDuration

        if dateBasedSeconds > 0 {
            let diff = abs(converted - dateBasedSeconds)
            let pctDiff = dateBasedSeconds > 0 ? diff / dateBasedSeconds : 0
            if diff > 300 || pctDiff > 0.20 {
                warning = "Duration mismatch: AH \(String(format: "%.1f", converted))s vs dates \(String(format: "%.1f", dateBasedSeconds))s (\(String(format: "%.0f", pctDiff * 100))% diff). Using AH duration."
                source = .appleHealthDuration
            }
        }

        return (converted, source, warning)
    }

    /// Format duration for display
    static func formatDuration(seconds: Double) -> String {
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
        default: return value // assume meters
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
        default: return value // assume kcal
        }
    }

    static func energyToKJ(value: Double?, unit: String?) -> Double? {
        guard let kcal = energyToKcal(value: value, unit: unit) else { return nil }
        return kcal * 4.184
    }
}

enum DurationSource: String {
    case appleHealthDuration = "Apple Health duration"
    case startEndDate = "Start/End Date"
}
