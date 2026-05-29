import Foundation

struct RecoveryAnalyzer {
    /// Calculate recovery score (0-100) from multiple factors
    static func calculate(
        recentSleepHours: [Double],
        restingHeartRate: Double,
        restingHRHistory: [Double],
        trainingLoadRatio: Double,
        hrvValues: [Double]?
    ) -> RecoveryScoreComponents {
        var score = 50.0
        var explanations: [String] = []
        var sleepFactor = 0.0
        var hrFactor = 0.0
        var loadFactor = 0.0
        var hrvFactor: Double? = nil

        // Sleep factor (0-25 points)
        let avgSleep = recentSleepHours.reduce(0, +) / Double(max(recentSleepHours.count, 1))
        if avgSleep >= 8.0 {
            sleepFactor = 25
            score += 20
            explanations.append("睡眠时长充足 (\(String(format: "%.1f", avgSleep))小时)")
        } else if avgSleep >= 7.0 {
            sleepFactor = 20
            score += 12
            explanations.append("睡眠时长正常 (\(String(format: "%.1f", avgSleep))小时)")
        } else if avgSleep >= 6.0 {
            sleepFactor = 10
            score += 0
            explanations.append("睡眠时长偏短 (\(String(format: "%.1f", avgSleep))小时)")
        } else {
            sleepFactor = -5
            score -= 15
            explanations.append("睡眠严重不足 (\(String(format: "%.1f", avgSleep))小时)")
        }

        // HR factor (0-25 points)
        let avgHRHistory = restingHRHistory.reduce(0, +) / Double(max(restingHRHistory.count, 1))
        if avgHRHistory > 0 {
            let hrChange = (restingHeartRate - avgHRHistory) / avgHRHistory * 100
            if hrChange < -3 {
                hrFactor = 25
                score += 20
                explanations.append("静息心率下降 (\(String(format: "%.0f", abs(hrChange)))%)，恢复良好")
            } else if hrChange <= 3 {
                hrFactor = 20
                score += 10
                explanations.append("静息心率稳定")
            } else if hrChange <= 8 {
                hrFactor = 10
                score -= 5
                explanations.append("静息心率略高 (\(String(format: "%.0f", hrChange))%)")
            } else {
                hrFactor = -5
                score -= 15
                explanations.append("静息心率显著升高 (\(String(format: "%.0f", hrChange))%)，可能恢复不足")
            }
        } else {
            hrFactor = 15
            score += 5
        }

        // Training load factor (0-25 points)
        if trainingLoadRatio > 1.5 {
            loadFactor = -5
            score -= 15
            explanations.append("训练负荷偏高 (ACWR: \(String(format: "%.2f", trainingLoadRatio)))")
        } else if trainingLoadRatio > 1.2 {
            loadFactor = 5
            score -= 5
            explanations.append("训练负荷适中偏高 (ACWR: \(String(format: "%.2f", trainingLoadRatio)))")
        } else if trainingLoadRatio >= 0.8 {
            loadFactor = 20
            score += 15
            explanations.append("训练负荷适中 (ACWR: \(String(format: "%.2f", trainingLoadRatio)))")
        } else {
            loadFactor = 10
            score += 5
            explanations.append("训练负荷偏低 (ACWR: \(String(format: "%.2f", trainingLoadRatio)))")
        }

        // HRV factor (0-25 points), if available
        if let hrvs = hrvValues, !hrvs.isEmpty {
            let avgHRV = hrvs.reduce(0, +) / Double(hrvs.count)
            if avgHRV > 50 {
                hrvFactor = 25
                score += 15
                explanations.append("HRV 良好 (\(String(format: "%.0f", avgHRV))ms)")
            } else if avgHRV > 30 {
                hrvFactor = 15
                score += 5
                explanations.append("HRV 正常 (\(String(format: "%.0f", avgHRV))ms)")
            } else {
                hrvFactor = 5
                score -= 5
                explanations.append("HRV 偏低 (\(String(format: "%.0f", avgHRV))ms)")
            }
        }

        score = min(100, max(0, score))

        return RecoveryScoreComponents(
            score: score,
            sleepFactor: sleepFactor,
            hrFactor: hrFactor,
            loadFactor: loadFactor,
            hrvFactor: hrvFactor,
            explanation: explanations.joined(separator: "。"),
            suggestion: generateSuggestion(score: score, avgSleep: avgSleep)
        )
    }

    private static func generateSuggestion(score: Double, avgSleep: Double) -> String {
        if score >= 80 {
            return "你的恢复状态很好，可以继续正常训练和生活节奏。"
        } else if score >= 60 {
            return "恢复状态尚可。保持当前作息，注意睡眠质量。"
        } else if score >= 40 {
            let sleepTip = avgSleep < 7 ? "建议增加睡眠时间至7-8小时。" : ""
            return "恢复状态一般，建议适当降低训练强度。\(sleepTip)"
        } else {
            return "恢复状态不佳。建议减少训练量，优先保证睡眠和营养。这仅是行为分析，不是医疗建议。"
        }
    }
}

struct RecoveryScoreComponents {
    let score: Double
    let sleepFactor: Double
    let hrFactor: Double
    let loadFactor: Double
    let hrvFactor: Double?
    let explanation: String
    let suggestion: String
}
