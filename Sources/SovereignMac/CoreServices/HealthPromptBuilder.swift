import Foundation

struct HealthPromptBuilder {

    /// System prompt that incorporates runtime status
    static func systemPrompt(for runtime: AIRuntimeStatus) -> String {
        let backend: String
        if runtime.providerMode.isCloud {
            backend = "DeepSeek V4 (\(runtime.modelName ?? "deepseek-v4-pro")) 作为语言模型后端"
        } else {
            backend = "本地规则引擎"
        }

        return """
你是 Sovereign App 内的 AI 健康教练与运动恢复分析师。Sovereign 是个人健康趋势监控与 AI 运动恢复分析系统。

你的身份：你是 Sovereign 里的 AI，不是单独的 DeepSeek 聊天机器人。DeepSeek 只是可能的后端语言模型。

当前后端：\(backend)
当前数据状态：\(runtime.dataSource.rawValue)

你使用结构化 Apple Health 摘要帮助用户理解健康趋势、睡眠、恢复、活动量和训练负荷。你可以给出具体、可执行、低风险的训练和恢复建议。

核心规则：
1. 你是 Sovereign 里的健康分析师，不是医生 — 不能做医疗诊断、不能开药、不能替代医疗建议
2. 每个结论都必须有数据依据 — 说清楚基于什么数据
3. 数据不足时明确说「数据不足」
4. 可以基于趋势做合理推断，但要说明依据和不确定性
5. 不能编造未提供的指标、日期或数值
6. 如果数据是 Demo/模拟数据，回答开头说明
7. 胸痛、晕厥、严重呼吸困难、自杀/自残 → 建议立即就医
8. 普通训练、减脂、疲劳、睡眠问题正常分析，给出保守建议
9. 如果用户问你的身份、模型、后端 — 说明你是 Sovereign 的 AI，DeepSeek 只是后端
10. 不要把自己称为 DeepSeek，你是 Sovereign
11. Apple Watch 数据只能作为生活方式参考，不是医疗级证据
12. 使用中文回复，简洁但信息完整（300字以内，除非用户要求详细分析）

回答结构：
- 先给结论，再给依据
- 依据按重要性排序
- 建议要具体到「今天/本周可以做什么」
- 指出数据限制
"""
    }

    /// Build context-rich user prompt with runtime info
    static func buildUserPrompt(question: String, context: HealthContext, runtime: AIRuntimeStatus) -> String {
        var parts: [String] = []

        // Sovereign runtime section
        parts.append("[Sovereign Runtime]")
        parts.append("App: Sovereign")
        parts.append("Role: AI health coach inside Sovereign")
        parts.append("Provider: \(runtime.providerMode.label)")
        if let model = runtime.modelName { parts.append("Model: \(model)") }
        parts.append("Data source: \(context.dataSource)")
        parts.append("")
        parts.append("[User Question]")
        parts.append(question)
        parts.append("")

        // Classify question type
        let q = question.lowercased()
        let questionType: String
        if q.contains("适合训练") || q.contains("可以训练") || q.contains("训练吗") { questionType = "TrainingReadiness" }
        else if q.contains("累") || q.contains("疲劳") { questionType = "FatigueAnalysis" }
        else if q.contains("睡眠") { questionType = "SleepAnalysis" }
        else if q.contains("训练负荷") || q.contains("训练量") { questionType = "TrainingLoad" }
        else if q.contains("恢复") { questionType = "RecoveryAnalysis" }
        else if q.contains("建议") || q.contains("安排") || q.contains("计划") { questionType = "WeeklyPlanning" }
        else if q.contains("总结") || q.contains("摘要") || q.contains("报告") { questionType = "HealthSummary" }
        else { questionType = "GeneralHealthQuestion" }
        parts.append("[Question Type]")
        parts.append(questionType)
        parts.append("")

        // Data status
        parts.append("[Data Status]")
        if context.isMockData {
            parts.append("⚠️ 当前数据为 Demo 演示数据，不是用户的真实健康数据。请在回答中明确说明。")
        }
        parts.append("数据来源: \(context.dataSource)")
        parts.append("数据范围: \(context.dataQuality.dateRangeStart) 至 \(context.dataQuality.dateRangeEnd)")
        parts.append("")

        // 7-day detailed data
        parts.append("[Last 7 Days — Daily Breakdown]")
        let sortedSteps = context.sevenDaySummary.dailySteps.sorted { $0.date < $1.date }
        if sortedSteps.isEmpty {
            parts.append("无数据")
        } else {
            for entry in sortedSteps {
                let sleep = context.sevenDaySummary.dailySleep.first(where: { $0.date == entry.date })?.value ?? 0
                let hr = context.sevenDaySummary.dailyRestingHR.first(where: { $0.date == entry.date })?.value ?? 0
                let recovery = context.sevenDaySummary.dailyRecoveryScore.first(where: { $0.date == entry.date })?.value ?? 0
                let load = context.sevenDaySummary.dailyTrainingLoad.first(where: { $0.date == entry.date })?.value ?? 0
                parts.append("- \(entry.date): 步数\(Int(entry.value)), 睡眠\(String(format: "%.1f", sleep))h, 静息心率\(Int(hr))bpm, 恢复\(Int(recovery)), 负荷\(Int(load))")
            }
        }
        parts.append("")

        // 30-day trends
        parts.append("[Last 30 Days — Trends]")
        parts.append("- 平均步数: \(String(format: "%.0f", context.thirtyDaySummary.avgSteps))/天")
        parts.append("- 平均睡眠: \(String(format: "%.1f", context.thirtyDaySummary.avgSleepHours)) 小时")
        parts.append("- 平均静息心率: \(String(format: "%.0f", context.thirtyDaySummary.avgRestingHR)) bpm")
        parts.append("- 30天运动次数: \(context.thirtyDaySummary.workoutFrequency) 次 · 总时长: \(context.thirtyDaySummary.totalWorkoutMinutes) 分钟")
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
        parts.append("[Data Limitations]")
        parts.append("- 缺失: \(context.dataQuality.missingMetrics.joined(separator: ", "))")
        parts.append("")

        // Response instructions
        parts.append("[Response Instructions]")
        parts.append("- Answer the user's actual question first.")
        parts.append("- Use the health data above as evidence.")
        parts.append("- Be specific and practical.")
        parts.append("- Do not invent missing data.")
        parts.append("- Do not claim to diagnose disease.")
        parts.append("- If data is insufficient, say exactly what is missing.")
        parts.append("- Keep the answer concise unless the user asks for detail.")
        parts.append("- Do NOT call yourself DeepSeek. You are Sovereign's AI coach.")

        return parts.joined(separator: "\n")
    }
}
