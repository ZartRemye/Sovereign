import SwiftUI

struct DataSettingsView: View {
    @State private var backgroundAnalysisEnabled: Bool = UserDefaults.standard.bool(forKey: "analysis_enabled")
    @State private var analysisInterval: Int = UserDefaults.standard.integer(forKey: "analysis_interval")
    @State private var notificationsEnabled: Bool = UserDefaults.standard.bool(forKey: "notifications_enabled")
    @State private var useMockData: Bool = UserDefaults.standard.bool(forKey: "use_mock_data")
    @State private var autoDailyReport: Bool = UserDefaults.standard.bool(forKey: "auto_daily_report")
    @State private var autoWeeklyReport: Bool = UserDefaults.standard.bool(forKey: "auto_weekly_report")
    @State private var showClearConfirmation = false
    @State private var clearTarget: ClearTarget = .demoData

    @EnvironmentObject var healthStore: MacHealthStore

    enum ClearTarget {
        case demoData, importedData, allData
    }

    init() {
        if UserDefaults.standard.object(forKey: "analysis_interval") == nil {
            UserDefaults.standard.set(15, forKey: "analysis_interval")
        }
        if UserDefaults.standard.object(forKey: "analysis_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "analysis_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_enabled")
        }
        if UserDefaults.standard.object(forKey: "use_mock_data") == nil {
            UserDefaults.standard.set(false, forKey: "use_mock_data") // Default to OFF
        }
        if UserDefaults.standard.object(forKey: "auto_daily_report") == nil {
            UserDefaults.standard.set(true, forKey: "auto_daily_report")
        }
    }

    var body: some View {
        Form {
            Section("后台分析") {
                Toggle("启用后台分析", isOn: $backgroundAnalysisEnabled)
                    .onChange(of: backgroundAnalysisEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "analysis_enabled")
                        if newValue {
                            BackgroundAnalysisScheduler.shared.start()
                        } else {
                            BackgroundAnalysisScheduler.shared.stop()
                        }
                    }

                Picker("分析频率", selection: $analysisInterval) {
                    Text("每 5 分钟").tag(5)
                    Text("每 15 分钟").tag(15)
                    Text("每 30 分钟").tag(30)
                    Text("每 1 小时").tag(60)
                }
                .onChange(of: analysisInterval) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "analysis_interval")
                    BackgroundAnalysisScheduler.shared.updateInterval(newValue)
                }

                if let lastAnalysis = healthStore.lastAnalysisDate {
                    Text("最近分析: \(lastAnalysis, style: .relative)前")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("通知") {
                Toggle("启用通知", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "notifications_enabled")
                    }

                Text("包括睡眠不足、恢复偏低、训练负荷过高、长时间不活动等提醒。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("开发与演示") {
                Toggle("允许加载 Demo 数据", isOn: $useMockData)
                    .onChange(of: useMockData) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "use_mock_data")
                    }
                Text("Demo 数据仅在没有任何真实数据时才会被加载。App 启动时会自动检测。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("加载 Demo 数据") {
                    Task { await healthStore.loadMockData() }
                }
                .disabled(healthStore.dataSource == .appleHealthImport)
                .buttonStyle(.bordered)
                Text("所有 Demo 数据会在 UI 中明确标记为「Demo Data」。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("当前数据状态") {
                HStack {
                    Text("数据源")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dataSourceColor)
                            .frame(width: 8, height: 8)
                        Text(healthStore.dataSource.rawValue)
                    }
                    .foregroundColor(.secondary)
                }
                HStack {
                    Text("指标样本")
                    Spacer()
                    Text("\(healthStore.dbMetricCount) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("运动记录")
                    Spacer()
                    Text("\(healthStore.dbWorkoutCount) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("睡眠记录")
                    Spacer()
                    Text("\(healthStore.dbSleepCount) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("每日摘要")
                    Spacer()
                    Text("\(healthStore.dbSummaryCount) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("活跃洞察")
                    Spacer()
                    Text("\(healthStore.healthInsights.count) 条")
                        .foregroundColor(.secondary)
                }
            }

            Section("数据管理") {
                Button("清空 Demo 数据") {
                    clearTarget = .demoData
                    showClearConfirmation = true
                }
                .disabled(healthStore.dataSource != .mockLive)
                .buttonStyle(.bordered)

                Button("清空已导入数据") {
                    clearTarget = .importedData
                    showClearConfirmation = true
                }
                .disabled(!healthStore.hasRealData)
                .buttonStyle(.bordered)

                Button("重建每日摘要") {
                    Task { await healthStore.rebuildDailySummaries() }
                }
                .buttonStyle(.bordered)
                .disabled(!healthStore.hasAnyData)

                Button("清空所有数据", role: .destructive) {
                    clearTarget = .allData
                    showClearConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(!healthStore.hasAnyData)
            }
            .alert("确认清空", isPresented: $showClearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("确认清空", role: .destructive) {
                    Task {
                        switch clearTarget {
                        case .demoData: await healthStore.clearDemoData()
                        case .importedData: await healthStore.clearImportedData()
                        case .allData: await healthStore.clearAllData()
                        }
                    }
                }
            } message: {
                switch clearTarget {
                case .demoData:
                    Text("将删除所有 Demo 演示数据。如有已导入的真实数据，将保留。")
                case .importedData:
                    Text("将删除所有 Apple Health 导入数据，包括指标、运动、睡眠记录和每日摘要。Demo 数据不受影响。")
                case .allData:
                    Text("将删除所有数据（Demo 和导入数据）。此操作不可撤销。")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dataSourceColor: Color {
        switch healthStore.dataSource {
        case .empty: return .gray
        case .mockLive: return .orange
        case .appleHealthImport: return .green
        case .iphoneSync: return .blue
        case .watchLive: return .purple
        case .unknown: return .gray
        }
    }
}
