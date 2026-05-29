import Foundation

actor LocalRuleAIService {
    static let shared = LocalRuleAIService()

    private let safetyGuard = HealthSafetyGuard()
    private var generatedInsights: [HealthInsight] = []

    private init() {}

    // MARK: - Main Entry Point

    func analyze(question: String, summaries: [DailySummary], workouts: [WorkoutSession],
                 sleepSessions: [SleepSession]) -> AsyncStream<ChatMessage> {
        AsyncStream { continuation in
            Task {
                // Step 1: Safety check
                let safetyResult = safetyGuard.check(question)
                if !safetyResult.isSafe, let warning = safetyResult.warningMessage {
                    continuation.yield(ChatMessage(
                        role: .assistant,
                        content: warning,
                        contextSummary: "安全拦截: \(safetyResult.category?.rawValue ?? "unknown")",
                        isFallback: true
                    ))
                    continuation.finish()
                    return
                }

                // Step 2: Generate local insights
                let insights = generateLocalInsights(summaries: summaries, workouts: workouts, sleepSessions: sleepSessions)
                generatedInsights = insights

                // Step 3: Build response based on question type
                let response = buildLocalResponse(question: question, summaries: summaries,
                                                   workouts: workouts, sleepSessions: sleepSessions, insights: insights)

                continuation.yield(ChatMessage(
                    role: .assistant,
                    content: response,
                    contextSummary: "基于本地规则分析",
                    isFallback: false
                ))
                continuation.finish()
            }
        }
    }

    // MARK: - Local Rules

    func generateLocalInsights(summaries: [DailySummary], workouts: [WorkoutSession],
                                sleepSessions: [SleepSession]) -> [HealthInsight] {
        var insights: [HealthInsight] = []
        let sorted = summaries.sorted { $0.date < $1.date }

        // Rule 1: Sleep deprivation
        if let sleepInsight = checkSleepDeprivation(summaries: sorted, sleepSessions: sleepSessions) {
            insights.append(sleepInsight)
        }

        // Rule 2: Elevated resting HR
        if let hrInsight = checkElevatedHR(summaries: sorted) {
            insights.append(hrInsight)
        }

        // Rule 3: Training load spike
        if let loadInsight = checkTrainingLoadSpike(summaries: sorted, workouts: workouts) {
            insights.append(loadInsight)
        }

        // Rule 4: Activity insufficiency
        if let activityInsight = checkActivityInsufficiency(summaries: sorted) {
            insights.append(activityInsight)
        }

        // Rule 5: Recovery insufficiency (combined)
        if let recoveryInsight = checkRecoveryInsufficiency(summaries: sorted) {
            insights.append(recoveryInsight)
        }

        // Rule 6: Good recovery
        if insights.isEmpty {
            if let goodInsight = checkGoodRecovery(summaries: sorted) {
                insights.append(goodInsight)
            }
        }

        // Rule 7: Data insufficiency
        if summaries.count < 7 {
            insights.append(HealthInsight(
                title: "数据不足",
                message: "可用数据少于7天 (\(summaries.count)天)，所有分析结论可能不可靠。建议导入更多健康数据。",
                severity: .warning,
                relatedMetrics: ["data_quality"],
                confidence: 1.0,
                suggestedAction: "导入 Apple Health 数据或等待更多数据积累。"
            ))
        }

        return insights
    }

    // MARK: - Rule Implementations

    private func checkSleepDeprivation(summaries: [DailySummary], sleepSessions: [SleepSession]) -> HealthInsight? {
        let recent = summaries.suffix(3)
        guard recent.count >= 3 else { return nil }

        let avgSleep = recent.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / Double(recent.count)

        if avgSleep < 6.5 {
            return HealthInsight(
                title: "睡眠不足",
                message: "最近3天平均睡眠仅 \(String(format: "%.1f", avgSleep)) 小时，低于推荐的7-8小时。",
                severity: .warning,
                relatedMetrics: ["sleep_duration"],
                confidence: 0.85,
                suggestedAction: "建议未来几天优先保证7-8小时睡眠，避免熬夜。"
            )
        }
        return nil
    }

    private func checkElevatedHR(summaries: [DailySummary]) -> HealthInsight? {
        guard summaries.count >= 14 else { return nil }

        let sortedByDate = summaries.sorted { $0.date < $1.date }
        let recent14 = sortedByDate.suffix(14)
        let avgHR = recent14.map(\.restingHeartRate).reduce(0, +) / Double(recent14.count)

        guard let today = sortedByDate.last, today.restingHeartRate > 0, avgHR > 0 else { return nil }

        let change = (today.restingHeartRate - avgHR) / avgHR * 100
        if change > 8 {
            return HealthInsight(
                title: "静息心率升高",
                message: "今日静息心率 \(String(format: "%.0f", today.restingHeartRate)) bpm，高于近14天均值 \(String(format: "%.0f", avgHR)) bpm (\(String(format: "%.0f", change))%)。",
                severity: .warning,
                relatedMetrics: ["resting_heart_rate"],
                confidence: 0.7,
                suggestedAction: "静息心率升高可能与疲劳、压力或水分摄入不足有关。建议关注休息质量和水分补充。"
            )
        }
        return nil
    }

    private func checkTrainingLoadSpike(summaries: [DailySummary], workouts: [WorkoutSession]) -> HealthInsight? {
        let sorted = summaries.sorted { $0.date < $1.date }
        guard sorted.count >= 14 else { return nil }

        let recent7 = sorted.suffix(7).map(\.trainingLoad).reduce(0, +)
        let prior7 = sorted.suffix(14).prefix(7).map(\.trainingLoad).reduce(0, +)

        guard prior7 > 0 else { return nil }

        let change = (recent7 - prior7) / prior7 * 100
        if change > 30 {
            return HealthInsight(
                title: "训练负荷突增",
                message: "最近7天训练量较前7天增加 \(String(format: "%.0f", change))%，建议注意恢复。",
                severity: .warning,
                relatedMetrics: ["training_load"],
                confidence: 0.8,
                suggestedAction: "建议本周适当降低训练强度，确保充分恢复后再增加训练量。"
            )
        }
        return nil
    }

    private func checkActivityInsufficiency(summaries: [DailySummary]) -> HealthInsight? {
        let recent = summaries.suffix(3)
        guard recent.count >= 3 else { return nil }

        let globalAvg = summaries.map(\.steps).reduce(0, +) / max(summaries.count, 1)
        let recentAvg = recent.map(\.steps).reduce(0, +) / recent.count

        if globalAvg > 0 && Double(recentAvg) < Double(globalAvg) * 0.5 {
            return HealthInsight(
                title: "活动不足",
                message: "最近3天步数显著低于个人平均水平。",
                severity: .info,
                relatedMetrics: ["step_count"],
                confidence: 0.6,
                suggestedAction: "试着每天增加一些步行时间，即使是短距离散步也有益处。"
            )
        }
        return nil
    }

    private func checkRecoveryInsufficiency(summaries: [DailySummary]) -> HealthInsight? {
        let recent = summaries.suffix(7)
        guard recent.count >= 3 else { return nil }

        let avgSleep = recent.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / Double(recent.count)
        let avgRecovery = recent.map(\.recoveryScore).reduce(0, +) / Double(recent.count)
        let avgLoad = recent.map(\.trainingLoad).reduce(0, +) / Double(recent.count)

        if avgSleep < 7 && avgRecovery < 60 && avgLoad > 50 {
            return HealthInsight(
                title: "运动恢复不足",
                message: "综合判断：睡眠不足 + 恢复评分偏低 + 训练负荷偏高。恢复状态需要关注。",
                severity: .warning,
                relatedMetrics: ["sleep_duration", "recovery_score", "training_load"],
                confidence: 0.75,
                suggestedAction: "建议：1) 降低训练强度 2) 保证每天7-8小时睡眠 3) 关注营养补充。这仅是行为分析，不是医疗建议。"
            )
        }
        return nil
    }

    private func checkGoodRecovery(summaries: [DailySummary]) -> HealthInsight? {
        let recent = summaries.suffix(7)
        guard recent.count >= 7 else { return nil }

        let avgSleep = recent.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / Double(recent.count)
        let avgRecovery = recent.map(\.recoveryScore).reduce(0, +) / Double(recent.count)
        let avgLoad = recent.map(\.trainingLoad).reduce(0, +) / Double(recent.count)

        if avgSleep >= 7 && avgRecovery >= 70 && avgLoad < 100 {
            return HealthInsight(
                title: "恢复良好",
                message: "睡眠充足、静息心率稳定、训练负荷适中。当前整体恢复状态良好。",
                severity: .positive,
                relatedMetrics: ["sleep_duration", "recovery_score", "training_load"],
                confidence: 0.8,
                suggestedAction: "可以保持当前训练和生活节奏。"
            )
        }
        return nil
    }

    // MARK: - Response Builder

    private func buildLocalResponse(question: String, summaries: [DailySummary],
                                     workouts: [WorkoutSession], sleepSessions: [SleepSession],
                                     insights: [HealthInsight]) -> String {
        let q = question.lowercased()

        if q.contains("适合训练") || q.contains("可以训练") {
            return buildTrainingReadinessResponse(insights: insights, summaries: summaries)
        } else if q.contains("恢复") {
            return buildRecoveryResponse(insights: insights, summaries: summaries)
        } else if q.contains("累") || q.contains("疲劳") {
            return buildFatigueResponse(insights: insights, summaries: summaries)
        } else if q.contains("睡眠") {
            return buildSleepResponse(insights: insights, sleepSessions: sleepSessions, summaries: summaries)
        } else if q.contains("训练负荷") || q.contains("训练量") {
            return buildLoadResponse(insights: insights, summaries: summaries)
        } else if q.contains("总结") || q.contains("摘要") {
            return buildSummaryResponse(insights: insights, summaries: summaries, workouts: workouts)
        } else if q.contains("训练建议") || q.contains("建议") {
            return buildSuggestionResponse(insights: insights, summaries: summaries)
        }

        // Default response
        return buildDefaultResponse(insights: insights, summaries: summaries)
    }

    private func buildTrainingReadinessResponse(insights: [HealthInsight], summaries: [DailySummary]) -> String {
        let recoveryScores = summaries.suffix(7).map(\.recoveryScore)
        let avgRecovery = recoveryScores.reduce(0, +) / max(Double(recoveryScores.count), 1)

        if avgRecovery >= 70 {
            return "根据最近7天数据，你的恢复评分平均为 \(String(format: "%.0f", avgRecovery))/100，恢复状态良好，可以进行正常训练。建议关注训练中的身体反馈。"
        } else if avgRecovery >= 50 {
            return "你的恢复评分 \(String(format: "%.0f", avgRecovery))/100，处于中等水平。可以进行轻度到中度的训练，但建议避免高强度训练。注意训练后的恢复。"
        } else {
            return "你的恢复评分偏低 (\(String(format: "%.0f", avgRecovery))/100)，建议今天是主动恢复日。可以进行轻度活动如散步、拉伸，但不建议高强度训练。这仅是行为分析，不是医疗建议。"
        }
    }

    private func buildRecoveryResponse(insights: [HealthInsight], summaries: [DailySummary]) -> String {
        let sorted = summaries.sorted { $0.date < $1.date }
        let recent = sorted.suffix(7)
        let avgScore = recent.map(\.recoveryScore).reduce(0, +) / max(Double(recent.count), 1)
        let avgSleep = recent.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / max(Double(recent.count), 1)

        var response = "最近7天恢复状态分析：\n"
        response += "- 平均恢复评分: \(String(format: "%.0f", avgScore))/100\n"
        response += "- 平均睡眠: \(String(format: "%.1f", avgSleep)) 小时\n"

        let relevantInsights = insights.filter { $0.relatedMetrics.contains("recovery_score") || $0.relatedMetrics.contains("sleep_duration") }
        for insight in relevantInsights {
            response += "- \(insight.title): \(insight.message)\n"
        }

        let recoveryInsight = insights.first { $0.title.contains("恢复良好") || $0.title.contains("恢复不足") }
        if let ri = recoveryInsight {
            response += "\n\(ri.suggestedAction ?? "")"
        }

        return response
    }

    private func buildFatigueResponse(insights: [HealthInsight], summaries: [DailySummary]) -> String {
        let sleepInsight = insights.first { $0.relatedMetrics.contains("sleep_duration") }
        let hrInsight = insights.first { $0.relatedMetrics.contains("resting_heart_rate") }
        let loadInsight = insights.first { $0.relatedMetrics.contains("training_load") }

        if sleepInsight != nil || hrInsight != nil || loadInsight != nil {
            var response = "根据最近健康数据，你感到累可能与以下因素有关：\n"
            if let si = sleepInsight {
                response += "- 睡眠: \(si.message)\n"
            }
            if let hi = hrInsight {
                response += "- 心率: \(hi.message)\n"
            }
            if let li = loadInsight {
                response += "- 训练: \(li.message)\n"
            }
            response += "\n建议：优先保证充足睡眠，适当降低训练强度。如果持续感觉异常疲劳，建议咨询医生。"
            return response
        }

        return "根据现有数据，没有检测到明显的异常指标。感觉累可能与其他因素有关（如工作压力、营养等）。建议保持规律作息，如果持续感觉疲劳，建议咨询医生。"
    }

    private func buildSleepResponse(insights: [HealthInsight], sleepSessions: [SleepSession],
                                     summaries: [DailySummary]) -> String {
        let recentSummaries = summaries.suffix(7)
        let avgSleep = recentSummaries.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / max(Double(recentSummaries.count), 1)

        var response = "最近7天睡眠分析：\n"
        response += "- 平均睡眠时长: \(String(format: "%.1f", avgSleep)) 小时\n"

        let sleepInsight = insights.first { $0.relatedMetrics.contains("sleep_duration") }
        if let si = sleepInsight {
            response += "- \(si.message)\n"
        }

        if avgSleep < 7 {
            response += "\n你的睡眠时长低于推荐值。长期睡眠不足可能影响恢复、认知功能和整体健康。建议：\n"
            response += "- 固定睡眠时间\n- 睡前避免屏幕蓝光\n- 保持卧室凉爽、安静\n"
        } else {
            response += "\n睡眠时长在正常范围。保持规律作息有助于维持良好的恢复状态。"
        }

        return response
    }

    private func buildLoadResponse(insights: [HealthInsight], summaries: [DailySummary]) -> String {
        let loadInsight = insights.first { $0.relatedMetrics.contains("training_load") }

        if let li = loadInsight {
            return "\(li.message)\n\n\(li.suggestedAction ?? "")"
        }

        let recent = summaries.suffix(7)
        let avgLoad = recent.map(\.trainingLoad).reduce(0, +) / max(Double(recent.count), 1)

        return "最近7天平均训练负荷为 \(String(format: "%.0f", avgLoad))。训练负荷在正常范围内。建议保持当前训练节奏，注意训练后的恢复。"
    }

    private func buildSummaryResponse(insights: [HealthInsight], summaries: [DailySummary],
                                       workouts: [WorkoutSession]) -> String {
        guard let today = summaries.last else { return "暂无足够数据生成健康总结。" }

        var response = "## 今日健康总结\n\n"
        response += "**步数**: \(today.steps) 步\n"
        response += "**静息心率**: \(String(format: "%.0f", today.restingHeartRate)) bpm\n"
        response += "**睡眠**: \(today.sleepFormatted)\n"
        response += "**运动分钟**: \(today.exerciseMinutes) 分钟\n"
        response += "**恢复评分**: \(String(format: "%.0f", today.recoveryScore))/100\n"
        response += "**健康状态**: \(today.healthStatus.rawValue)\n"

        if !insights.isEmpty {
            response += "\n**关键发现**:\n"
            for insight in insights.prefix(3) {
                response += "- \(insight.title): \(insight.message)\n"
            }
        }

        return response
    }

    private func buildSuggestionResponse(insights: [HealthInsight], summaries: [DailySummary]) -> String {
        if insights.isEmpty {
            return "根据当前数据，你的健康状况看起来不错。继续保持规律作息和适度运动。"
        }

        var response = "基于你的健康数据，以下是本周建议：\n\n"
        for insight in insights {
            if let action = insight.suggestedAction {
                response += "- \(action)\n"
            }
        }
        return response
    }

    private func buildDefaultResponse(insights: [HealthInsight], summaries: [DailySummary]) -> String {
        if summaries.count < 7 {
            return "目前健康数据不足（\(summaries.count)天数据），分析的可靠性有限。建议导入更多 Apple Health 数据，或等待数据积累。导入方法：在 iPhone 上打开「健康」App → 点击头像 → 导出所有健康数据 → 通过 AirDrop 传到 Mac → 在 Sovereign 中导入。"
        }

        if insights.isEmpty {
            return "根据最近数据分析，各项指标在正常范围内。你可以问我：\n- 我今天适合训练吗？\n- 我最近恢复怎么样？\n- 帮我生成今天的健康总结。"
        }

        var response = "根据最近数据分析：\n"
        for insight in insights.prefix(3) {
            response += "- \(insight.message)\n"
        }
        return response
    }
}
