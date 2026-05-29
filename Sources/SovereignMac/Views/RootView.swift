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
        case .overview:   DashboardView()
        case .profile:    ProfileView()
        case .trends:     TrendsView()
        case .recovery:   SleepRecoveryView()
        case .workouts:   WorkoutsView()
        case .coach:      AICoachView()
        case .importData: ImportView()
        case .settings:   SettingsView()
        }
    }
}

enum NavigationTab: String, Identifiable, CaseIterable {
    case overview = "概览"
    case profile = "画像"
    case trends = "趋势"
    case recovery = "恢复"
    case workouts = "运动"
    case coach = "AI 教练"
    case importData = "数据导入"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: "heart.text.square"
        case .profile: "person.fill.viewfinder"
        case .trends: "chart.xyaxis.line"
        case .recovery: "moon.zzz.fill"
        case .workouts: "figure.run"
        case .coach: "brain.head.profile"
        case .importData: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }
}
