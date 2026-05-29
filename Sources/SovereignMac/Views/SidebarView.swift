import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    @EnvironmentObject var healthStore: MacHealthStore
    @StateObject private var importCoordinator = ImportCoordinator.shared
    @State private var runtimeStatus: AIRuntimeStatus = AIRuntimeStatus()

    var body: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach([NavigationTab.overview, .profile, .trends, .recovery, .workouts], id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }

            Section {
                Label(NavigationTab.coach.rawValue, systemImage: NavigationTab.coach.systemImage)
                    .tag(NavigationTab.coach)
            }

            Section {
                Label(NavigationTab.importData.rawValue, systemImage: NavigationTab.importData.systemImage)
                    .tag(NavigationTab.importData)
                Label(NavigationTab.settings.rawValue, systemImage: NavigationTab.settings.systemImage)
                    .tag(NavigationTab.settings)
            }

            Section {
                statusFooter
            }
        }
        .listStyle(.sidebar)
        .task {
            runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries)
        }
        .onChange(of: healthStore.dataSource) { _ in
            Task { runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries) }
        }
    }

    // MARK: - Status Footer

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Data source
            HStack(spacing: 5) {
                Circle().fill(dataSourceColor).frame(width: 6, height: 6)
                Text(dataSourceLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Import
            if importCoordinator.isImporting {
                HStack(spacing: 5) {
                    ProgressView().scaleEffect(0.55).frame(width: 10, height: 10)
                    Text("Import \(importCoordinator.progress.percentComplete)%")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }

            // AI mode
            HStack(spacing: 5) {
                Circle().fill(aiModeColor).frame(width: 6, height: 6)
                Text("AI: \(runtimeStatus.providerMode.shortLabel)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Summary counts
            if healthStore.dbSummaryCount > 0 {
                Text("\(healthStore.dbSummaryCount)d · \(healthStore.dbWorkoutCount) workouts")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }

    private var dataSourceColor: Color {
        switch healthStore.dataSource {
        case .empty: .gray; case .mockLive: .orange; case .appleHealthImport: .green
        case .iphoneSync: .blue; case .watchLive: .purple; default: .gray
        }
    }

    private var dataSourceLabel: String {
        switch healthStore.dataSource {
        case .empty: "Empty"; case .mockLive: "Demo"; case .appleHealthImport: "Apple Health"
        case .iphoneSync: "iPhone"; case .watchLive: "Watch"; default: "Unknown"
        }
    }

    private var aiModeColor: Color {
        switch runtimeStatus.providerMode {
        case .localRules: .blue; case .deepSeek: .purple; case .fallback: .orange; case .disabled: .gray
        }
    }
}
