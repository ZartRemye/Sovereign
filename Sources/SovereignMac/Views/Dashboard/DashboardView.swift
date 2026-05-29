import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var healthStore: MacHealthStore

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                headerSection

                if healthStore.dataSource == .empty {
                    emptyStateView
                } else {
                    // Status banner
                    statusBanner

                    // Core metrics — 4 key cards
                    coreMetricsRow

                    // Insights — up to 3
                    if !healthStore.healthInsights.isEmpty {
                        insightSection
                    }

                    // Alerts summary
                    if !healthStore.alerts.filter({ !$0.isDismissed }).isEmpty {
                        alertsSection
                    }

                    // Recent trend
                    recentTrendSection
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("概览")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.xl) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.4))

            VStack(spacing: AppSpacing.sm) {
                Text("No health data yet")
                    .font(AppTypography.title2)
                Text("Import your Apple Health export to start analysis.")
                    .font(AppTypography.callout)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: AppSpacing.md) {
                Button("导入 Apple Health 数据") {
                    NotificationCenter.default.post(name: NSNotification.Name("NavigateToImport"), object: nil)
                }
                .buttonStyle(.borderedProminent)

                Button("加载 Demo 数据") {
                    Task { await healthStore.loadMockData() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sovereign")
                    .font(AppTypography.largeTitle)
                HStack(spacing: 8) {
                    DataSourceBadge(source: healthStore.dataSource)
                    if let diag = healthStore.lastImportDiagnostic {
                        Text("· 导入于 \(diag.importTime, style: .relative)前")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.xxl) {
                // Recovery score ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 6)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: min(healthStore.latestRecoveryScore / 100, 1.0))
                        .stroke(recoveryColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(String(format: "%.0f", healthStore.latestRecoveryScore))")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("恢复")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("今日状态")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    if let today = healthStore.todaySummary {
                        Text(today.healthStatus.rawValue)
                            .font(AppTypography.title2)
                    } else {
                        Text("数据不足")
                            .font(AppTypography.title2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: AppSpacing.xl) {
                        metricLabel("步数", "\(healthStore.todaySummary?.steps ?? 0)")
                        metricLabel("睡眠", healthStore.todaySummary?.sleepFormatted ?? "—")
                        metricLabel("静息心率", healthStore.todaySummary?.restingHeartRate ?? 0 > 0 ? "\(Int(healthStore.todaySummary?.restingHeartRate ?? 0)) bpm" : "—")
                    }
                }
            }
        }
    }

    // MARK: - Core Metrics (4 cards)

    private var coreMetricsRow: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.lg) {
            if let today = healthStore.todaySummary {
                MetricCardCompact(
                    title: "恢复评分",
                    value: "\(Int(today.recoveryScore))",
                    unit: "/100",
                    systemImage: "arrow.triangle.2.circlepath",
                    color: recoveryScoreColor(today.recoveryScore)
                )
                MetricCardCompact(
                    title: "训练负荷",
                    value: "\(Int(today.trainingLoad))",
                    unit: "pts",
                    systemImage: "chart.bar.fill",
                    color: .blue
                )
                MetricCardCompact(
                    title: "睡眠时长",
                    value: today.sleepFormatted,
                    unit: "",
                    systemImage: "moon.zzz.fill",
                    color: today.sleepHours >= 7 ? .mint : .orange
                )
                MetricCardCompact(
                    title: "运动分钟",
                    value: "\(today.exerciseMinutes)",
                    unit: "min",
                    systemImage: "figure.run",
                    color: .green
                )
            }
        }
    }

    // MARK: - Insights

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("关键洞察")
                .font(AppTypography.title3)

            ForEach(healthStore.healthInsights.prefix(3)) { insight in
                InsightCard(insight: insight)
            }
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("提醒")
                .font(AppTypography.title3)

            let activeAlerts = healthStore.alerts.filter { !$0.isDismissed }.prefix(3)
            ForEach(Array(activeAlerts), id: \.id) { alert in
                AlertCard(alert: alert, onDismiss: {})
            }
        }
    }

    // MARK: - Trend

    private var recentTrendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("最近 7 天恢复趋势")
                .font(AppTypography.title3)

            if #available(macOS 14.0, *) {
                let recentSummaries = healthStore.dailySummaries.prefix(7)
                Chart {
                    ForEach(Array(recentSummaries), id: \.id) { summary in
                        LineMark(
                            x: .value("日期", summary.dateFormatted),
                            y: .value("恢复评分", summary.recoveryScore)
                        )
                        .foregroundStyle(.blue.gradient)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("日期", summary.dateFormatted),
                            y: .value("恢复评分", summary.recoveryScore)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic) }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 160)
            } else {
                Text("Swift Charts 需要 macOS 14+")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func metricLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppTypography.headline)
            Text(title)
                .font(AppTypography.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var recoveryColor: Color {
        let score = healthStore.latestRecoveryScore
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func recoveryScoreColor(_ score: Double) -> Color {
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }
}

// MARK: - Compact Metric Card

struct MetricCardCompact: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let color: Color

    var body: some View {
        CardView {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(value)
                            .font(AppTypography.title2)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(title)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Time Range (if needed elsewhere)

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "7天"
    case month = "30天"

    var id: String { rawValue }
}
