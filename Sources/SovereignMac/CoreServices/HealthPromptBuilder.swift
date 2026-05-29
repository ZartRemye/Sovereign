import Foundation

struct HealthPromptBuilder {

    /// System prompt incorporating Elite Health Coach Skill and runtime context
    static func systemPrompt(for runtime: AIRuntimeStatus) -> String {
        let skill = AISkillLoader.loadEliteHealthCoachSkill()
        let backend = runtime.providerMode.isCloud
            ? "DeepSeek V4 (\(runtime.modelName ?? "deepseek-v4-pro")) as language model backend"
            : "Local Rules Engine"

        return """
\(skill)

## Current Runtime
- Provider: \(runtime.providerMode.label)
- Backend: \(backend)
- Data: \(runtime.dataSource.rawValue)
- Has API Key: \(runtime.hasAPIKey)
- Cloud AI Enabled: \(runtime.isCloudAIEnabled)
- Health Data Available: \(runtime.hasRealHealthData)

IMPORTANT: When asked who you are or what model you use, state that you are Sovereign's internal AI health coach. DeepSeek is only your language model backend when enabled.
"""
    }

    /// Build full prompt with skill, model, forecast, and exercise prescription
    static func buildUserPrompt(
        question: String,
        context: HealthContext,
        runtime: AIRuntimeStatus,
        healthModel: PersonalHealthModel,
        forecast: HealthForecast,
        prescription: ExercisePrescription
    ) -> String {
        var parts: [String] = []

        // Runtime
        parts.append("[Sovereign Runtime]")
        parts.append("App: Sovereign")
        parts.append("Role: AI health coach inside Sovereign")
        parts.append("Provider: \(runtime.providerMode.label)")
        if let model = runtime.modelName { parts.append("Model: \(model)") }
        parts.append("Data: \(runtime.dataSource.rawValue)")
        parts.append("")

        // Personal Health Model
        parts.append("[Personal Health Model]")
        parts.append(healthModel.summary)
        parts.append("")

        // Forecast
        parts.append("[Forecast (\(forecast.horizonDays)-day)]")
        parts.append("Recovery: \(forecast.recoveryForecast)")
        parts.append("Training Risk: \(forecast.trainingRiskForecast)")
        parts.append("Sleep Risk: \(forecast.sleepRiskForecast)")
        parts.append("Confidence: \(forecast.confidence)")
        if !forecast.assumptions.isEmpty {
            parts.append("Assumptions: \(forecast.assumptions.joined(separator: "; "))")
        }
        parts.append("")

        // Exercise Prescription Context
        parts.append("[Exercise Prescription Context]")
        parts.append("Readiness: \(prescription.readiness.rawValue)")
        parts.append("Recommended: \(prescription.recommendedTrainingType)")
        parts.append("Intensity: \(prescription.intensity)")
        if let hrZone = prescription.targetHeartRateZone { parts.append("HR Zone: \(hrZone)") }
        parts.append("Stop Conditions: \(prescription.stopConditions.joined(separator: "; "))")
        parts.append("Rationale: \(prescription.rationale.joined(separator: "; "))")
        parts.append("")

        // 7-day data
        parts.append("[Last 7 Days]")
        let sortedSteps = context.sevenDaySummary.dailySteps.sorted { $0.date < $1.date }
        if sortedSteps.isEmpty {
            parts.append("No data available")
        } else {
            for entry in sortedSteps {
                let sleep = context.sevenDaySummary.dailySleep.first(where: { $0.date == entry.date })?.value ?? 0
                let hr = context.sevenDaySummary.dailyRestingHR.first(where: { $0.date == entry.date })?.value ?? 0
                let recovery = context.sevenDaySummary.dailyRecoveryScore.first(where: { $0.date == entry.date })?.value ?? 0
                let load = context.sevenDaySummary.dailyTrainingLoad.first(where: { $0.date == entry.date })?.value ?? 0
                parts.append("- \(entry.date): steps \(Int(entry.value)), sleep \(String(format: "%.1f", sleep))h, RHR \(Int(hr)), recovery \(Int(recovery)), load \(Int(load))")
            }
        }
        parts.append("")

        // 30-day trends
        parts.append("[Last 30 Days Trends]")
        parts.append("- Avg Steps: \(String(format: "%.0f", context.thirtyDaySummary.avgSteps))/day")
        parts.append("- Avg Sleep: \(String(format: "%.1f", context.thirtyDaySummary.avgSleepHours))h")
        parts.append("- Avg RHR: \(String(format: "%.0f", context.thirtyDaySummary.avgRestingHR)) bpm")
        parts.append("- Workouts: \(context.thirtyDaySummary.workoutFrequency) sessions, \(context.thirtyDaySummary.totalWorkoutMinutes) min")
        parts.append("- Load Trend: \(context.thirtyDaySummary.trainingLoadChange)")
        parts.append("- Recovery Trend: \(context.thirtyDaySummary.recoveryTrend)")
        parts.append("- Sleep Trend: \(context.thirtyDaySummary.sleepTrend)")
        parts.append("- Activity Trend: \(context.thirtyDaySummary.activityTrend)")
        parts.append("")

        // Recent workouts
        if !context.recentWorkouts.isEmpty {
            parts.append("[Recent Workouts]")
            for w in context.recentWorkouts {
                var line = "- \(w.date): \(w.type), \(w.durationMinutes)min"
                if let km = w.distanceKm { line += ", \(String(format: "%.1f", km))km" }
                if let hr = w.avgHeartRate { line += ", HR \(String(format: "%.0f", hr))" }
                line += ", \(w.intensityEstimate)"
                parts.append(line)
            }
            parts.append("")
        }

        // Local insights
        if !context.localInsights.isEmpty {
            parts.append("[Local Insights]")
            for insight in context.localInsights {
                parts.append("- [\(insight.severity)] \(insight.title): \(insight.message)")
            }
            parts.append("")
        }

        // Data limitations
        parts.append("[Data Limitations]")
        parts.append("- Missing: \(context.dataQuality.missingMetrics.joined(separator: ", "))")
        if context.isMockData { parts.append("- WARNING: Current data is DEMO data, not real user health data") }
        parts.append("")

        // User question
        parts.append("[User Question]")
        parts.append(question)
        parts.append("")

        // Response instructions
        parts.append("[Answer Rules]")
        parts.append("- Answer the user's actual question first")
        parts.append("- Use evidence from the Personal Health Model and data above")
        parts.append("- Give concrete next actions the user can take today")
        parts.append("- Mention uncertainty and data limitations")
        parts.append("- Do NOT diagnose disease or prescribe medication")
        parts.append("- If red flags appear, recommend professional medical help")
        parts.append("- If this is an identity question (who are you, what model), answer based on Runtime section above")
        parts.append("- Be concise. No generic wellness fluff.")

        return parts.joined(separator: "\n")
    }
}
