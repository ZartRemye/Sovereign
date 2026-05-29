import SwiftUI

struct SleepRecoveryView: View {
    @EnvironmentObject var healthStore: MacHealthStore

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Text("睡眠与恢复")
                    .font(AppTypography.largeTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if healthStore.dailySummaries.isEmpty {
                    EmptyStateView(
                        systemImage: "moon.zzz.fill",
                        title: "暂无睡眠数据",
                        message: "导入 Apple Health 数据或加载模拟数据以查看睡眠与恢复分析。"
                    )
                } else {
                    // Recovery score overview
                    recoveryOverview

                    // Sleep details
                    sleepDetails

                    // Recovery factors
                    recoveryFactors

                    // Today's suggestion
                    todaySuggestion
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("睡眠恢复")
    }

    // MARK: - Recovery Overview

    private var recoveryOverview: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.xxl) {
                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: healthStore.latestRecoveryScore / 100)
                        .stroke(recoveryGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(String(format: "%.0f", healthStore.latestRecoveryScore))")
                            .font(AppTypography.scoreLarge)
                        Text("恢复评分")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if let today = healthStore.todaySummary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("恢复状态: \(recoveryLabel)")
                                .font(AppTypography.title3)
                            Text("基于睡眠、心率、训练负荷综合分析")
                                .font(AppTypography.callout)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack(spacing: AppSpacing.xl) {
                            sleepRecoveryStat(icon: "moon.zzz.fill", label: "睡眠", value: today.sleepFormatted, color: .indigo)
                            sleepRecoveryStat(icon: "heart.fill", label: "静息心率", value: "\(String(format: "%.0f", today.restingHeartRate)) bpm", color: .red)
                            sleepRecoveryStat(icon: "chart.bar.fill", label: "训练负荷", value: "\(String(format: "%.0f", today.trainingLoad))", color: .blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sleep Details

    private var sleepDetails: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("最近睡眠")
                    .font(AppTypography.title3)

                let recentSleep = healthStore.recentSleep.prefix(7)
                if recentSleep.isEmpty {
                    Text("暂无睡眠记录")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(recentSleep), id: \.id) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatDate(session.startDate))
                                    .font(AppTypography.callout)
                                Text("\(formatTime(session.startDate)) - \(formatTime(session.endDate))")
                                    .font(AppTypography.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(session.durationFormatted)
                                .font(AppTypography.headline)

                            if session.durationSeconds < 21600 {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)

                        if session.id != recentSleep.last?.id {
                            Divider()
                        }
                    }
                }

                // Sleep regularity
                HStack {
                    Text("睡眠规律性")
                        .font(AppTypography.callout)
                    Spacer()
                    Text(sleepRegularity)
                        .font(AppTypography.headline)
                        .foregroundColor(sleepRegularityColor)
                }
                .padding(.top, AppSpacing.sm)
            }
        }
    }

    // MARK: - Recovery Factors

    private var recoveryFactors: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("恢复因素分析")
                    .font(AppTypography.title3)

                RecoveryFactorRow(
                    label: "睡眠时长",
                    value: sleepFactorValue,
                    quality: sleepQuality
                )
                RecoveryFactorRow(
                    label: "静息心率变化",
                    value: hrFactorValue,
                    quality: hrQuality
                )
                RecoveryFactorRow(
                    label: "训练负荷",
                    value: loadFactorValue,
                    quality: loadQuality
                )
                RecoveryFactorRow(
                    label: "心率变异性 (HRV)",
                    value: hrvFactorValue,
                    quality: hrvQuality
                )
            }
        }
    }

    // MARK: - Suggestion

    private var todaySuggestion: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("今日建议")
                        .font(AppTypography.title3)
                }

                Text(suggestionText)
                    .font(AppTypography.callout)
                    .foregroundColor(.secondary)

                Text("此建议基于行为数据分析，不是医疗诊断。如有健康疑虑，请咨询医生。")
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    private var recoveryLabel: String {
        let score = healthStore.latestRecoveryScore
        switch score {
        case 80...: return "优秀"
        case 60..<80: return "良好"
        case 40..<60: return "一般"
        case 20..<40: return "偏低"
        default: return "不足"
        }
    }

    private var recoveryGradient: AngularGradient {
        AngularGradient(
            colors: [.green, .mint, .yellow, .orange, .red],
            center: .center
        )
    }

    private func sleepRecoveryStat(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(AppTypography.callout.weight(.medium))
            Text(label)
                .font(AppTypography.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var sleepRegularity: String {
        let sleepDurations = healthStore.recentSleep.prefix(7).map(\.durationSeconds)
        guard sleepDurations.count >= 3 else { return "数据不足" }
        let avg = sleepDurations.reduce(0, +) / Double(sleepDurations.count)
        let variance = sleepDurations.map { abs($0 - avg) }.reduce(0, +) / Double(sleepDurations.count)
        if variance < 1800 { return "规律" }
        if variance < 3600 { return "较规律" }
        return "不规律"
    }

    private var sleepRegularityColor: Color {
        switch sleepRegularity {
        case "规律": return .green
        case "较规律": return .orange
        default: return .red
        }
    }

    // Simplified factor values (in a real app these come from RecoveryAnalyzer)
    private var sleepFactorValue: String { healthStore.recentSleep.first?.durationFormatted ?? "N/A" }
    private var sleepQuality: RecoveryFactorQuality {
        let duration = healthStore.recentSleep.first?.durationSeconds ?? 0
        if duration >= 25200 { return .good }
        if duration >= 21600 { return .moderate }
        return .poor
    }

    private var hrFactorValue: String {
        guard let today = healthStore.todaySummary else { return "N/A" }
        return "\(String(format: "%.0f", today.restingHeartRate)) bpm"
    }
    private var hrQuality: RecoveryFactorQuality { .moderate }

    private var loadFactorValue: String {
        guard let today = healthStore.todaySummary else { return "N/A" }
        return "\(String(format: "%.0f", today.trainingLoad))"
    }
    private var loadQuality: RecoveryFactorQuality { .moderate }

    private var hrvFactorValue: String {
        guard let hrv = healthStore.todaySummary?.heartRateVariability else { return "N/A" }
        return "\(String(format: "%.0f", hrv)) ms"
    }
    private var hrvQuality: RecoveryFactorQuality { .moderate }

    private var suggestionText: String {
        let score = healthStore.latestRecoveryScore
        let sleepHours = (healthStore.recentSleep.first?.durationSeconds ?? 0) / 3600

        if score >= 70 {
            return "你的恢复状态良好。继续维持当前作息和训练节奏。注意保证每天 \(String(format: "%.1f", max(sleepHours, 7))) 小时的睡眠。"
        } else if score >= 40 {
            return "恢复状态一般。建议：1) 适当降低训练强度 2) 保证充足睡眠 3) 关注营养摄入。"
        } else {
            return "恢复状态需要关注。强烈建议：1) 优先休息和睡眠 2) 避免高强度训练 3) 关注身体信号。如果持续感觉不适，请咨询医生。"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Recovery Factor Types

enum RecoveryFactorQuality {
    case good, moderate, poor

    var color: Color {
        switch self {
        case .good: return .green
        case .moderate: return .orange
        case .poor: return .red
        }
    }

    var label: String {
        switch self {
        case .good: return "良好"
        case .moderate: return "一般"
        case .poor: return "偏低"
        }
    }
}

struct RecoveryFactorRow: View {
    let label: String
    let value: String
    let quality: RecoveryFactorQuality

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.callout)
            Spacer()
            Text(value)
                .font(AppTypography.callout.weight(.medium))
            Text(quality.label)
                .font(AppTypography.caption)
                .foregroundColor(quality.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(quality.color.opacity(0.12), in: Capsule())
        }
    }
}
