import SwiftUI
import SwiftData

struct TrendsView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var selectedRange: TrendRange = .thirtyDays
    @State private var selectedMetric: TrendMetric = .steps

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("趋势分析")
                            .font(AppTypography.largeTitle)
                        Text("基于 \(selectedRange.rawValue) 数据")
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    Picker("时间范围", selection: $selectedRange) {
                        ForEach(TrendRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                // Metric selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(TrendMetric.allCases) { metric in
                            TrendMetricChip(
                                metric: metric,
                                isSelected: selectedMetric == metric,
                                action: { selectedMetric = metric }
                            )
                        }
                    }
                }

                // Main chart
                TrendChartCard(
                    summaries: filteredSummaries,
                    metric: selectedMetric,
                    range: selectedRange
                )
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("趋势分析")
    }

    private var filteredSummaries: [DailySummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = selectedRange.days
        let startDate = calendar.date(byAdding: .day, value: -days, to: today)!

        return healthStore.dailySummaries
            .filter { $0.date >= startDate }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Trend Types

enum TrendRange: String, CaseIterable, Identifiable {
    case sevenDays = "7天"
    case thirtyDays = "30天"
    case ninetyDays = "90天"

    var id: String { rawValue }
    var days: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case steps = "步数"
    case sleep = "睡眠"
    case restingHR = "静息心率"
    case hrv = "HRV"
    case activeEnergy = "活动能量"
    case exerciseMinutes = "运动分钟"
    case trainingLoad = "训练负荷"
    case recovery = "恢复评分"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .sleep: return "moon.zzz"
        case .restingHR: return "heart"
        case .hrv: return "waveform.path"
        case .activeEnergy: return "flame"
        case .exerciseMinutes: return "figure.run"
        case .trainingLoad: return "chart.bar"
        case .recovery: return "arrow.triangle.2.circlepath"
        }
    }
    var color: Color {
        switch self {
        case .steps: return .mint
        case .sleep: return .indigo
        case .restingHR: return .red
        case .hrv: return .teal
        case .activeEnergy: return .orange
        case .exerciseMinutes: return .green
        case .trainingLoad: return .blue
        case .recovery: return .purple
        }
    }
    var unit: String {
        switch self {
        case .steps: return "步"
        case .sleep: return "小时"
        case .restingHR: return "bpm"
        case .hrv: return "ms"
        case .activeEnergy: return "kJ"
        case .exerciseMinutes: return "分钟"
        case .trainingLoad: return ""
        case .recovery: return "/100"
        }
    }
}

// MARK: - Metric Chip

struct TrendMetricChip: View {
    let metric: TrendMetric
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(metric.rawValue, systemImage: metric.systemImage)
                .font(AppTypography.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? metric.color.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundColor(isSelected ? metric.color : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
