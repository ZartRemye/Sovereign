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
}

enum WorkoutType: String, Codable, CaseIterable {
    case running = "Running"
    case walking = "Walking"
    case cycling = "Cycling"
    case strength = "Strength Training"
    case swimming = "Swimming"
    case yoga = "Yoga"
    case hiit = "HIIT"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "bicycle"
        case .strength: "dumbbell"
        case .swimming: "figure.pool.swim"
        case .yoga: "figure.mind.and.body"
        case .hiit: "figure.highintensity.intervaltraining"
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
    case mockLive = "Mock Live"
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
    var durationSeconds: Double = 0
    var distanceMeters: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKJ: Double?
    var trainingLoad: Double = 0
    var sourceRaw: String = DataSource.unknown.rawValue
    var notes: String?

    var workoutType: WorkoutType {
        WorkoutType(rawValue: workoutTypeRaw) ?? .other
    }

    var source: DataSource {
        DataSource(rawValue: sourceRaw) ?? .unknown
    }

    var durationFormatted: String {
        let hours = Int(durationSeconds) / 3600
        let minutes = (Int(durationSeconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var distanceFormatted: String? {
        guard let meters = distanceMeters else { return nil }
        return String(format: "%.2f km", meters / 1000)
    }

    init(workoutType: WorkoutType, startDate: Date, endDate: Date, durationSeconds: Double,
         distanceMeters: Double? = nil, avgHeartRate: Double? = nil, maxHeartRate: Double? = nil,
         activeEnergyKJ: Double? = nil, trainingLoad: Double = 0, source: DataSource = .unknown, notes: String? = nil) {
        self.workoutTypeRaw = workoutType.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKJ = activeEnergyKJ
        self.trainingLoad = trainingLoad
        self.sourceRaw = source.rawValue
        self.notes = notes
    }
}

// MARK: - Sleep Session

@Model
final class SleepSession {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    var durationSeconds: Double = 0
    var deepSleepSeconds: Double = 0
    var remSleepSeconds: Double = 0
    var coreSleepSeconds: Double = 0
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

    init(startDate: Date, endDate: Date, durationSeconds: Double, deepSleepSeconds: Double = 0,
         remSleepSeconds: Double = 0, coreSleepSeconds: Double = 0, qualityScore: Double = 0, source: DataSource = .unknown) {
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.deepSleepSeconds = deepSleepSeconds
        self.remSleepSeconds = remSleepSeconds
        self.coreSleepSeconds = coreSleepSeconds
        self.qualityScore = qualityScore
        self.sourceRaw = source.rawValue
    }
}

// MARK: - Daily Summary

@Model
final class DailySummary {
    var id: UUID = UUID()
    var date: Date = Date()
    var steps: Int = 0
    var restingHeartRate: Double = 0
    var heartRateVariability: Double?
    var sleepDurationSeconds: Double = 0
    var activeEnergyKJ: Double = 0
    var exerciseMinutes: Int = 0
    var recoveryScore: Double = 0
    var trainingLoad: Double = 0
    var healthStatusRaw: String = HealthStatus.insufficientData.rawValue
    var summaryText: String?

    var healthStatus: HealthStatus {
        HealthStatus(rawValue: healthStatusRaw) ?? .insufficientData
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    var sleepFormatted: String {
        let hours = Int(sleepDurationSeconds) / 3600
        let minutes = (Int(sleepDurationSeconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    init(date: Date, steps: Int = 0, restingHeartRate: Double = 0, heartRateVariability: Double? = nil,
         sleepDurationSeconds: Double = 0, activeEnergyKJ: Double = 0, exerciseMinutes: Int = 0,
         recoveryScore: Double = 0, trainingLoad: Double = 0, healthStatus: HealthStatus = .insufficientData) {
        self.date = date
        self.steps = steps
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.sleepDurationSeconds = sleepDurationSeconds
        self.activeEnergyKJ = activeEnergyKJ
        self.exerciseMinutes = exerciseMinutes
        self.recoveryScore = recoveryScore
        self.trainingLoad = trainingLoad
        self.healthStatusRaw = healthStatus.rawValue
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
