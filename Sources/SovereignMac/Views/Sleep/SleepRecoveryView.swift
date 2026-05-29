import SwiftUI
import Charts

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
                        message: "导入 Apple Health 数据以查看睡眠与恢复分析。"
                    )
                } else {
                    // Recovery score overview
                    recoveryOverview

                    // Sleep details
                    sleepDetails

                    // Recovery factors
                    recoveryFactors

                    // Sleep quality note
                    if hasLowQualitySleepData {
                        sleepQualityWarning
                    }

                    // Suggestion
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
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                        .frame(width: 110, height: 110)

                    Circle()
                        .trim(from: 0, to: min(healthStore.latestRecoveryScore / 100, 1.0))
                        .stroke(recoveryGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(String(format: "%.0f", healthStore.latestRecoveryScore))")
                            .font(AppTypography.scoreLarge)
                        Text("恢复评分")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("恢复状态: \(recoveryLabel)")
                            .font(AppTypography.title3)
                        Text("基于睡眠、心率、训练负荷综合分析")
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    HStack(spacing: AppSpacing.xl) {
                        sleepRecoveryStat(icon: "moon.zzz.fill", label: "睡眠", value: todaySleepFormatted, color: .indigo)
                        sleepRecoveryStat(icon: "heart.fill", label: "静息心率", value: todayHRFormatted, color: .red)
                        sleepRecoveryStat(icon: "chart.bar.fill", label: "训练负荷", value: todayLoadFormatted, color: .blue)
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

                // Sleep duration bar chart (last 14 days from summaries)
                let recentSummaries = healthStore.dailySummaries.prefix(14).reversed()
                if #available(macOS 14.0, *), !recentSummaries.isEmpty {
                    Chart {
                        ForEach(Array(recentSummaries), id: \.id) { s in
                            BarMark(x: .value("日期", s.dateFormatted), y: .value("睡眠", s.sleepHours))
                                .foregroundStyle(Color.indigo.opacity(0.6))
                        }
                        RuleMark(y: .value("推荐 7h", 7)).foregroundStyle(.orange.opacity(0.6)).lineStyle(StrokeStyle(dash: [4,4]))
                            .annotation(position: .trailing) { Text("7h").font(.caption2).foregroundColor(.orange) }
                    }
                    .chartXAxis { AxisMarks(values: .automatic) }
                    .chartYAxis { AxisMarks { _ in AxisValueLabel(); AxisGridLine() } }
                    .frame(height: 140)
                    Text("总计睡眠时长（小时）· 橙色虚线为 7 小时推荐值").font(.caption2).foregroundColor(.secondary).padding(.bottom, 4)
                }

                let recentSleep = healthStore.recentSleep.prefix(7)
                if recentSleep.isEmpty {
                    Text("暂无睡眠记录")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(recentSleep), id: \.id) { session in
                        VStack(spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDate(session.startDate))
                                        .font(AppTypography.callout)
                                    Text("\(formatTime(session.startDate)) — \(formatTime(session.endDate))")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("睡眠 \(session.durationFormatted)")
                                        .font(AppTypography.headline)
                                    if session.deepSleepHours > 0 || session.remSleepHours > 0 {
                                        Text("深睡 \(String(format: "%.1f", session.deepSleepHours))h · REM \(String(format: "%.1f", session.remSleepHours))h")
                                            .font(AppTypography.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if session.isInBedOnly {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                        .help("只有 InBed 数据，无法区分睡眠阶段")
                                }
                            }

                            // Sleep stage bar
                            if session.durationSeconds > 0 {
                                SleepStageBar(
                                    deep: session.deepSleepSeconds / session.durationSeconds,
                                    rem: session.remSleepSeconds / session.durationSeconds,
                                    core: session.coreSleepSeconds / session.durationSeconds,
                                    awake: session.awakeSeconds / session.durationSeconds,
                                    hasRealStages: session.hasRealSleepStages
                                )
                                .frame(height: 6)
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

    // MARK: - Sleep Quality Warning

    private var sleepQualityWarning: some View {
        CardView {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("数据质量提示")
                        .font(AppTypography.callout.weight(.medium))
                    Text("当前睡眠数据仅包含「卧床时间」(InBed)，无法区分深度睡眠、REM 和清醒时间。睡眠时长可能被高估。建议使用支持睡眠阶段检测的设备以获得更准确的分析。")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Recovery Factors

    private var recoveryFactors: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("恢复因素分析")
                    .font(AppTypography.title3)

                RecoveryFactorRow(label: "睡眠时长", value: sleepFactorValue, quality: sleepQuality)
                RecoveryFactorRow(label: "静息心率变化", value: hrFactorValue, quality: hrQuality)
                RecoveryFactorRow(label: "训练负荷", value: loadFactorValue, quality: loadQuality)
                RecoveryFactorRow(label: "HRV", value: hrvFactorValue, quality: hrvQuality)
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
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Computed

    private var hasLowQualitySleepData: Bool {
        let recentSleep = healthStore.recentSleep.prefix(7)
        return recentSleep.contains(where: { $0.isInBedOnly })
    }

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
        AngularGradient(colors: [.green, .mint, .yellow, .orange, .red], center: .center)
    }

    private var todaySleepFormatted: String {
        if let today = healthStore.todaySummary {
            return today.sleepFormatted
        }
        return healthStore.recentSleep.first?.durationFormatted ?? "N/A"
    }

    private var todayHRFormatted: String {
        guard let today = healthStore.todaySummary, today.restingHeartRate > 0 else { return "N/A" }
        return "\(Int(today.restingHeartRate)) bpm"
    }

    private var todayLoadFormatted: String {
        guard let today = healthStore.todaySummary else { return "N/A" }
        return "\(Int(today.trainingLoad))"
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
        let durations = healthStore.recentSleep.prefix(7).map(\.durationSeconds)
        guard durations.count >= 3 else { return "数据不足" }
        let avg = durations.reduce(0, +) / Double(durations.count)
        let variance = durations.map { abs($0 - avg) }.reduce(0, +) / Double(durations.count)
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

    // Recovery factors
    private var sleepFactorValue: String {
        let recentSleep = healthStore.recentSleep.prefix(1)
        guard let today = recentSleep.first else { return "N/A" }
        return "\(today.durationFormatted)"
    }

    private var sleepQuality: RecoveryFactorQuality {
        let duration = healthStore.recentSleep.first?.durationSeconds ?? 0
        if duration >= 28800 { return .good }
        if duration >= 21600 { return .moderate }
        return .poor
    }

    private var hrFactorValue: String {
        guard let today = healthStore.todaySummary, today.restingHeartRate > 0 else { return "N/A" }
        return "\(Int(today.restingHeartRate)) bpm"
    }
    private var hrQuality: RecoveryFactorQuality { .moderate }

    private var loadFactorValue: String {
        guard let today = healthStore.todaySummary else { return "N/A" }
        return "\(Int(today.trainingLoad))"
    }
    private var loadQuality: RecoveryFactorQuality {
        let load = healthStore.todaySummary?.trainingLoad ?? 0
        if load < 50 { return .good }
        if load < 100 { return .moderate }
        return .poor
    }

    private var hrvFactorValue: String {
        guard let hrv = healthStore.todaySummary?.heartRateVariability else { return "N/A" }
        return "\(Int(hrv)) ms"
    }
    private var hrvQuality: RecoveryFactorQuality {
        guard let hrv = healthStore.todaySummary?.heartRateVariability else { return .poor }
        if hrv >= 40 { return .good }
        if hrv >= 25 { return .moderate }
        return .poor
    }

    private var suggestionText: String {
        let score = healthStore.latestRecoveryScore
        let sleepHours = healthStore.todaySummary?.sleepHours ?? 0

        if score >= 70 {
            return "恢复状态良好。保持当前作息和训练节奏。注意保证每天 \(String(format: "%.1f", max(sleepHours, 7))) 小时的睡眠。"
        } else if score >= 40 {
            return "恢复状态一般。建议：1) 适当降低训练强度 2) 保证充足睡眠 3) 关注营养摄入。"
        } else {
            return "恢复状态需要关注。建议：1) 优先休息和睡眠 2) 避免高强度训练 3) 关注身体信号。如果持续感觉不适，请咨询医生。"
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

// MARK: - Sleep Stage Bar

struct SleepStageBar: View {
    let deep: Double
    let rem: Double
    let core: Double
    let awake: Double
    let hasRealStages: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if hasRealStages {
                    Rectangle().fill(Color.indigo.opacity(0.7)).frame(width: max(0, deep * geometry.size.width))
                    Rectangle().fill(Color.purple.opacity(0.5)).frame(width: max(0, rem * geometry.size.width))
                    Rectangle().fill(Color.blue.opacity(0.3)).frame(width: max(0, core * geometry.size.width))
                    Rectangle().fill(Color.orange.opacity(0.3)).frame(width: max(0, awake * geometry.size.width))
                } else {
                    Rectangle().fill(Color.indigo.opacity(0.3)).frame(width: geometry.size.width)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
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
