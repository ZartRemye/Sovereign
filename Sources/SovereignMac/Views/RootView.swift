import SwiftUI

struct RootView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var selectedTab: NavigationTab = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            contentView
                .frame(minWidth: AppSpacing.detailMinWidth)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .liveMonitor:
            LiveMonitorView()
        case .trends:
            TrendsView()
        case .sleep:
            SleepRecoveryView()
        case .workouts:
            WorkoutsView()
        case .coach:
            AICoachView()
        case .reports:
            ReportsView()
        case .alerts:
            AlertsView()
        case .importData:
            ImportView()
        case .settings:
            SettingsView()
        }
    }
}

enum NavigationTab: String, Identifiable, CaseIterable {
    case dashboard = "总览"
    case liveMonitor = "实时监控"
    case trends = "趋势分析"
    case sleep = "睡眠恢复"
    case workouts = "运动分析"
    case coach = "AI 教练"
    case reports = "健康报告"
    case alerts = "提醒"
    case importData = "数据导入"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .liveMonitor: return "waveform.path.ecg"
        case .trends: return "chart.xyaxis.line"
        case .sleep: return "moon.zzz.fill"
        case .workouts: return "figure.run"
        case .coach: return "bubble.left.and.text.bubble.right"
        case .reports: return "doc.text"
        case .alerts: return "bell.badge"
        case .importData: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}
