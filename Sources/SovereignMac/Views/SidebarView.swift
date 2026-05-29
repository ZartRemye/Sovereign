import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    @EnvironmentObject var healthStore: MacHealthStore

    var body: some View {
        List(selection: $selectedTab) {
            Section("健康数据") {
                ForEach([NavigationTab.dashboard, .liveMonitor, .trends, .sleep, .workouts], id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }

            Section("分析") {
                ForEach([NavigationTab.coach, .reports, .alerts], id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }

            Section("数据管理") {
                Label(NavigationTab.importData.rawValue, systemImage: NavigationTab.importData.systemImage)
                    .tag(NavigationTab.importData)
                Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.systemImage)
                    .tag(NavigationTab.settings)
            }

            Section("状态") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(dataSourceColor)
                            .frame(width: 8, height: 8)
                        Text("数据源: \(healthStore.dataSource.rawValue)")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                    if let lastAnalysis = healthStore.lastAnalysisDate {
                        Text("最近分析: \(formatRelative(lastAnalysis))")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
    }

    private var dataSourceColor: Color {
        switch healthStore.dataSource {
        case .mockLive: return .orange
        case .appleHealthImport: return .green
        case .iphoneSync: return .blue
        case .watchLive: return .purple
        case .unknown: return .gray
        }
    }

    private func formatRelative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
