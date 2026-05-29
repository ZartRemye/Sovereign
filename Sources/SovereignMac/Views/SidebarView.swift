import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    @EnvironmentObject var healthStore: MacHealthStore

    var body: some View {
        List(selection: $selectedTab) {
            Section("分析") {
                ForEach([NavigationTab.overview, .trends, .recovery, .workouts], id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }

            Section("AI") {
                Label(NavigationTab.coach.rawValue, systemImage: NavigationTab.coach.systemImage)
                    .tag(NavigationTab.coach)
            }

            Section("数据") {
                Label(NavigationTab.importData.rawValue, systemImage: NavigationTab.importData.systemImage)
                    .tag(NavigationTab.importData)
                Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.systemImage)
                    .tag(NavigationTab.settings)
            }

            Section("状态") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dataSourceColor)
                            .frame(width: 7, height: 7)
                        Text(dataSourceText)
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }

                    if !healthStore.dailySummaries.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(healthStore.dbSummaryCount) 天摘要")
                                .font(AppTypography.caption2)
                                .foregroundColor(.secondary)
                            Text("\(healthStore.dbWorkoutCount) 次运动")
                                .font(AppTypography.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let lastAnalysis = healthStore.lastAnalysisDate {
                        Text("分析于 \(formatRelative(lastAnalysis))")
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
        case .empty: return .gray
        case .mockLive: return .orange
        case .appleHealthImport: return .green
        case .iphoneSync: return .blue
        case .watchLive: return .purple
        case .unknown: return .gray
        }
    }

    private var dataSourceText: String {
        switch healthStore.dataSource {
        case .empty: return "无数据"
        case .mockLive: return "Demo Data"
        case .appleHealthImport: return "Apple Health"
        case .iphoneSync: return "iPhone Sync"
        case .watchLive: return "Watch Live"
        case .unknown: return "未知"
        }
    }

    private func formatRelative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
