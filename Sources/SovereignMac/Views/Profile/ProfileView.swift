import SwiftUI
import Charts

struct ProfileView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @EnvironmentObject var chatStore: ChatSessionStore
    @StateObject private var aiCoordinator = AIRequestCoordinator.shared

    private var profile: PersonalHealthProfile {
        PersonalHealthProfileBuilder().build(
            summaries: healthStore.dailySummaries,
            workouts: healthStore.recentWorkouts,
            sleep: healthStore.recentSleep
        )
    }

    private var confidenceLabel: String {
        let days = healthStore.dbSummaryCount
        if healthStore.isDemoData { return "演示数据" }
        if days >= 60 { return "高" }
        if days >= 30 { return "中" }
        if days >= 7 { return "低" }
        return "不足"
    }

    private var confidenceColor: Color {
        if healthStore.isDemoData { return .orange }
        switch confidenceLabel {
        case "高": return .green; case "中": return .blue; case "低": return .orange
        default: return .gray
        }
    }

    var body: some View {
        ScrollView {
            if healthStore.dataSource == .empty {
                EmptyStateView(systemImage: "person.fill.viewfinder",
                               title: "暂无健康数据",
                               message: "导入 Apple Health 数据以生成你的个人健康画像。")
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    profileHeader
                    if healthStore.isDemoData { demoWarning }
                    profileTags
                    baselineGrid
                    readinessSection
                    trainingLoadSection
                    sleepSection
                    workoutIdentity
                    strengthsAndConstraints
                    actionButtons
                }
                .padding(AppSpacing.xl)
            }
        }
        .navigationTitle("健康画像")
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("健康画像").font(AppTypography.largeTitle)
                    HStack(spacing: 8) {
                        statusBadge(healthStore.dataSource.rawValue, dataSourceColor)
                        if let s = profile.dataRangeStart, let e = profile.dataRangeEnd {
                            Text("\(s.formatted(date: .numeric, time: .omitted)) – \(e.formatted(date: .numeric, time: .omitted))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("数据完整度 \(String(format: "%.0f", profile.dataCompleteness * 100))%")
                        .font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Circle().fill(confidenceColor).frame(width: 6, height: 6)
                        Text("画像置信度: \(confidenceLabel)").font(.caption).foregroundColor(confidenceColor)
                    }
                }
            }
        }
    }

    private var demoWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text("当前为演示数据，画像不代表真实身体状态。导入 Apple Health 数据后将自动替换。")
                .font(.caption).foregroundColor(.orange)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tags

    private var profileTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(profile.dominantTags, id: \.self) { tag in
                    Text(tag).font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(tagColor(tag).opacity(0.1), in: Capsule())
                        .foregroundColor(tagColor(tag))
                }
                if profile.dominantTags.isEmpty {
                    Text("数据不足以生成画像标签").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Baseline

    private var baselineGrid: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("健康基线").font(AppTypography.title3)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.lg) {
                baselineCard("日均步数", profile.baselineSteps.map { String(format: "%.0f", $0) } ?? "—", "步", "figure.walk", .mint)
                baselineCard("平均睡眠", profile.baselineSleepHours.map { String(format: "%.1f", $0) } ?? "—", "小时", "moon.zzz.fill", .indigo)
                baselineCard("静息心率", profile.baselineRestingHeartRate.map { String(format: "%.0f", $0) } ?? "—", "bpm", "heart.fill", .red)
                baselineCard("心率变异性", profile.baselineHRV.map { String(format: "%.0f", $0) } ?? "—", "ms", "waveform.path.ecg", .purple)
                baselineCard("活动能量", profile.baselineActiveEnergy.map { String(format: "%.0f", $0) } ?? "—", "kJ", "flame.fill", .orange)
                baselineCard("训练负荷", profile.baselineTrainingLoad.map { String(format: "%.0f", $0) } ?? "—", "分", "chart.bar.fill", .blue)
            }
        }
    }

    // MARK: - Readiness

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("当日准备度与恢复").font(AppTypography.title3)
            HStack(spacing: AppSpacing.xl) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.1), lineWidth: 8).frame(width: 100, height: 100)
                    Circle().trim(from: 0, to: min((profile.currentRecoveryScore ?? 0) / 100, 1))
                        .stroke(recoveryGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(String(format: "%.0f", profile.currentRecoveryScore ?? 0))").font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("恢复").font(.caption2).foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    profileBar("睡眠", score: profile.sleepConsistencyScore ?? 0)
                    profileBar("活动", score: profile.activityConsistencyScore ?? 0)
                    profileBar("心肺", score: profile.cardioStabilityScore ?? 0)
                    profileBar("训练", score: profile.trainingRegularityScore ?? 0)
                }
            }
        }
    }

    // MARK: - Training Load

    private var trainingLoadSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("训练负荷模型").font(AppTypography.title3)
            HStack(spacing: AppSpacing.xl) {
                metricPill("急性负荷 (7天)", profile.acuteTrainingLoad7d.map { String(format: "%.0f", $0) } ?? "—")
                metricPill("慢性负荷 (28天)", profile.chronicTrainingLoad28d.map { String(format: "%.0f", $0) } ?? "—")
                metricPill("急慢性比 (ACWR)", profile.acuteChronicRatio.map { String(format: "%.2f", $0) } ?? "—")
                Spacer()
                Text(profile.acuteChronicRatio.map { acwr in acwr > 1.5 ? "↑ 高风险" : acwr > 1.2 ? "→ 中等" : "✓ 最佳" } ?? "—")
                    .font(.headline).foregroundColor(profile.acuteChronicRatio.map { $0 > 1.5 ? Color.red : $0 > 1.2 ? .orange : .green } ?? .secondary)
            }
        }
    }

    // MARK: - Sleep

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("睡眠与活动规律").font(AppTypography.title3)
            let recent = healthStore.dailySummaries.prefix(14)
            if #available(macOS 14.0, *), !recent.isEmpty {
                Chart {
                    ForEach(Array(recent), id: \.id) { s in
                        BarMark(x: .value("日期", s.dateFormatted), y: .value("睡眠", s.sleepHours))
                            .foregroundStyle(Color.indigo.opacity(0.5))
                    }
                    RuleMark(y: .value("推荐", 7)).foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(dash: [4,4]))
                }
                .chartXAxis { AxisMarks(values: .automatic) }
                .chartYAxis { AxisMarks { _ in AxisValueLabel(); AxisGridLine() } }
                .frame(height: 140)
                Text("图表：近 14 天睡眠时长（小时），虚线为 7 小时推荐值").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Workout Identity

    private var workoutIdentity: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("运动画像").font(AppTypography.title3)
            HStack(spacing: 6) {
                ForEach(profile.dominantWorkoutTypes, id: \.self) { t in
                    Text(t).font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08), in: Capsule())
                }
                if profile.dominantWorkoutTypes.isEmpty {
                    Text("运动数据不足").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Strengths & Constraints

    private var strengthsAndConstraints: some View {
        HStack(alignment: .top, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: 6) {
                Text("优势").font(AppTypography.title3).foregroundColor(.green)
                ForEach(profile.strengths, id: \.self) { s in
                    Label(s, systemImage: "checkmark.circle.fill").font(.callout).foregroundColor(.green)
                }
                if profile.strengths.isEmpty { Text("需要更多数据").font(.caption).foregroundColor(.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("限制因素").font(AppTypography.title3).foregroundColor(.orange)
                ForEach(profile.constraints, id: \.self) { c in
                    Label(c, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundColor(.orange)
                }
                if profile.constraints.isEmpty { Text("暂无显著限制").font(.caption).foregroundColor(.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("优化机会").font(AppTypography.title3).foregroundColor(.blue)
                ForEach(profile.opportunities, id: \.self) { o in
                    Label(o, systemImage: "lightbulb.fill").font(.callout).foregroundColor(.blue)
                }
                if profile.opportunities.isEmpty { Text("导入更多数据").font(.caption).foregroundColor(.secondary) }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("让 AI 教练分析").font(AppTypography.title3)
            HStack(spacing: AppSpacing.md) {
                coachButton("解释我的健康画像", "请基于我的健康画像，解释我当前最重要的身体状态、主要优势、主要限制因素，以及接下来最值得优化的方向。")
                coachButton("未来7天优化计划", "请基于我的健康画像和最近数据，给我制定未来7天的低风险运动与恢复优化计划。要求具体到每天的训练类型、强度、时长、恢复动作和注意事项。")
                coachButton("最大限制因素分析", "请基于我的健康画像，分析当前限制我健康状态和运动表现的最大因素，并给出优先级排序和改进方案。")
            }
        }
    }

    private func coachButton(_ label: String, _ question: String) -> some View {
        Button(action: {
            let runtime = AIRuntimeStatus()
            chatStore.createNewSession(runtime: runtime)
            aiCoordinator.ask(question: question, store: healthStore, chatStore: chatStore,
                              runtime: runtime, useDeepSeek: UserDefaults.standard.bool(forKey: "deepseek_enabled"))
        }) {
            Label(label, systemImage: "brain.head.profile")
        }
        .buttonStyle(.bordered)
        .disabled(aiCoordinator.state != .idle && aiCoordinator.state != .completed)
    }

    // MARK: - Helpers

    private func statusBadge(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private func baselineCard(_ title: String, _ value: String, _ unit: String, _ icon: String, _ color: Color) -> some View {
        CardView {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundColor(color).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundColor(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(value).font(.title3.weight(.medium))
                        Text(unit).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func metricPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.medium))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private func profileBar(_ label: String, score: Double) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 50, alignment: .leading).foregroundColor(.secondary)
            GeometryReader { g in
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(score > 0.7 ? .green : score > 0.4 ? .orange : .red)
                            .frame(width: g.size.width * score, height: 6)
                    }
            }.frame(width: 120, height: 6)
            Text("\(String(format: "%.0f", score * 100))%").font(.caption2).foregroundColor(.secondary).frame(width: 35, alignment: .trailing)
        }
    }

    private func tagColor(_ tag: String) -> Color {
        if tag.contains("有氧") || tag.contains("心肺") { return .blue }
        if tag.contains("力量") { return .red }
        if tag.contains("恢复") || tag.contains("睡眠") { return .orange }
        if tag.contains("重建") { return .purple }
        return .gray
    }

    private var dataSourceColor: Color {
        healthStore.dataSource == .appleHealthImport ? .green : healthStore.dataSource == .mockLive ? .orange : .gray
    }

    private var recoveryGradient: AngularGradient {
        AngularGradient(colors: [.green, .mint, .yellow, .orange, .red], center: .center)
    }
}
