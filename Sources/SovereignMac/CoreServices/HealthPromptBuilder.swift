import Foundation

struct HealthPromptBuilder {
    /// Build the system prompt for the AI coach
    static let systemPrompt = """
        你是一个健康与运动数据分析助理，运行在 Sovereign App 中。\
        你不是医生，不能做医疗诊断，只能基于给定健康摘要给出保守、可解释、低风险建议。

        规则:
        1. 永远不要诊断疾病或推荐药物
        2. 基于数据给出建议，而不是猜测
        3. 如果数据不足，明确指出来
        4. 如果用户提到胸痛、晕厥、严重呼吸困难等症状，建议他们立即就医
        5. 使用中文回复
        6. 保持回复简洁（200字以内，除非用户要求详细分析）
        7. 每个建议都要说明是基于什么数据做出的
        8. 如果数据是模拟数据，必须在回复开头说明
        """

    /// Build a user prompt with health context
    static func buildUserPrompt(question: String, context: HealthContext) -> String {
        var parts: [String] = []

        parts.append("## 用户问题")
        parts.append(question)
        parts.append("")

        parts.append("## 健康数据摘要")

        if context.isMockData {
            parts.append("⚠️ 以下数据为模拟数据，仅供参考和开发测试使用。")
        }

        parts.append("数据来源: \(context.dataSource)")
        parts.append("数据范围: \(context.dataQuality.dateRangeStart) 至 \(context.dataQuality.dateRangeEnd)")

        // 7-day summary
        parts.append("")
        parts.append("### 最近7天数据")
        let sleepValues = context.sevenDaySummary.dailySleep.map(\.value)
        let avgSleep = sleepValues.reduce(0, +) / max(Double(sleepValues.count), 1)
        parts.append("- 平均睡眠: \(String(format: "%.1f", avgSleep)) 小时")

        let hrValues = context.sevenDaySummary.dailyRestingHR.map(\.value)
        let avgHR = hrValues.reduce(0, +) / max(Double(hrValues.count), 1)
        parts.append("- 平均静息心率: \(String(format: "%.0f", avgHR)) bpm")

        let stepsTotal = context.sevenDaySummary.dailySteps.map(\.value).reduce(0, +)
        parts.append("- 7天总步数: \(String(format: "%.0f", stepsTotal))")

        // 30-day summary
        parts.append("")
        parts.append("### 最近30天概览")
        parts.append("- 平均步数: \(String(format: "%.0f", context.thirtyDaySummary.avgSteps))/天")
        parts.append("- 平均睡眠: \(String(format: "%.1f", context.thirtyDaySummary.avgSleepHours)) 小时")
        parts.append("- 平均静息心率: \(String(format: "%.0f", context.thirtyDaySummary.avgRestingHR)) bpm")
        parts.append("- 运动频率: \(context.thirtyDaySummary.workoutFrequency) 次")
        parts.append("- 训练负荷变化: \(context.thirtyDaySummary.trainingLoadChange)")
        parts.append("- 恢复趋势: \(context.thirtyDaySummary.recoveryTrend)")

        // Recent workouts
        if !context.recentWorkouts.isEmpty {
            parts.append("")
            parts.append("### 最近运动")
            for w in context.recentWorkouts {
                var line = "- \(w.date): \(w.type), \(w.durationMinutes)分钟"
                if let km = w.distanceKm { line += ", \(String(format: "%.1f", km))km" }
                if let hr = w.avgHeartRate { line += ", 平均心率\(String(format: "%.0f", hr))" }
                line += ", 强度:\(w.intensityEstimate)"
                parts.append(line)
            }
        }

        // Local insights
        if !context.localInsights.isEmpty {
            parts.append("")
            parts.append("### 本地分析发现")
            for insight in context.localInsights {
                parts.append("- [\(insight.severity)] \(insight.title): \(insight.message)")
            }
        }

        // Data quality
        parts.append("")
        parts.append("### 数据质量")
        parts.append("- 缺失指标: \(context.dataQuality.missingMetrics.joined(separator: ", "))")
        if context.isMockData {
            parts.append("- 数据类型: Mock 模拟数据")
        }

        return parts.joined(separator: "\n")
    }
}
