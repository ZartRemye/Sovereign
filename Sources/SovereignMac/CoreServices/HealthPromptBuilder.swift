import Foundation

struct HealthPromptBuilder {
    /// System prompt: private health analyst + exercise recovery coach
    static let systemPrompt = """
你是一位私人健康数据分析师和运动恢复教练，运行在 Sovereign App 中。

你的角色：
1. 基于用户的 Apple Health 数据，分析健康趋势、运动模式和恢复状态
2. 提供基于具体数据的、可执行的训练和恢复建议
3. 解释数据背后的含义，帮助用户理解自己的身体状态

核心规则：
1. 你是健康数据分析师，不是医生 — 永远不要做医疗诊断、不要推荐药物、不要开处方
2. 每个结论都必须有数据依据 — 说清楚是基于什么数据得出的
3. 数据不足时，必须明确告诉用户「数据不足，无法做出可靠判断」
4. 可以基于趋势做合理推断和建议，但不能编造不存在的数据
5. 回答要具体、实用、可操作 — 不要泛泛而谈
6. 如果数据是 Demo/模拟数据，在回答开头明确说明
7. 遇到胸痛、晕厥、严重呼吸困难、自杀/自残等高风险情况，建议立即就医
8. 普通训练、减脂、疲劳、睡眠问题正常分析，给出保守建议
9. 使用中文回复
10. 回复简洁但信息完整（控制在300字以内，除非用户要求详细分析）

回答结构建议：
- 先给结论，再给依据
- 依据按照重要性排序
- 建议要具体到「今天/本周可以做什么」
- 指出数据限制，避免过度自信
"""

    /// Build a context-rich user prompt based on the question type
    static func buildUserPrompt(question: String, context: HealthContext) -> String {
        var parts: [String] = []

        // Question
        parts.append("[User Question]")
        parts.append(question)
        parts.append("")

        // Data status
        parts.append("[Data Status]")
        if context.isMockData {
            parts.append("⚠️ 当前数据为 Demo 演示数据，不是用户的真实健康数据。请在回答中明确说明。")
        }
        parts.append("数据来源: \(context.dataSource)")
        parts.append("数据范围: \(context.dataQuality.dateRangeStart) 至 \(context.dataQuality.dateRangeEnd)")
        if let syncDate = context.dataQuality.lastSyncDate {
            parts.append("最近导入: \(syncDate)")
        }
        parts.append("")

        // 7-day detailed data
        parts.append("[Last 7 Days — Daily Breakdown]")
        let sortedSteps = context.sevenDaySummary.dailySteps.sorted { $0.date < $1.date }
        for entry in sortedSteps {
            let sleep = context.sevenDaySummary.dailySleep.first(where: { $0.date == entry.date })?.value ?? 0
            let hr = context.sevenDaySummary.dailyRestingHR.first(where: { $0.date == entry.date })?.value ?? 0
            let recovery = context.sevenDaySummary.dailyRecoveryScore.first(where: { $0.date == entry.date })?.value ?? 0
            let load = context.sevenDaySummary.dailyTrainingLoad.first(where: { $0.date == entry.date })?.value ?? 0
            parts.append("- \(entry.date): 步数\(Int(entry.value)), 睡眠\(String(format: "%.1f", sleep))h, 静息心率\(Int(hr))bpm, 恢复\(Int(recovery)), 负荷\(Int(load))")
        }
        parts.append("")

        // 30-day trends
        parts.append("[Last 30 Days — Trends]")
        parts.append("- 平均步数: \(String(format: "%.0f", context.thirtyDaySummary.avgSteps))/天")
        parts.append("- 平均睡眠: \(String(format: "%.1f", context.thirtyDaySummary.avgSleepHours)) 小时")
        parts.append("- 平均静息心率: \(String(format: "%.0f", context.thirtyDaySummary.avgRestingHR)) bpm")
        parts.append("- 30天运动次数: \(context.thirtyDaySummary.workoutFrequency) 次")
        parts.append("- 30天运动总时长: \(context.thirtyDaySummary.totalWorkoutMinutes) 分钟")
        parts.append("- 训练负荷变化: \(context.thirtyDaySummary.trainingLoadChange)")
        parts.append("- 恢复趋势: \(context.thirtyDaySummary.recoveryTrend)")
        parts.append("- 睡眠趋势: \(context.thirtyDaySummary.sleepTrend)")
        parts.append("- 活动趋势: \(context.thirtyDaySummary.activityTrend)")
        parts.append("")

        // Recent workouts
        if !context.recentWorkouts.isEmpty {
            parts.append("[Recent Workouts]")
            for w in context.recentWorkouts {
                var line = "- \(w.date): \(w.type), \(w.durationMinutes)分钟"
                if let km = w.distanceKm { line += ", \(String(format: "%.1f", km))km" }
                if let hr = w.avgHeartRate { line += ", 平均心率\(String(format: "%.0f", hr))" }
                line += ", 强度:\(w.intensityEstimate)"
                parts.append(line)
            }
            parts.append("")
        }

        // Local insights
        if !context.localInsights.isEmpty {
            parts.append("[Local Analysis Findings]")
            for insight in context.localInsights {
                parts.append("- [\(insight.severity)] \(insight.title): \(insight.message)")
            }
            parts.append("")
        }

        // Missing data
        parts.append("[Missing Data]")
        parts.append("- 缺失: \(context.dataQuality.missingMetrics.joined(separator: ", "))")
        parts.append("")

        // Response requirements based on question type
        parts.append("[Response Requirements]")
        let q = question.lowercased()
        if q.contains("适合训练") || q.contains("可以训练") || q.contains("训练吗") {
            parts.append("请按以下结构回答：1) 结论（适合/不适合/只适合低强度/数据不足）2) 依据（睡眠、静息心率、训练负荷、最近运动）3) 今天建议（做什么、强度、注意事项）4) 数据限制说明")
        } else if q.contains("累") || q.contains("疲劳") || q.contains("为什么") {
            parts.append("请按以下结构回答：1) 可能原因（按可能性排序）2) 每个原因的数据依据 3) 改善建议 4) 需要继续观察的指标")
        } else if q.contains("睡眠") {
            parts.append("请按以下结构回答：1) 整体判断 2) 睡眠时长和规律性 3) 与恢复的关联 4) 改善建议 5) 数据质量说明（是否为InBed估计值）")
        } else if q.contains("训练负荷") || q.contains("训练量") {
            parts.append("请按以下结构回答：1) 当前负荷评估 2) 急慢性负荷比 3) 与恢复的关系 4) 本周训练建议 5) 风险提示")
        } else if q.contains("建议") || q.contains("安排") || q.contains("计划") {
            parts.append("请给出一周的低风险训练安排，包括：每天的训练类型建议、强度控制、休息日安排。所有建议要保守，注明依据。")
        } else if q.contains("总结") || q.contains("摘要") || q.contains("报告") {
            parts.append("请生成简洁的健康数据摘要，突出核心指标和最重要的1-3个发现。")
        } else {
            parts.append("请基于以上数据回答用户问题。如果问题超出健康数据分析范围，请礼貌说明你的职责范围。")
        }

        return parts.joined(separator: "\n")
    }
}
