import Foundation
import SwiftData

// MARK: - Metric Types

enum HealthMetricType: String, Codable, CaseIterable {
    case stepCount = "HKQuantityTypeIdentifierStepCount"
    case heartRate = "HKQuantityTypeIdentifierHeartRate"
    case restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    case heartRateVariability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    case activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
    case exerciseTime = "HKQuantityTypeIdentifierAppleExerciseTime"
    case distance = "HKQuantityTypeIdentifierDistanceWalkingRunning"
    case vo2Max = "HKQuantityTypeIdentifierVO2Max"
    case sleep = "HKCategoryTypeIdentifierSleepAnalysis"
    case bodyMass = "HKQuantityTypeIdentifierBodyMass"
    case height = "HKQuantityTypeIdentifierHeight"

    var displayName: String {
        switch self {
        case .stepCount: return "步数"
        case .heartRate: return "心率"
        case .restingHeartRate: return "静息心率"
        case .heartRateVariability: return "HRV"
        case .activeEnergy: return "活动能量"
        case .exerciseTime: return "运动时间"
        case .distance: return "距离"
        case .vo2Max: return "最大摄氧量"
        case .sleep: return "睡眠"
        case .bodyMass: return "体重"
        case .height: return "身高"
        }
    }
}

enum WorkoutType: String, Codable, CaseIterable {
    case running = "Running"
    case walking = "Walking"
    case cycling = "Cycling"
    case strength = "Strength Training"
    case functionalStrength = "Functional Strength"
    case swimming = "Swimming"
    case yoga = "Yoga"
    case hiit = "HIIT"
    case hiking = "Hiking"
    case crossTraining = "Cross Training"
    case elliptical = "Elliptical"
    case rowing = "Rowing"
    case stairClimbing = "Stair Climbing"
    case dance = "Dance"
    case pilates = "Pilates"
    case taiChi = "Tai Chi"
    case mixedCardio = "Mixed Cardio"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "bicycle"
        case .strength, .functionalStrength: "dumbbell"
        case .swimming: "figure.pool.swim"
        case .yoga, .pilates, .taiChi: "figure.mind.and.body"
        case .hiit: "figure.highintensity.intervaltraining"
        case .hiking: "figure.hiking"
        case .crossTraining, .elliptical, .mixedCardio: "figure.mixed.cardio"
        case .rowing: "figure.rower"
        case .stairClimbing: "figure.stairs"
        case .dance: "figure.dance"
        case .other: "figure.mixed.cardio"
        }
    }
}

enum InsightSeverity: String, Codable, CaseIterable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"
    case positive = "Positive"
}

enum DataSource: String, Codable {
    case empty = "Empty"
    case mockLive = "Demo Data"
    case appleHealthImport = "Apple Health Import"
    case iphoneSync = "iPhone Sync"
    case watchLive = "Watch Live"
    case unknown = "Unknown"
}

enum HealthStatus: String, Codable {
    case recoveringWell = "恢复良好"
    case mildFatigue = "轻度疲劳"
    case sleepDeprived = "睡眠不足"
    case trainingLoadHigh = "训练负荷偏高"
    case insufficientData = "数据不足"
}

// MARK: - Health Metric Sample

@Model
final class HealthMetricSample {
    var id: UUID = UUID()
    var metricTypeRaw: String = HealthMetricType.stepCount.rawValue
    var value: Double = 0
    var unit: String = ""
    var date: Date = Date()
    var sourceRaw: String = DataSource.unknown.rawValue
    var deviceName: String?
    /// Fingerprint for dedup (sourceName + type + date + value + unit)
    var fingerprint: String?

    var metricType: HealthMetricType {
        HealthMetricType(rawValue: metricTypeRaw) ?? .stepCount
    }

    var source: DataSource {
        DataSource(rawValue: sourceRaw) ?? .unknown
    }

    init(metricType: HealthMetricType, value: Double, unit: String, date: Date, source: DataSource = .unknown, deviceName: String? = nil) {
        self.metricTypeRaw = metricType.rawValue
        self.value = value
        self.unit = unit
        self.date = date
        self.sourceRaw = source.rawValue
        self.deviceName = deviceName
    }
}

// MARK: - Workout Session

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var workoutTypeRaw: String = WorkoutType.other.rawValue
    var startDate: Date = Date()
    var endDate: Date = Date()

    // Standardized fields
    var durationSeconds: Double = 0
    var distanceMeters: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKcal: Double?   // Now in kcal (was KJ)
    var trainingLoad: Double = 0
    var trainingLoadBasis: String?
    var trainingLoadConfidence: String?
    var sourceRaw: String = DataSource.unknown.rawValue
    var sourceName: String?
    var notes: String?

    // Raw Apple Health fields (for traceability)
    var rawWorkoutActivityType: String?
    var rawDuration: Double?
    var rawDurationUnit: String?
    var rawDistance: Double?
    var rawDistanceUnit: String?
    var rawEnergy: Double?
    var rawEnergyUnit: String?

    // Duration diagnostics
    var durationSource: String?     // "Apple Health duration" or "Start/End Date"
    var durationWarning: String?    // Mismatch warning if AH duration ≠ dates

    // Legacy compatibility
    var activeEnergyKJ: Double? {
        get { (activeEnergyKcal != nil) ? activeEnergyKcal! * 4.184 : nil }
        set { activeEnergyKcal = (newValue != nil) ? newValue! / 4.184 : nil }
    }

    var workoutType: WorkoutType {
        WorkoutType(rawValue: workoutTypeRaw) ?? .other
    }

    var source: DataSource {
        DataSource(rawValue: sourceRaw) ?? .unknown
    }

    var durationFormatted: String {
        HealthUnitNormalizer.formatDuration(seconds: durationSeconds)
    }

    var durationMinutes: Double {
        durationSeconds / 60
    }

    var distanceFormatted: String? {
        guard let meters = distanceMeters else { return nil }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    var rawDurationFormatted: String? {
        guard let raw = rawDuration else { return nil }
        if let unit = rawDurationUnit {
            return "\(String(format: "%.2f", raw)) \(unit)"
        }
        return "\(String(format: "%.2f", raw))"
    }

    var rawEnergyFormatted: String? {
        guard let raw = rawEnergy else { return nil }
        if let unit = rawEnergyUnit {
            return "\(String(format: "%.0f", raw)) \(unit)"
        }
        return "\(String(format: "%.0f", raw))"
    }

    var rawDistanceFormatted: String? {
        guard let raw = rawDistance else { return nil }
        if let unit = rawDistanceUnit {
            return "\(String(format: "%.2f", raw)) \(unit)"
        }
        return "\(String(format: "%.2f", raw))"
    }

    init(workoutType: WorkoutType, startDate: Date, endDate: Date, durationSeconds: Double,
         distanceMeters: Double? = nil, avgHeartRate: Double? = nil, maxHeartRate: Double? = nil,
         activeEnergyKcal: Double? = nil, trainingLoad: Double = 0,
         trainingLoadBasis: String? = nil, trainingLoadConfidence: String? = nil,
         source: DataSource = .unknown,
         sourceName: String? = nil, notes: String? = nil,
         rawWorkoutActivityType: String? = nil,
         rawDuration: Double? = nil, rawDurationUnit: String? = nil,
         rawDistance: Double? = nil, rawDistanceUnit: String? = nil,
         rawEnergy: Double? = nil, rawEnergyUnit: String? = nil,
         durationSource: String? = nil, durationWarning: String? = nil) {
        self.workoutTypeRaw = workoutType.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKcal = activeEnergyKcal
        self.trainingLoad = trainingLoad
        self.trainingLoadBasis = trainingLoadBasis
        self.trainingLoadConfidence = trainingLoadConfidence
        self.sourceRaw = source.rawValue
        self.sourceName = sourceName
        self.notes = notes
        self.rawWorkoutActivityType = rawWorkoutActivityType
        self.rawDuration = rawDuration
        self.rawDurationUnit = rawDurationUnit
        self.rawDistance = rawDistance
        self.rawDistanceUnit = rawDistanceUnit
        self.rawEnergy = rawEnergy
        self.rawEnergyUnit = rawEnergyUnit
        self.durationSource = durationSource
        self.durationWarning = durationWarning
    }
}

// MARK: - Sleep Session

@Model
final class SleepSession {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    var durationSeconds: Double = 0
    var timeInBedSeconds: Double = 0
    var deepSleepSeconds: Double = 0
    var remSleepSeconds: Double = 0
    var coreSleepSeconds: Double = 0
    var awakeSeconds: Double = 0
    /// 0.0-1.0: how reliable the sleep stage data is (1.0 = real stages, <0.5 = estimate from InBed only)
    var sleepDataQuality: Double = 0
    var qualityScore: Double = 0
    var sourceRaw: String = DataSource.unknown.rawValue

    var source: DataSource {
        DataSource(rawValue: sourceRaw) ?? .unknown
    }

    var durationFormatted: String {
        let hours = Int(durationSeconds) / 3600
        let minutes = (Int(durationSeconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var asleepHours: Double { durationSeconds / 3600 }
    var deepSleepHours: Double { deepSleepSeconds / 3600 }
    var remSleepHours: Double { remSleepSeconds / 3600 }

    var hasRealSleepStages: Bool { sleepDataQuality >= 0.8 }
    var isInBedOnly: Bool { sleepDataQuality < 0.5 && timeInBedSeconds > 0 }

    init(startDate: Date, endDate: Date, durationSeconds: Double,
         timeInBedSeconds: Double = 0, deepSleepSeconds: Double = 0,
         remSleepSeconds: Double = 0, coreSleepSeconds: Double = 0,
         awakeSeconds: Double = 0, sleepDataQuality: Double = 0,
         qualityScore: Double = 0, source: DataSource = .unknown) {
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.timeInBedSeconds = timeInBedSeconds
        self.deepSleepSeconds = deepSleepSeconds
        self.remSleepSeconds = remSleepSeconds
        self.coreSleepSeconds = coreSleepSeconds
        self.awakeSeconds = awakeSeconds
        self.sleepDataQuality = sleepDataQuality
        self.qualityScore = qualityScore
        self.sourceRaw = source.rawValue
    }
}

// MARK: - Daily Summary

@Model
final class DailySummary {
    var id: UUID = UUID()
    var date: Date = Date()

    // Core metrics
    var steps: Int = 0
    var averageHeartRate: Double = 0
    var restingHeartRate: Double = 0
    var heartRateVariability: Double?
    var sleepHours: Double = 0          // Asleep time in hours
    var timeInBed: Double = 0           // Total time in bed in hours
    var activeEnergy: Double = 0        // kJ
    var exerciseMinutes: Int = 0
    var walkingRunningDistance: Double = 0 // meters

    // Body metrics
    var bodyMass: Double?               // kg
    var height: Double?                 // cm
    var vo2Max: Double?                 // mL/kg·min

    // Workout summary
    var workoutCount: Int = 0
    var workoutMinutes: Double = 0
    var trainingLoad: Double = 0

    // Recovery
    var recoveryScore: Double = 0
    var healthStatusRaw: String = HealthStatus.insufficientData.rawValue

    // Sleep detail (hours)
    var deepSleep: Double = 0
    var remSleep: Double = 0
    var awakeTime: Double = 0
    var sleepDataQuality: Double = 0

    // Data quality
    var dataCompleteness: Double = 0    // 0.0-1.0
    var sourceRaw: String = DataSource.unknown.rawValue

    // Summary text
    var summaryText: String?

    // Legacy compatibility
    var sleepDurationSeconds: Double {
        get { sleepHours * 3600 }
        set { sleepHours = newValue / 3600 }
    }

    var activeEnergyKJ: Double {
        get { activeEnergy }
        set { activeEnergy = newValue }
    }

    var healthStatus: HealthStatus {
        HealthStatus(rawValue: healthStatusRaw) ?? .insufficientData
    }

    var source: DataSource {
        DataSource(rawValue: sourceRaw) ?? .unknown
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    var sleepFormatted: String {
        if sleepHours >= 1 {
            let hours = Int(sleepHours)
            let minutes = Int((sleepHours - Double(hours)) * 60)
            return "\(hours)h \(minutes)m"
        }
        return "0h"
    }

    init(date: Date, steps: Int = 0, restingHeartRate: Double = 0, heartRateVariability: Double? = nil,
         sleepHours: Double = 0, activeEnergy: Double = 0, exerciseMinutes: Int = 0,
         recoveryScore: Double = 0, trainingLoad: Double = 0, healthStatus: HealthStatus = .insufficientData,
         source: DataSource = .unknown) {
        self.date = date
        self.steps = steps
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.sleepHours = sleepHours
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.recoveryScore = recoveryScore
        self.trainingLoad = trainingLoad
        self.healthStatusRaw = healthStatus.rawValue
        self.sourceRaw = source.rawValue
    }
}

// MARK: - Recovery Score

@Model
final class RecoveryScoreRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var score: Double = 0
    var sleepFactor: Double = 0
    var hrFactor: Double = 0
    var loadFactor: Double = 0
    var hrvFactor: Double?
    var explanation: String = ""
    var suggestion: String?

    var scoreLabel: String {
        switch score {
        case 80...100: return "优秀"
        case 60..<80: return "良好"
        case 40..<60: return "一般"
        case 20..<40: return "偏低"
        default: return "不足"
        }
    }

    init(date: Date, score: Double, sleepFactor: Double = 0, hrFactor: Double = 0,
         loadFactor: Double = 0, hrvFactor: Double? = nil, explanation: String = "", suggestion: String? = nil) {
        self.date = date
        self.score = score
        self.sleepFactor = sleepFactor
        self.hrFactor = hrFactor
        self.loadFactor = loadFactor
        self.hrvFactor = hrvFactor
        self.explanation = explanation
        self.suggestion = suggestion
    }
}

// MARK: - Training Load

@Model
final class TrainingLoadRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var acuteLoad: Double = 0
    var chronicLoad: Double = 0
    var ratio: Double = 0
    var statusRaw: String = "Normal"

    var statusLabel: String {
        switch ratio {
        case 1.5...: return "偏高"
        case 1.2..<1.5: return "适中偏高"
        case 0.8..<1.2: return "正常"
        case 0.5..<0.8: return "偏低"
        default: return "明显偏低"
        }
    }

    init(date: Date, acuteLoad: Double = 0, chronicLoad: Double = 0) {
        self.date = date
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.ratio = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
    }
}

// MARK: - Health Insight

@Model
final class HealthInsight {
    var id: UUID = UUID()
    var title: String = ""
    var message: String = ""
    var severityRaw: String = InsightSeverity.info.rawValue
    var relatedMetrics: [String] = []
    var confidence: Double = 0
    var suggestedAction: String?
    var sourceRaw: String = "Local Rules"
    var createdAt: Date = Date()

    var severity: InsightSeverity {
        InsightSeverity(rawValue: severityRaw) ?? .info
    }

    init(title: String, message: String, severity: InsightSeverity, relatedMetrics: [String] = [],
         confidence: Double, suggestedAction: String? = nil, source: String = "Local Rules", createdAt: Date = Date()) {
        self.title = title
        self.message = message
        self.severityRaw = severity.rawValue
        self.relatedMetrics = relatedMetrics
        self.confidence = confidence
        self.suggestedAction = suggestedAction
        self.sourceRaw = source
        self.createdAt = createdAt
    }
}

// MARK: - Alert Record

@Model
final class AlertRecord {
    var id: UUID = UUID()
    var type: String = ""
    var title: String = ""
    var message: String = ""
    var date: Date = Date()
    var isRead: Bool = false
    var isDismissed: Bool = false
    var relatedInsightID: UUID?

    init(type: String, title: String, message: String, date: Date = Date(), relatedInsightID: UUID? = nil) {
        self.type = type
        self.title = title
        self.message = message
        self.date = date
        self.relatedInsightID = relatedInsightID
    }
}

// MARK: - AI Analysis Cache

@Model
final class AIAnalysisCache {
    var id: UUID = UUID()
    var promptHash: String = ""
    var response: String = ""
    var modelUsed: String = ""
    var contextDateRange: String = ""
    var createdAt: Date = Date()

    init(promptHash: String, response: String, modelUsed: String, contextDateRange: String = "") {
        self.promptHash = promptHash
        self.response = response
        self.modelUsed = modelUsed
        self.contextDateRange = contextDateRange
    }
}

// MARK: - Import Diagnostics Record

@Model
final class ImportDiagnostic {
    var id: UUID = UUID()
    var fileName: String = ""
    var importTime: Date = Date()
    var success: Bool = false
    var dateRangeStart: Date?
    var dateRangeEnd: Date?
    var parsedByTypeJSON: String = "{}"     // JSON-encoded [String: Int]
    var savedByTypeJSON: String = "{}"
    var skippedReasonsJSON: String = "{}"
    var totalMetricSamples: Int = 0
    var totalWorkouts: Int = 0
    var totalSleepSessions: Int = 0
    var totalDailySummaries: Int = 0
    var errorMessage: String?

    var parsedByType: [String: Int] {
        guard let data = parsedByTypeJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return dict
    }

    var savedByType: [String: Int] {
        guard let data = savedByTypeJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return dict
    }

    var skippedReasons: [String: Int] {
        guard let data = skippedReasonsJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return dict
    }

    init(fileName: String, importTime: Date, success: Bool, dateRangeStart: Date?, dateRangeEnd: Date?,
         parsedByType: [String: Int], savedByType: [String: Int], skippedReasons: [String: Int],
         totalMetricSamples: Int, totalWorkouts: Int, totalSleepSessions: Int, totalDailySummaries: Int,
         errorMessage: String?) {
        self.fileName = fileName
        self.importTime = importTime
        self.success = success
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.totalMetricSamples = totalMetricSamples
        self.totalWorkouts = totalWorkouts
        self.totalSleepSessions = totalSleepSessions
        self.totalDailySummaries = totalDailySummaries
        self.errorMessage = errorMessage

        let encoder = JSONEncoder()
        self.parsedByTypeJSON = (try? encoder.encode(parsedByType)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.savedByTypeJSON = (try? encoder.encode(savedByType)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.skippedReasonsJSON = (try? encoder.encode(skippedReasons)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

// MARK: - Chat Session Record

@Model
final class ChatSessionRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = "New Chat"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var dataSource: String = ""
    var providerMode: String = ""
    var modelName: String?
    var healthDataRangeStart: Date?
    var healthDataRangeEnd: Date?
    var isPinned: Bool = false
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageRecord.session)
    var messages: [ChatMessageRecord]? = []

    init(title: String = "New Chat", dataSource: String = "", providerMode: String = "",
         modelName: String? = nil, healthDataRangeStart: Date? = nil, healthDataRangeEnd: Date? = nil) {
        self.title = title
        self.dataSource = dataSource
        self.providerMode = providerMode
        self.modelName = modelName
        self.healthDataRangeStart = healthDataRangeStart
        self.healthDataRangeEnd = healthDataRangeEnd
    }
}

// MARK: - Chat Message Record

@Model
final class ChatMessageRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var role: String = "user" // "user", "assistant", "system"
    var contentMarkdown: String = ""
    var contentPlainText: String = ""
    var createdAt: Date = Date()
    var contextSummary: String?
    var evidenceData: String?
    var isFallback: Bool = false
    var providerMode: String?
    var modelName: String?
    var status: String = "completed"  // drafting / completed / truncated / failed
    var finishReason: String?          // stop / length / max_tokens / etc.
    var continuationCount: Int = 0
    var isPartial: Bool = false

    var session: ChatSessionRecord?

    init(role: String, contentMarkdown: String, contentPlainText: String = "",
         contextSummary: String? = nil, evidenceData: String? = nil,
         isFallback: Bool = false, providerMode: String? = nil, modelName: String? = nil,
         status: String = "completed", finishReason: String? = nil,
         continuationCount: Int = 0, isPartial: Bool = false) {
        self.role = role
        self.contentMarkdown = contentMarkdown
        self.contentPlainText = contentPlainText.isEmpty ? MarkdownSanitizer.plainText(from: contentMarkdown) : contentPlainText
        self.contextSummary = contextSummary
        self.evidenceData = evidenceData
        self.isFallback = isFallback
        self.providerMode = providerMode
        self.modelName = modelName
        self.status = status
        self.finishReason = finishReason
        self.continuationCount = continuationCount
        self.isPartial = isPartial
    }
}

// MARK: - Markdown Sanitizer

enum MarkdownSanitizer {
    /// Strip markdown to plain text for search/preview
    static func plainText(from markdown: String) -> String {
        var text = markdown
        // Remove headers
        text = text.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        // Remove bold/italic markers
        text = text.replacingOccurrences(of: #"\*{1,3}([^*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        // Remove inline code
        text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Remove links keeping text
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        // Collapse multiple newlines
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clean model output for better display
    static func displayMarkdown(from rawModelOutput: String) -> String {
        var text = rawModelOutput
        // Remove excessive horizontal rules
        text = text.replacingOccurrences(of: "\n---\n", with: "\n\n")
        // Collapse triple+ newlines
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        // Remove trailing whitespace lines
        text = text.replacingOccurrences(of: "(?m)^\\s+$", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
