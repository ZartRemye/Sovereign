import SwiftUI

struct DataSettingsView: View {
    @State private var backgroundAnalysisEnabled: Bool = UserDefaults.standard.bool(forKey: "analysis_enabled")
    @State private var analysisInterval: Int = UserDefaults.standard.integer(forKey: "analysis_interval")
    @State private var notificationsEnabled: Bool = UserDefaults.standard.bool(forKey: "notifications_enabled")
    @State private var useMockData: Bool = UserDefaults.standard.bool(forKey: "use_mock_data")
    @State private var autoDailyReport: Bool = UserDefaults.standard.bool(forKey: "auto_daily_report")
    @State private var autoWeeklyReport: Bool = UserDefaults.standard.bool(forKey: "auto_weekly_report")

    @EnvironmentObject var healthStore: MacHealthStore

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
            UserDefaults.standard.set(true, forKey: "use_mock_data")
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

                Text("包括睡眠不足、恢复偏低、训练负荷过高、长时间不活动、AI 分析失败等提醒。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("数据") {
                Toggle("使用 Mock Live 数据", isOn: $useMockData)
                    .onChange(of: useMockData) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "use_mock_data")
                        if newValue {
                            Task { await healthStore.loadMockData() }
                        }
                    }

                Toggle("自动生成日报", isOn: $autoDailyReport)
                    .onChange(of: autoDailyReport) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "auto_daily_report")
                    }

                Toggle("自动生成周报", isOn: $autoWeeklyReport)
                    .onChange(of: autoWeeklyReport) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "auto_weekly_report")
                    }
            }

            Section("当前数据状态") {
                HStack {
                    Text("数据源")
                    Spacer()
                    Text(healthStore.dataSource.rawValue)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("每日摘要")
                    Spacer()
                    Text("\(healthStore.dailySummaries.count) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("运动记录")
                    Spacer()
                    Text("\(healthStore.recentWorkouts.count) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("睡眠记录")
                    Spacer()
                    Text("\(healthStore.recentSleep.count) 条")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("活跃洞察")
                    Spacer()
                    Text("\(healthStore.healthInsights.count) 条")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
