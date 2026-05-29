import SwiftUI
import Charts

struct TrendChartCard: View {
    let summaries: [DailySummary]
    let metric: TrendMetric
    let range: TrendRange

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("\(metric.rawValue)趋势")
                        .font(AppTypography.title3)
                    Spacer()
                    Text("\(metric.unit)")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }

                // Summary stats
                HStack(spacing: AppSpacing.xl) {
                    StatBadge(
                        label: "平均值",
                        value: formattedAvg,
                        color: metric.color
                    )
                    StatBadge(
                        label: "最高",
                        value: formattedMax,
                        color: .green
                    )
                    StatBadge(
                        label: "最低",
                        value: formattedMin,
                        color: .orange
                    )

                    if let change = percentChange {
                        StatBadge(
                            label: "变化",
                            value: change,
                            color: change.contains("+") ? .green : .red
                        )
                    }
                }

                // Chart
                if #available(macOS 14.0, *) {
                    Chart {
                        ForEach(summaries, id: \.id) { summary in
                            LineMark(
                                x: .value("日期", summary.dateFormatted),
                                y: .value(metric.rawValue, valueForSummary(summary))
                            )
                            .foregroundStyle(metric.color.gradient)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("日期", summary.dateFormatted),
                                y: .value(metric.rawValue, valueForSummary(summary))
                            )
                            .foregroundStyle(metric.color.opacity(0.1).gradient)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: range == .sevenDays ? 7 : 6))
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                            AxisGridLine()
                        }
                    }
                    .frame(height: 250)
                }

                if summaries.isEmpty {
                    Text("暂无 \(range.rawValue) 数据")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
            }
        }
    }

    private func valueForSummary(_ summary: DailySummary) -> Double {
        switch metric {
        case .steps: return Double(summary.steps)
        case .sleep: return summary.sleepDurationSeconds / 3600
        case .restingHR: return summary.restingHeartRate
        case .hrv: return summary.heartRateVariability ?? 0
        case .activeEnergy: return summary.activeEnergyKJ
        case .exerciseMinutes: return Double(summary.exerciseMinutes)
        case .trainingLoad: return summary.trainingLoad
        case .recovery: return summary.recoveryScore
        }
    }

    private var values: [Double] {
        summaries.map(valueForSummary).filter { $0 > 0 }
    }

    private var formattedAvg: String {
        guard !values.isEmpty else { return "N/A" }
        let avg = values.reduce(0, +) / Double(values.count)
        return formatValue(avg)
    }

    private var formattedMax: String {
        guard let max = values.max() else { return "N/A" }
        return formatValue(max)
    }

    private var formattedMin: String {
        guard let min = values.min() else { return "N/A" }
        return formatValue(min)
    }

    private var percentChange: String? {
        guard values.count >= 2 else { return nil }
        let mid = values.count / 2
        let firstHalf = values.prefix(mid)
        let secondHalf = values.suffix(values.count - mid)
        let firstAvg = firstHalf.reduce(0, +) / max(Double(firstHalf.count), 1)
        let secondAvg = secondHalf.reduce(0, +) / max(Double(secondHalf.count), 1)
        guard firstAvg > 0 else { return nil }
        let change = (secondAvg - firstAvg) / firstAvg * 100
        return String(format: "%+.1f%%", change)
    }

    private func formatValue(_ value: Double) -> String {
        switch metric {
        case .steps: return String(format: "%.0f", value)
        case .sleep: return String(format: "%.1f", value)
        default: return String(format: "%.0f", value)
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(AppTypography.headline)
                .foregroundColor(color)
        }
    }
}
