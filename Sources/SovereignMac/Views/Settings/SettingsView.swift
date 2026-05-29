import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var healthStore: MacHealthStore

    private enum SettingsTab: String, CaseIterable {
        case ai = "AI 设置"
        case privacy = "隐私"
        case analysis = "数据分析"

        var systemImage: String {
            switch self {
            case .ai: return "brain"
            case .privacy: return "hand.raised"
            case .analysis: return "gearshape.2"
            }
        }
    }

    var body: some View {
        TabView {
            AISettingsView()
                .tabItem { Label("AI 设置", systemImage: "brain") }

            PrivacySettingsView()
                .tabItem { Label("隐私", systemImage: "hand.raised") }

            DataSettingsView()
                .tabItem { Label("数据分析", systemImage: "gearshape.2") }
        }
        .frame(width: 500, height: 450)
    }
}
