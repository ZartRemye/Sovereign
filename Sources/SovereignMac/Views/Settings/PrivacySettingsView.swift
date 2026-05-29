import SwiftUI

struct PrivacySettingsView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var showClearConfirmation = false
    @State private var showExportSuccess = false

    var body: some View {
        Form {
            Section {
                Label("原始健康数据仅保存在本地", systemImage: "lock.shield.fill")
                    .foregroundColor(.green)
                Label("发送给 DeepSeek 的仅是匿名摘要", systemImage: "text.magnifyingglass")
                    .foregroundColor(.green)
                Label("不会上传完整原始数据", systemImage: "hand.raised.fill")
                    .foregroundColor(.green)
                Label("AI 分析不是医疗诊断", systemImage: "stethoscope")
                    .foregroundColor(.secondary)
            } header: {
                Text("数据隐私")
            }

            Section("数据管理") {
                Button("清空所有本地数据") {
                    showClearConfirmation = true
                }
                .foregroundColor(.red)

                Button("导出本地数据为 JSON") {
                    exportData()
                }

                if showExportSuccess {
                    Text("数据已导出")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Section("免责声明") {
                Text("Sovereign 不是医疗设备，不提供医疗诊断。所有恢复评分、训练建议和 AI 分析均基于行为数据模式分析，仅供个人参考。如有健康疑虑，请咨询持证医生。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("确认清空数据", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task { await healthStore.clearAllData() }
            }
        } message: {
            Text("这将删除所有本地健康数据。此操作不可撤销。")
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Sovereign_Export_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)).json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let export: [String: Any] = [
                    "exportDate": Date().ISO8601Format(),
                    "summaryCount": healthStore.dailySummaries.count,
                    "workoutCount": healthStore.recentWorkouts.count,
                    "sleepSessionCount": healthStore.recentSleep.count,
                ]
                if let json = try? JSONSerialization.data(withJSONObject: export, options: .prettyPrinted) {
                    try? json.write(to: url)
                    showExportSuccess = true
                }
            }
        }
    }
}
