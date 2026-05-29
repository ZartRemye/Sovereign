import SwiftUI

struct RootView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var selectedTab: NavigationTab = .overview

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            contentView
                .frame(minWidth: AppSpacing.detailMinWidth)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .overview:
            DashboardView()
        case .trends:
            TrendsView()
        case .recovery:
            SleepRecoveryView()
        case .workouts:
            WorkoutsView()
        case .coach:
            AICoachView()
        case .importData:
            ImportView()
        case .settings:
            SettingsView()
        }
    }
}

enum NavigationTab: String, Identifiable, CaseIterable {
    case overview = "概览"
    case trends = "趋势"
    case recovery = "恢复"
    case workouts = "运动"
    case coach = "AI 教练"
    case importData = "数据导入"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "heart.text.square"
        case .trends: return "chart.xyaxis.line"
        case .recovery: return "moon.zzz.fill"
        case .workouts: return "figure.run"
        case .coach: return "brain.head.profile"
        case .importData: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}
