import Foundation

// MARK: - Readiness Assessment

struct ReadinessContributor: Codable, Equatable {
    var name: String
    var score: Double  // 0-1
    var label: String
    var impactPositive: Bool
}

struct ReadinessAssessment: Codable, Equatable {
    var score: Double
    var label: String
    var primaryReason: String
    var contributors: [ReadinessContributor]
    var recommendedAction: String

    static func assess(summaries: [DailySummary], workouts: [WorkoutSession], sleep: [SleepSession]) -> ReadinessAssessment {
        let recent7 = Array(summaries.sorted { $0.date < $1.date }.suffix(7))
        let today = recent7.last
        let avgRecovery = recent7.map(\.recoveryScore).reduce(0, +) / max(Double(recent7.count), 1)
        let avgSleep = recent7.map(\.sleepHours).reduce(0, +) / max(Double(recent7.count), 1)
        let avgRHR = recent7.map(\.restingHeartRate).filter { $0 > 0 }.reduce(0, +) / max(Double(recent7.filter { $0.restingHeartRate > 0 }.count), 1)

        var contributors: [ReadinessContributor] = []
        var score = 50.0

        // Sleep factor (30 pts)
        let sleepScore = min(avgSleep / 8.0, 1.0) * 30
        score += sleepScore - 15
        contributors.append(ReadinessContributor(name: "睡眠时长", score: min(avgSleep / 8.0, 1.0), label: String(format: "%.1fh", avgSleep), impactPositive: avgSleep >= 7))

        // Recovery factor (25 pts)
        let recScore = (today?.recoveryScore ?? avgRecovery) / 100 * 25
        score += recScore - 12.5
        contributors.append(ReadinessContributor(name: "恢复评分", score: (today?.recoveryScore ?? avgRecovery) / 100, label: "\(Int(today?.recoveryScore ?? avgRecovery))/100", impactPositive: (today?.recoveryScore ?? 0) >= 60))

        // RHR factor (20 pts)
        if avgRHR > 0 {
            let rhrScore = min(max(1 - (avgRHR - 55) / 30, 0), 1) * 20
            score += rhrScore - 10
            contributors.append(ReadinessContributor(name: "静息心率", score: min(max(1 - (avgRHR - 55) / 30, 0), 1), label: "\(Int(avgRHR)) bpm", impactPositive: avgRHR < 65))
        }

        // Training load factor (25 pts)
        let acuteLoad = recent7.map(\.trainingLoad).reduce(0, +) / 7
        let allLoads = summaries.map(\.trainingLoad)
        let chronicLoad = allLoads.reduce(0, +) / max(Double(allLoads.count), 1)
        let acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
        let loadScore: Double = acwr <= 1.2 ? 25 : acwr <= 1.5 ? 10 : -10
        score += loadScore
        contributors.append(ReadinessContributor(name: "训练负荷", score: acwr <= 1.2 ? 0.8 : acwr <= 1.5 ? 0.5 : 0.2, label: "ACWR \(String(format: "%.2f", acwr))", impactPositive: acwr <= 1.2))

        score = min(100, max(0, score))

        let label: String
        let action: String
        let reason: String

        if score >= 75 {
            label = "准备充分"
            action = "可以进行正常训练，强度可适当提高"
            reason = "睡眠、恢复、心率等指标均在良好范围"
        } else if score >= 55 {
            label = "轻度受限"
            action = "建议中等强度训练，注意恢复"
            reason = contributors.filter { !$0.impactPositive }.prefix(2).map(\.name).joined(separator: "、") + " 需要关注"
        } else if score >= 35 {
            label = "建议减量"
            action = "建议低强度活动或主动恢复日"
            reason = contributors.filter { !$0.impactPositive }.prefix(2).map(\.name).joined(separator: "、") + " 明显受限"
        } else {
            label = "建议休息"
            action = "优先休息和睡眠，避免结构化训练"
            reason = "多项指标显示恢复不足"
        }

        return ReadinessAssessment(score: score, label: label, primaryReason: reason, contributors: contributors, recommendedAction: action)
    }
}

// MARK: - Sleep Debt

struct SleepDebtRecord: Codable, Equatable {
    var date: Date
    var targetSleepHours: Double
    var actualSleepHours: Double
    var debtHours: Double
    var rollingDebt7d: Double

    static func compute(summaries: [DailySummary], targetHours: Double = 8.0) -> [SleepDebtRecord] {
        let sorted = summaries.sorted { $0.date < $1.date }
        var records: [SleepDebtRecord] = []
        var rollingWindow: [Double] = []
        for s in sorted {
            let debt = max(0, targetHours - s.sleepHours)
            rollingWindow.append(debt)
            if rollingWindow.count > 7 { rollingWindow.removeFirst() }
            let rolling = rollingWindow.reduce(0, +)
            records.append(SleepDebtRecord(date: s.date, targetSleepHours: targetHours, actualSleepHours: s.sleepHours, debtHours: debt, rollingDebt7d: rolling))
        }
        return records
    }

    static func currentDebt(from records: [SleepDebtRecord]) -> Double {
        records.last?.rollingDebt7d ?? 0
    }
}

// MARK: - Training Load Model

struct TrainingLoadModelData: Codable, Equatable {
    var acuteLoad7d: Double
    var chronicLoad28d: Double
    var acuteChronicRatio: Double
    var riskLabel: String
    var explanation: String

    static func compute(summaries: [DailySummary]) -> TrainingLoadModelData {
        let sorted = summaries.sorted { $0.date < $1.date }
        let recent7 = Array(sorted.suffix(7))
        let recent28 = Array(sorted.suffix(28))
        let acute = recent7.map(\.trainingLoad).reduce(0, +) / 7
        let chronic = recent28.map(\.trainingLoad).reduce(0, +) / max(Double(recent28.count), 1)
        let acwr = chronic > 0 ? acute / chronic : 1.0
        let risk: String
        let explanation: String
        if acwr > 1.5 {
            risk = "高风险"; explanation = "急慢性负荷比显著偏高，受伤风险上升。建议减少训练量。"
        } else if acwr > 1.2 {
            risk = "中等风险"; explanation = "训练负荷在上升趋势。建议监控恢复，控制强度。"
        } else if acwr >= 0.8 {
            risk = "最佳区间"; explanation = "急慢性负荷比在安全范围，可维持或逐步增加训练量。"
        } else {
            risk = "偏低"; explanation = "训练负荷低于维持水平，可逐步增加。"
        }
        return TrainingLoadModelData(acuteLoad7d: acute, chronicLoad28d: chronic, acuteChronicRatio: acwr, riskLabel: risk, explanation: explanation)
    }
}

// MARK: - Data Quality Score

struct DataQualityScore: Codable, Equatable {
    var score: Double
    var missingMetrics: [String]
    var reliabilityLabel: String
    var explanation: String

    static func assess(summaries: [DailySummary], workouts: [WorkoutSession], sleep: [SleepSession]) -> DataQualityScore {
        var missing: [String] = []
        let recent = Array(summaries.suffix(30))
        if recent.allSatisfy({ $0.steps == 0 }) { missing.append("步数") }
        if recent.allSatisfy({ $0.sleepHours == 0 }) { missing.append("睡眠") }
        if recent.allSatisfy({ $0.restingHeartRate == 0 }) { missing.append("静息心率") }
        if recent.allSatisfy({ $0.heartRateVariability == nil }) { missing.append("HRV") }
        if workouts.isEmpty { missing.append("运动记录") }

        let score = max(0, 1.0 - Double(missing.count) * 0.2)
        let label = score > 0.8 ? "良好" : score > 0.5 ? "中等" : "偏低"
        return DataQualityScore(score: score, missingMetrics: missing, reliabilityLabel: label, explanation: "缺失: \(missing.joined(separator: "、"))")
    }
}

// MARK: - Weekly Plan

struct WeeklyPlanDay: Codable, Equatable {
    var date: Date
    var focus: String
    var trainingType: String
    var durationMinutes: Int?
    var intensity: String
    var rationale: String
    var stopConditions: [String]
}

enum WeeklyPlanGenerator {
    static func generate(readiness: ReadinessAssessment, healthModel: PersonalHealthModel) -> [WeeklyPlanDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var plan: [WeeklyPlanDay] = []

        let types = ["主动恢复", "低强度有氧", "中等强度训练", "力量训练", "休息日", "灵活活动", "户外活动"]
        let stopCond = ["胸痛或压迫感", "异常气短", "头晕", "心率异常持续升高", "关节/肌肉剧痛"]

        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: i, to: today) else { continue }
            let isRestDay = i == 0 && readiness.score < 45 || i == 3 || i == 6
            let idx = min(i, types.count - 1)
            let type = isRestDay ? "休息日" : (i == 0 ? (readiness.score >= 60 ? "中等强度训练" : "低强度有氧") : types[idx])

            plan.append(WeeklyPlanDay(
                date: date, focus: isRestDay ? "恢复" : "训练",
                trainingType: type,
                durationMinutes: isRestDay ? nil : (readiness.score >= 60 ? 40 : 25),
                intensity: readiness.score >= 75 ? "中-高" : readiness.score >= 55 ? "低-中" : "低",
                rationale: isRestDay ? "主动恢复日，促进身体修复" : "基于当前准备度和负荷状态",
                stopConditions: stopCond
            ))
        }
        return plan
    }
}
