import SwiftUI
import Charts

struct LiveMonitorView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var currentHR: Double = 68
    @State private var currentSteps: Int = 0
    @State private var isInWorkout: Bool = false
    @State private var lastUpdate: Date = Date()
    @State private var hrHistory: [Double] = Array(repeating: 65, count: 30)
    @State private var dataSourceStatus: String = "Mock Live"

    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("实时监控")
                            .font(AppTypography.largeTitle)
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("数据源: \(dataSourceStatus) · 每5秒更新")
                                .font(AppTypography.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()

                    Text("最近更新: \(timeFormatter.string(from: lastUpdate))")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }

                // Heart rate live
                LiveHeartRateCard(heartRate: currentHR, history: hrHistory, isInWorkout: isInWorkout)

                // Status rings row
                HStack(spacing: AppSpacing.lg) {
                    LiveStatusRing(
                        title: "恢复状态",
                        value: healthStore.latestRecoveryScore,
                        maxValue: 100,
                        color: recoveryColor
                    )

                    LiveStatusRing(
                        title: "今日步数",
                        value: Double(currentSteps),
                        maxValue: 10000,
                        color: .mint
                    )

                    LiveStatusRing(
                        title: "运动状态",
                        value: isInWorkout ? 1 : 0,
                        maxValue: 1,
                        color: isInWorkout ? .orange : .gray,
                        valueFormatter: { $0 > 0 ? "运动中" : "静止" }
                    )
                }

                // HR zone
                hrZoneCard

                // HR trend (last 30 min)
                hrTrendCard

                // Data source status
                dataSourceStatusCard
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("实时监控")
        .onReceive(timer) { _ in
            Task { await updateLiveData() }
        }
    }

    private func updateLiveData() async {
        let mock = MockHealthDataProvider.shared
        currentHR = await mock.generateLiveHeartRate()
        currentSteps = await mock.generateLiveSteps()
        isInWorkout = currentHR > 90

        // Update HR history (rolling window of 30 readings = ~2.5 min at 5s intervals)
        hrHistory.append(currentHR)
        if hrHistory.count > 30 { hrHistory.removeFirst() }

        lastUpdate = Date()
    }

    private var hrZoneCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("心率区间")
                    .font(AppTypography.title3)

                HStack(spacing: 0) {
                    HRZoneBar(zone: "静息", range: "<60", color: .gray, widthPercent: 0.2)
                    HRZoneBar(zone: "脂肪", range: "60-100", color: .blue, widthPercent: 0.3)
                    HRZoneBar(zone: "有氧", range: "100-140", color: .green, widthPercent: 0.25)
                    HRZoneBar(zone: "无氧", range: "140-170", color: .orange, widthPercent: 0.15)
                    HRZoneBar(zone: "极限", range: ">170", color: .red, widthPercent: 0.1)
                }
                .frame(height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    ForEach(["静息", "脂肪燃烧", "有氧", "无氧", "极限"], id: \.self) { zone in
                        Circle()
                            .fill(zoneColor(zone))
                            .frame(width: 6, height: 6)
                        Text(zone)
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var hrTrendCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("心率趋势 (最近更新)")
                    .font(AppTypography.title3)

                if #available(macOS 14.0, *) {
                    Chart {
                        ForEach(Array(hrHistory.enumerated()), id: \.offset) { index, hr in
                            LineMark(
                                x: .value("时间", index),
                                y: .value("心率", hr)
                            )
                            .foregroundStyle(.red.gradient)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                            AxisGridLine()
                        }
                    }
                    .frame(height: 120)
                }

                HStack {
                    Text("最低: \(String(format: "%.0f", hrHistory.min() ?? 0)) bpm")
                        .font(AppTypography.caption)
                    Spacer()
                    Text("最高: \(String(format: "%.0f", hrHistory.max() ?? 0)) bpm")
                        .font(AppTypography.caption)
                    Spacer()
                    Text("当前: \(String(format: "%.0f", currentHR)) bpm")
                        .font(AppTypography.caption.weight(.bold))
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var dataSourceStatusCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("数据源状态")
                    .font(AppTypography.title3)

                VStack(spacing: AppSpacing.sm) {
                    DataSourceRow(name: "Mock Live", status: "活跃", isConnected: true)
                    DataSourceRow(name: "Apple Health Import", status: healthStore.dataSource == .appleHealthImport ? "已导入" : "未导入", isConnected: healthStore.dataSource == .appleHealthImport)
                    DataSourceRow(name: "iPhone Sync", status: "未来启用", isConnected: false, isFuture: true)
                    DataSourceRow(name: "Watch Live", status: "未来启用", isConnected: false, isFuture: true)
                }
            }
        }
    }

    private var recoveryColor: Color {
        let score = healthStore.latestRecoveryScore
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private func zoneColor(_ zone: String) -> Color {
        switch zone {
        case "静息": return .gray
        case "脂肪燃烧": return .blue
        case "有氧": return .green
        case "无氧": return .orange
        case "极限": return .red
        default: return .gray
        }
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - Sub-views

struct HRZoneBar: View {
    let zone: String
    let range: String
    let color: Color
    let widthPercent: Double

    var body: some View {
        color.frame(width: max(CGFloat(widthPercent) * 300, 30))
    }
}

struct DataSourceRow: View {
    let name: String
    let status: String
    let isConnected: Bool
    var isFuture: Bool = false

    var body: some View {
        HStack {
            Circle()
                .fill(isFuture ? Color.gray.opacity(0.3) : (isConnected ? Color.green : Color.gray))
                .frame(width: 8, height: 8)
            Text(name)
                .font(AppTypography.callout)
            Spacer()
            Text(status)
                .font(AppTypography.caption)
                .foregroundColor(isFuture ? .secondary.opacity(0.5) : .secondary)
        }
    }
}
