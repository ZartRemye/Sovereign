import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var selectedTimeRange: TimeRange = .today

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                headerSection

                if healthStore.dailySummaries.isEmpty {
                    EmptyStateView(
                        systemImage: "heart.text.square",
                        title: "暂无健康数据",
                        message: "正在加载模拟数据或等待导入 Apple Health 数据。",
                        actionLabel: "导入数据",
                        action: { /* navigate to import */ }
                    )
                } else {
                    // Health status banner
                    statusBanner

                    // Metric cards grid
                    metricCardsGrid

                    // AI Insight
                    if !healthStore.healthInsights.isEmpty {
                        insightSection
                    }

                    // Recent 7 days trend
                    recentTrendSection
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("总览")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("健康总览")
                    .font(AppTypography.largeTitle)
                Text("\(formattedToday()) · 数据来源: \(healthStore.dataSource.rawValue)")
                    .font(AppTypography.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Picker("时间范围", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.xl) {
                // Recovery ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: healthStore.latestRecoveryScore / 100)
                        .stroke(recoveryColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(String(format: "%.0f", healthStore.latestRecoveryScore))")
                            .font(AppTypography.metricValue)
                        Text("恢复")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let today = healthStore.todaySummary {
                        Text("当前状态：\(today.healthStatus.rawValue)")
                            .font(AppTypography.title3)

                        HStack(spacing: AppSpacing.xl) {
                            VStack(alignment: .leading) {
                                Text("步数").font(AppTypography.caption).foregroundColor(.secondary)
                                Text("\(today.steps)").font(AppTypography.title2)
                            }
                            VStack(alignment: .leading) {
                                Text("睡眠").font(AppTypography.caption).foregroundColor(.secondary)
                                Text(today.sleepFormatted).font(AppTypography.title2)
                            }
                            VStack(alignment: .leading) {
                                Text("运动").font(AppTypography.caption).foregroundColor(.secondary)
                                Text("\(today.exerciseMinutes) 分钟").font(AppTypography.title2)
                            }
                        }
                    } else {
                        Text("数据加载中...")
                    }
                }
            }
        }
    }

    // MARK: - Metric Cards

    private var metricCardsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.lg) {
            if let today = healthStore.todaySummary {
                MetricCard(
                    title: "步数",
                    value: "\(today.steps)",
                    unit: "步",
                    systemImage: "figure.walk",
                    color: .mint
                )
                MetricCard(
                    title: "静息心率",
                    value: "\(String(format: "%.0f", today.restingHeartRate))",
                    unit: "bpm",
                    systemImage: "heart.fill",
                    color: .red
                )
                MetricCard(
                    title: "睡眠",
                    value: today.sleepFormatted,
                    unit: "",
                    systemImage: "moon.zzz.fill",
                    color: .indigo
                )
                MetricCard(
                    title: "活动能量",
                    value: "\(String(format: "%.0f", today.activeEnergyKJ))",
                    unit: "kJ",
                    systemImage: "flame.fill",
                    color: .orange
                )
                MetricCard(
                    title: "运动分钟",
                    value: "\(today.exerciseMinutes)",
                    unit: "分钟",
                    systemImage: "figure.run",
                    color: .green
                )
                MetricCard(
                    title: "训练负荷",
                    value: "\(String(format: "%.0f", today.trainingLoad))",
                    unit: "",
                    systemImage: "chart.bar.fill",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Insights

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("AI 今日洞察")
                .font(AppTypography.title2)

            ForEach(healthStore.healthInsights.prefix(3)) { insight in
                InsightCard(insight: insight)
            }
        }
    }

    // MARK: - Recent Trend

    private var recentTrendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("最近 7 天趋势")
                .font(AppTypography.title2)

            if #available(macOS 14.0, *) {
                let recentSummaries = healthStore.dailySummaries.prefix(7)
                Chart {
                    ForEach(Array(recentSummaries), id: \.id) { summary in
                        LineMark(
                            x: .value("日期", summary.dateFormatted),
                            y: .value("恢复评分", summary.recoveryScore)
                        )
                        .foregroundStyle(.blue.gradient)

                        PointMark(
                            x: .value("日期", summary.dateFormatted),
                            y: .value("恢复评分", summary.recoveryScore)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic) }
                .chartYAxis { AxisMarks { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }}
                .frame(height: 180)
                .padding(.top, AppSpacing.sm)
            } else {
                Text("Swift Charts 需要 macOS 14+")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var recoveryColor: Color {
        let score = healthStore.latestRecoveryScore
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func formattedToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "7天"
    case month = "30天"

    var id: String { rawValue }
}
