import Foundation

final class AISkillLoader {
    static func loadEliteHealthCoachSkill() -> String {
        // Try to load from bundle resource
        if let url = Bundle.main.url(forResource: "SovereignEliteHealthCoach", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // Fallback: load from source path (development)
        let fallbackPaths = [
            Bundle.main.bundlePath + "/../Sources/SovereignMac/CoreServices/AI/Skills/SovereignEliteHealthCoach.md",
        ]
        for path in fallbackPaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
        }
        // Final fallback: embedded
        return embeddedSkill
    }

    private static let embeddedSkill = """
# Sovereign Elite Health Coach Skill

## Identity
You are the AI health coach inside Sovereign. You are not a stand-alone chatbot. You are not DeepSeek. DeepSeek is only your language model backend when enabled.

## Mission
Build a longitudinal model of the user's health from Apple Health summaries. Explain current state, detect trends, forecast trajectories, and provide low-risk, actionable plans.

## Boundaries
Do NOT diagnose disease. Do NOT prescribe medication. Do NOT claim Apple Watch data is medical-grade. Do NOT invent data. Do NOT call yourself DeepSeek.

## Response Style
Specific, evidence-based, concise, practical, calm, high-trust. No generic wellness fluff.
"""
}

// MARK: - Trend Direction

enum TrendDirection: String, Codable {
    case improving, stable, declining, insufficient
}

// MARK: - Personal Health Model

struct PersonalHealthModel: Codable, Equatable {
    var dataRangeStart: Date?
    var dataRangeEnd: Date?
    var dataCompleteness: Double

    var baselineSteps: Double?
    var baselineSleepHours: Double?
    var baselineRestingHeartRate: Double?
    var baselineHRV: Double?
    var baselineTrainingLoad: Double?

    var currentRecoveryScore: Double?
    var currentTrainingLoad: Double?
    var acuteTrainingLoad7d: Double?
    var chronicTrainingLoad28d: Double?
    var acuteChronicRatio: Double?

    var sleepTrend: TrendDirection
    var activityTrend: TrendDirection
    var restingHeartRateTrend: TrendDirection
    var hrvTrend: TrendDirection
    var trainingLoadTrend: TrendDirection
    var recoveryTrend: TrendDirection

    var mainConstraints: [String]
    var mainOpportunities: [String]
    var dataLimitations: [String]

    var summary: String {
        var parts: [String] = []
        if let s = dataRangeStart, let e = dataRangeEnd {
            parts.append("Data: \(s.formatted(date: .numeric, time: .omitted)) – \(e.formatted(date: .numeric, time: .omitted))")
        }
        parts.append("Completeness: \(String(format: "%.0f", dataCompleteness * 100))%")
        if let steps = baselineSteps { parts.append("Avg Steps: \(String(format: "%.0f", steps))/day") }
        if let sleep = baselineSleepHours { parts.append("Avg Sleep: \(String(format: "%.1f", sleep))h") }
        if let hr = baselineRestingHeartRate { parts.append("Avg RHR: \(String(format: "%.0f", hr)) bpm") }
        if let hrv = baselineHRV { parts.append("Avg HRV: \(String(format: "%.0f", hrv)) ms") }
        if let acr = acuteChronicRatio { parts.append("ACWR: \(String(format: "%.2f", acr))") }
        parts.append("Sleep: \(sleepTrend.rawValue) | Activity: \(activityTrend.rawValue) | RHR: \(restingHeartRateTrend.rawValue) | Recovery: \(recoveryTrend.rawValue)")
        if !mainConstraints.isEmpty { parts.append("Constraints: \(mainConstraints.joined(separator: "; "))") }
        if !dataLimitations.isEmpty { parts.append("Limitations: \(dataLimitations.joined(separator: "; "))") }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Personal Health Model Builder

final class PersonalHealthModelBuilder {
    func build(
        summaries: [DailySummary],
        workouts: [WorkoutSession],
        sleep: [SleepSession]
    ) -> PersonalHealthModel {
        let sorted = summaries.sorted { $0.date < $1.date }
        let allWorkouts = workouts.sorted { $0.startDate < $1.startDate }
        let recent7 = Array(sorted.suffix(7))
        let recent28 = Array(sorted.suffix(28))
        let older28 = sorted.count > 56 ? Array(sorted.suffix(56).prefix(28)) : Array(sorted.prefix(max(sorted.count - 28, 0)))

        let dates = sorted.map(\.date)
        let dataRangeStart = dates.min()
        let dataRangeEnd = dates.max()

        // Completeness
        let complete = sorted.filter { $0.dataCompleteness > 0.5 }
        let dataCompleteness = sorted.isEmpty ? 0 : Double(complete.count) / Double(sorted.count)

        // Baselines from recent 28 days (filter zeros)
        let baselineSteps = mean(recent28.map(\.steps).map(Double.init).filter { $0 > 0 })
        let baselineSleep = mean(recent28.map(\.sleepHours).filter { $0 > 0 })
        let baselineRHR = mean(recent28.map(\.restingHeartRate).filter { $0 > 0 })
        let baselineHRV = mean(recent28.compactMap(\.heartRateVariability).filter { $0 > 0 })
        let baselineLoad = mean(recent28.map(\.trainingLoad).filter { $0 > 0 })

        // Current
        let currentRecovery = recent7.map(\.recoveryScore).reduce(0, +) / max(Double(recent7.count), 1)
        let currentLoad = recent7.map(\.trainingLoad).reduce(0, +) / 7

        // Acute/Chronic
        let acuteLoads = recent7.map(\.trainingLoad)
        let chronicLoads = recent28.map(\.trainingLoad)
        let acute = acuteLoads.reduce(0, +) / max(Double(acuteLoads.count), 1)
        let chronic = chronicLoads.reduce(0, +) / max(Double(chronicLoads.count), 1)
        let acwr = chronic > 0 ? acute / chronic : 1.0

        // Trends
        let sleepTrend = trendDirection(recent: recent7.map(\.sleepHours), older: older28.map(\.sleepHours), threshold: 0.1)
        let activityTrend = trendDirection(recent: recent7.map(\.steps).map(Double.init), older: older28.map(\.steps).map(Double.init), threshold: 0.1)
        let rhrTrend = trendDirection(recent: recent7.map(\.restingHeartRate), older: older28.map(\.restingHeartRate), threshold: 0.05)
        let hrvTrend = trendDirection(recent: recent7.compactMap(\.heartRateVariability), older: older28.compactMap(\.heartRateVariability), threshold: 0.1)
        let loadTrend = trendDirection(recent: recent7.map(\.trainingLoad), older: older28.map(\.trainingLoad), threshold: 0.15)
        let recTrend = trendDirection(recent: recent7.map(\.recoveryScore), older: older28.map(\.recoveryScore), threshold: 0.1)

        // Constraints & opportunities
        var constraints: [String] = []
        var opportunities: [String] = []
        var limitations: [String] = []

        if let sleep = baselineSleep, sleep < 7 { constraints.append("Sleep below 7h avg") }
        if acwr > 1.3 { constraints.append("Training load elevated (ACWR \(String(format: "%.2f", acwr)))") }
        if rhrTrend == .declining { constraints.append("Resting HR rising") }
        if sleepTrend == .declining { constraints.append("Sleep declining") }

        if let sleep = baselineSleep, sleep >= 7.5 { opportunities.append("Sleep duration adequate") }
        if acwr >= 0.8 && acwr <= 1.2 { opportunities.append("Training load balanced") }
        if recTrend == .improving || recTrend == .stable { opportunities.append("Recovery stable") }

        if sorted.count < 14 { limitations.append("Less than 14 days of data") }
        if baselineHRV == nil { limitations.append("No HRV data") }
        if recent7.allSatisfy({ $0.steps == 0 }) { limitations.append("No step data") }

        return PersonalHealthModel(
            dataRangeStart: dataRangeStart,
            dataRangeEnd: dataRangeEnd,
            dataCompleteness: dataCompleteness,
            baselineSteps: baselineSteps,
            baselineSleepHours: baselineSleep,
            baselineRestingHeartRate: baselineRHR,
            baselineHRV: baselineHRV,
            baselineTrainingLoad: baselineLoad,
            currentRecoveryScore: currentRecovery,
            currentTrainingLoad: currentLoad,
            acuteTrainingLoad7d: acute,
            chronicTrainingLoad28d: chronic,
            acuteChronicRatio: acwr,
            sleepTrend: sleepTrend,
            activityTrend: activityTrend,
            restingHeartRateTrend: rhrTrend,
            hrvTrend: hrvTrend,
            trainingLoadTrend: loadTrend,
            recoveryTrend: recTrend,
            mainConstraints: constraints,
            mainOpportunities: opportunities,
            dataLimitations: limitations
        )
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func trendDirection(recent: [Double], older: [Double], threshold: Double) -> TrendDirection {
        guard !recent.isEmpty, !older.isEmpty else { return .insufficient }
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        guard olderAvg > 0 else { return .insufficient }
        let change = (recentAvg - olderAvg) / olderAvg
        if change > threshold { return .improving }
        if change < -threshold { return .declining }
        return .stable
    }
}

// MARK: - Health Forecast

struct HealthForecast: Codable, Equatable {
    var horizonDays: Int
    var recoveryForecast: String
    var trainingRiskForecast: String
    var sleepRiskForecast: String
    var confidence: String
    var assumptions: [String]
}

final class ForecastEngine {
    func forecast(from model: PersonalHealthModel, horizonDays: Int = 7) -> HealthForecast {
        var assumptions: [String] = []

        // Recovery forecast
        let recoveryFc: String
        if model.recoveryTrend == .declining && model.sleepTrend == .declining {
            recoveryFc = "Recovery may continue to decline over the next \(horizonDays) days if sleep and training load don't improve."
            assumptions.append("Sleep and recovery both declining")
        } else if model.recoveryTrend == .improving {
            recoveryFc = "Recovery is trending up. If current patterns hold, scores should stay above 60."
        } else if let acwr = model.acuteChronicRatio, acwr > 1.3 {
            recoveryFc = "ACWR is elevated (\(String(format: "%.2f", acwr))). Recovery may drop if training load isn't reduced."
            assumptions.append("Elevated ACWR")
        } else {
            recoveryFc = "Recovery is expected to remain stable over the next \(horizonDays) days."
        }

        // Training risk
        let trainingRisk: String
        if let acwr = model.acuteChronicRatio {
            if acwr > 1.5 {
                trainingRisk = "HIGH — ACWR \(String(format: "%.2f", acwr)). Strongly recommend reducing training volume this week."
            } else if acwr > 1.2 {
                trainingRisk = "MODERATE — ACWR \(String(format: "%.2f", acwr)). Recommend capping intensity and monitoring recovery."
            } else {
                trainingRisk = "LOW — ACWR in optimal range. Can maintain or slightly increase volume."
            }
        } else {
            trainingRisk = "UNKNOWN — insufficient load history."
        }

        // Sleep risk
        let sleepRisk: String
        if let sleep = model.baselineSleepHours {
            if sleep < 6.5 && model.sleepTrend == .declining {
                sleepRisk = "ELEVATED — Sleep is low (\(String(format: "%.1f", sleep))h) and declining. Recovery capacity is compromised."
            } else if sleep < 7 {
                sleepRisk = "MODERATE — Sleep is below recommended 7h. Consider prioritizing sleep this week."
            } else {
                sleepRisk = "LOW — Sleep duration is adequate."
            }
        } else {
            sleepRisk = "UNKNOWN — no sleep data available."
        }

        return HealthForecast(
            horizonDays: horizonDays,
            recoveryForecast: recoveryFc,
            trainingRiskForecast: trainingRisk,
            sleepRiskForecast: sleepRisk,
            confidence: model.dataCompleteness > 0.6 ? "Moderate" : "Low (limited data)",
            assumptions: assumptions
        )
    }
}

// MARK: - Readiness & Exercise Prescription

enum ReadinessLevel: String, Codable {
    case ready, limited, restDay, insufficientData
}

struct ExercisePrescription: Codable, Equatable {
    var readiness: ReadinessLevel
    var recommendedTrainingType: String
    var durationRangeMinutes: ClosedRange<Int>?
    var intensity: String
    var targetHeartRateZone: String?
    var warmup: String
    var mainSession: String
    var cooldown: String
    var stopConditions: [String]
    var recoveryActions: [String]
    var rationale: [String]
}

final class ExercisePrescriptionEngine {
    func prescribe(from model: PersonalHealthModel) -> ExercisePrescription {
        let readiness = computeReadiness(model)
        let intensity: String
        let recType: String
        let duration: ClosedRange<Int>?
        let hrZone: String?

        switch readiness {
        case .ready:
            intensity = "Moderate to High"
            recType = "Normal training session"
            duration = 45...75
            hrZone = "Zone 2-3 (60-80% max HR)"
        case .limited:
            intensity = "Low to Moderate"
            recType = "Light aerobic or mobility work"
            duration = 20...40
            hrZone = "Zone 1-2 (50-65% max HR)"
        case .restDay:
            intensity = "Very Low"
            recType = "Active recovery only"
            duration = 15...30
            hrZone = "Zone 1 (<60% max HR)"
        case .insufficientData:
            intensity = "Conservative"
            recType = "Light activity"
            duration = 20...45
            hrZone = "Zone 1-2"
        }

        var rationale: [String] = []
        if let score = model.currentRecoveryScore {
            rationale.append("Recovery score: \(String(format: "%.0f", score))/100")
        }
        if let acwr = model.acuteChronicRatio {
            rationale.append("ACWR: \(String(format: "%.2f", acwr))")
        }
        if model.sleepTrend == .declining { rationale.append("Sleep is declining") }
        if model.restingHeartRateTrend == .declining { rationale.append("Resting HR is rising") }

        return ExercisePrescription(
            readiness: readiness,
            recommendedTrainingType: recType,
            durationRangeMinutes: duration,
            intensity: intensity,
            targetHeartRateZone: hrZone,
            warmup: "10 min light walking + dynamic mobility",
            mainSession: "\(recType) at \(intensity) intensity, \(duration.map { "\($0.lowerBound)-\($0.upperBound) min" } ?? "30 min")",
            cooldown: "5-10 min light stretching",
            stopConditions: [
                "Chest pain or pressure",
                "Unusual shortness of breath",
                "Dizziness or lightheadedness",
                "Heart rate stays abnormally high after stopping",
                "Sharp or worsening joint/muscle pain",
            ],
            recoveryActions: [
                "Hydrate adequately before and after",
                "Prioritize 7-8h sleep tonight",
                "Light walking or stretching if sore",
            ],
            rationale: rationale
        )
    }

    private func computeReadiness(_ model: PersonalHealthModel) -> ReadinessLevel {
        guard model.dataCompleteness > 0.2 else { return .insufficientData }

        var flags = 0
        if let score = model.currentRecoveryScore, score < 40 { flags += 2 }
        if let sleep = model.baselineSleepHours, sleep < 6 { flags += 1 }
        if model.sleepTrend == .declining { flags += 1 }
        if let acwr = model.acuteChronicRatio, acwr > 1.5 { flags += 2 }
        else if let acwr = model.acuteChronicRatio, acwr > 1.2 { flags += 1 }
        if model.restingHeartRateTrend == .declining { flags += 1 }

        if flags >= 4 { return .restDay }
        if flags >= 2 { return .limited }
        if flags == 0 { return .ready }
        return .limited
    }
}
