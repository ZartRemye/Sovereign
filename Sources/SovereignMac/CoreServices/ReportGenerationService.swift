import Foundation

actor ReportGenerationService {
    static let shared = ReportGenerationService()

    private init() {}

    // MARK: - Daily Report

    func generateDailyReport(
        date: Date,
        summary: DailySummary,
        insights: [HealthInsight],
        workouts: [WorkoutSession],
        sleepSessions: [SleepSession],
        aiContent: String? = nil
    ) -> HealthReport {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let dayWorkouts = workouts.filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
        let daySleep = sleepSessions.filter { $0.startDate >= dayStart && $0.startDate < dayEnd }

        var content = ""

        // Today's conclusion
        content += "## 今日结论\n\n"
        content += "健康状态: **\(summary.healthStatus.rawValue)**\n"
        content += "恢复评分: **\(String(format: "%.0f", summary.recoveryScore))/100**\n\n"

        // Key data
        content += "## 关键数据\n\n"
        content += "| 指标 | 数值 |\n"
        content += "|------|------|\n"
        content += "| 步数 | \(summary.steps) |\n"
        content += "| 静息心率 | \(String(format: "%.0f", summary.restingHeartRate)) bpm |\n"
        if let hrv = summary.heartRateVariability {
            content += "| HRV | \(String(format: "%.0f", hrv)) ms |\n"
        }
        content += "| 睡眠 | \(summary.sleepFormatted) |\n"
        content += "| 运动分钟 | \(summary.exerciseMinutes) 分钟 |\n"
        content += "| 训练负荷 | \(String(format: "%.0f", summary.trainingLoad)) |\n\n"

        // Recovery status
        content += "## 恢复状态\n\n"
        content += "\(buildRecoverySummary(summary: summary))\n\n"

        // Training suggestion
        content += "## 训练建议\n\n"
        content += "\(buildTrainingSuggestion(summary: summary, workouts: dayWorkouts))\n\n"

        // Sleep suggestion
        content += "## 睡眠建议\n\n"
        let sleepHours = summary.sleepDurationSeconds / 3600
        if sleepHours < 7 {
            content += "睡眠时长偏短 (\(String(format: "%.1f", sleepHours))小时)。建议今晚争取7-8小时睡眠。\n\n"
        } else {
            content += "睡眠时长正常 (\(String(format: "%.1f", sleepHours))小时)。保持规律作息。\n\n"
        }

        // Attention needed
        let warnings = insights.filter { $0.severity == .warning || $0.severity == .critical }
        if !warnings.isEmpty {
            content += "## 需要注意\n\n"
            for w in warnings {
                content += "- **\(w.title)**: \(w.message)\n"
            }
            content += "\n"
        }

        // AI content
        if let ai = aiContent, !ai.isEmpty {
            content += "## AI 分析\n\n"
            content += "\(ai)\n\n"
        }

        // Data limitations
        content += "## 数据限制\n\n"
        content += "- 分析基于本地规则\(aiContent != nil ? "和 DeepSeek AI" : "")。\n"
        content += "- 不是医疗诊断。如有健康疑虑，请咨询医生。\n"

        return HealthReport(
            id: UUID(),
            type: .daily,
            title: "日报 - \(formatDate(dayStart))",
            content: content,
            generatedAt: Date(),
            dateRange: (dayStart, dayEnd),
            source: aiContent != nil ? "Local Rules + DeepSeek" : "Local Rules"
        )
    }

    // MARK: - Weekly Report

    func generateWeeklyReport(
        weekEnding date: Date,
        summaries: [DailySummary],
        insights: [HealthInsight],
        workouts: [WorkoutSession],
        aiContent: String? = nil
    ) -> HealthReport {
        let calendar = Calendar.current
        let weekEnd = calendar.startOfDay(for: date)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: weekEnd)!
        let sorted = summaries.sorted { $0.date < $1.date }
        let weekSummaries = sorted.filter { $0.date >= weekStart && $0.date <= weekEnd }

        var content = ""

        // Overview
        content += "## 本周总览\n\n"
        let avgSteps = weekSummaries.map(\.steps.doubleValue).reduce(0, +) / max(Double(weekSummaries.count), 1)
        let avgSleep = weekSummaries.map { $0.sleepDurationSeconds / 3600 }.reduce(0, +) / max(Double(weekSummaries.count), 1)
        let avgHR = weekSummaries.map(\.restingHeartRate).filter { $0 > 0 }.reduce(0, +) / max(Double(weekSummaries.filter { $0.restingHeartRate > 0 }.count), 1)
        let totalExercise = weekSummaries.map(\.exerciseMinutes).reduce(0, +)

        content += "| 指标 | 平均值 |\n"
        content += "|------|--------|\n"
        content += "| 步数 | \(String(format: "%.0f", avgSteps))/天 |\n"
        content += "| 睡眠 | \(String(format: "%.1f", avgSleep)) 小时/天 |\n"
        content += "| 静息心率 | \(String(format: "%.0f", avgHR)) bpm |\n"
        content += "| 运动 | 共 \(totalExercise) 分钟 |\n\n"

        // Activity trend
        content += "## 活动趋势\n\n"
        let prevWeekSummaries = sorted.filter {
            let prevStart = calendar.date(byAdding: .day, value: -14, to: weekEnd)!
            return $0.date >= prevStart && $0.date < weekStart
        }
        let prevAvgSteps = prevWeekSummaries.map(\.steps.doubleValue).reduce(0, +) / max(Double(prevWeekSummaries.count), 1)
        if prevAvgSteps > 0 {
            let change = (avgSteps - prevAvgSteps) / prevAvgSteps * 100
            content += "步数较上周\(change > 0 ? "增加" : "减少") \(String(format: "%.0f", abs(change)))%。\n\n"
        } else {
            content += "步数趋势：\(avgSteps > 8000 ? "活跃" : avgSteps > 5000 ? "正常" : "偏低")\n\n"
        }

        // Sleep trend
        content += "## 睡眠趋势\n\n"
        content += "本周平均睡眠 \(String(format: "%.1f", avgSleep)) 小时。\n"
        if avgSleep < 7 {
            content += "⚠️ 睡眠低于推荐水平，建议关注。\n"
        }
        content += "\n"

        // Training load
        let avgLoad = weekSummaries.map(\.trainingLoad).reduce(0, +) / max(Double(weekSummaries.count), 1)
        content += "## 训练负荷\n\n"
        content += "本周平均训练负荷: \(String(format: "%.0f", avgLoad))\n\n"

        // Recovery trend
        let avgRecovery = weekSummaries.map(\.recoveryScore).reduce(0, +) / max(Double(weekSummaries.count), 1)
        content += "## 恢复趋势\n\n"
        content += "本周平均恢复评分: \(String(format: "%.0f", avgRecovery))/100\n"
        content += "恢复状态: \(recoveryLabel(avgRecovery))\n\n"

        // Next week suggestions
        content += "## 下周建议\n\n"
        if avgRecovery < 60 {
            content += "- 优先恢复：增加睡眠，降低训练强度\n"
        }
        if avgSleep < 7 {
            content += "- 改善睡眠：固定睡眠时间，睡前减少屏幕使用\n"
        }
        if totalExercise < 150 {
            content += "- 增加活动：目标是每周至少150分钟中等强度活动\n"
        }
        if insights.contains(where: { $0.severity == .warning }) {
            content += "- 关注提醒：有\(insights.filter { $0.severity == .warning }.count)项需要注意\n"
        }
        content += "\n"

        // AI content
        if let ai = aiContent, !ai.isEmpty {
            content += "## AI 分析\n\n\(ai)\n\n"
        }

        // Data limitations
        content += "## 数据限制\n\n"
        content += "- 分析基于本地规则\(aiContent != nil ? "和 DeepSeek AI" : "")。\n"
        content += "- 不是医疗诊断。如有健康疑虑，请咨询医生。\n"

        return HealthReport(
            id: UUID(),
            type: .weekly,
            title: "周报 - \(formatDate(weekStart)) 至 \(formatDate(weekEnd))",
            content: content,
            generatedAt: Date(),
            dateRange: (weekStart, weekEnd),
            source: aiContent != nil ? "Local Rules + DeepSeek" : "Local Rules"
        )
    }

    // MARK: - Monthly Report (stub)

    func generateMonthlyReport(
        monthEnding date: Date,
        summaries: [DailySummary],
        insights: [HealthInsight],
        workouts: [WorkoutSession]
    ) -> HealthReport {
        let calendar = Calendar.current
        let monthEnd = calendar.startOfDay(for: date)
        let monthStart = calendar.date(byAdding: .day, value: -30, to: monthEnd)!

        var content = "## 月度总览\n\n"
        content += "月度报告功能开发中。当前提供基础数据概览。\n\n"

        let avgRecovery = summaries.map(\.recoveryScore).reduce(0, +) / max(Double(summaries.count), 1)
        content += "30天平均恢复评分: \(String(format: "%.0f", avgRecovery))/100\n\n"

        content += "## 数据限制\n\n"
        content += "- 不是医疗诊断。如有健康疑虑，请咨询医生。\n"

        return HealthReport(
            id: UUID(),
            type: .monthly,
            title: "月报 - \(formatDate(monthStart)) 至 \(formatDate(monthEnd))",
            content: content,
            generatedAt: Date(),
            dateRange: (monthStart, monthEnd),
            source: "Local Rules"
        )
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func buildRecoverySummary(summary: DailySummary) -> String {
        let score = summary.recoveryScore
        switch score {
        case 80...: return "恢复状态**优秀**，身体处于良好恢复状态。"
        case 60..<80: return "恢复状态**良好**，可以继续正常活动。"
        case 40..<60: return "恢复状态**一般**，建议适当关注休息。"
        case 20..<40: return "恢复状态**偏低**，建议降低训练强度。"
        default: return "恢复状态**不足**，应优先休息和恢复。"
        }
    }

    private func buildTrainingSuggestion(summary: DailySummary, workouts: [WorkoutSession]) -> String {
        let score = summary.recoveryScore
        if score >= 70 {
            return "可以正常训练。基于恢复评分为 \(String(format: "%.0f", score))/100。"
        } else if score >= 50 {
            return "可以进行低到中等强度训练。高强度训练建议等恢复评分提升后再进行。"
        } else {
            return "建议今天是主动恢复日。可进行散步、拉伸等轻度活动。这不替代专业训练指导。"
        }
    }

    private func recoveryLabel(_ score: Double) -> String {
        switch score {
        case 80...: return "优秀"
        case 60..<80: return "良好"
        case 40..<60: return "一般"
        case 20..<40: return "偏低"
        default: return "不足"
        }
    }
}

private extension Int {
    var doubleValue: Double { Double(self) }
}
