import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: NavigationTab
    @EnvironmentObject var healthStore: MacHealthStore
    @StateObject private var importCoordinator = ImportCoordinator.shared
    @State private var runtimeStatus: AIRuntimeStatus = AIRuntimeStatus()

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

            Section("Status") {
                // Data source
                HStack(spacing: 6) {
                    Circle()
                        .fill(dataSourceColor)
                        .frame(width: 7, height: 7)
                    Text("Data: \(dataSourceLabel)")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }

                // Import status
                if importCoordinator.isImporting {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Import: \(importCoordinator.progress.percentComplete)%")
                                .font(AppTypography.caption)
                                .foregroundColor(.accentColor)
                        }
                        Text("\(importCoordinator.progress.formattedProcessedSize) / \(importCoordinator.progress.formattedTotalSize)")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if case .completed = importCoordinator.state {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("Import: Completed")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                } else if case .failed = importCoordinator.state {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text("Import: Failed")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text("Import: Idle")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // AI mode
                HStack(spacing: 6) {
                    Circle()
                        .fill(aiModeColor)
                        .frame(width: 7, height: 7)
                    Text("AI: \(runtimeStatus.providerMode.shortLabel)")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }

                // Data counts
                if !healthStore.dailySummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(healthStore.dbSummaryCount) days · \(healthStore.dbWorkoutCount) workouts")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let lastAnalysis = healthStore.lastAnalysisDate {
                    Text("Analyzed \(formatRelative(lastAnalysis))")
                        .font(AppTypography.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .task {
            runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries)
        }
        .onChange(of: healthStore.dataSource) { _ in
            Task {
                runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries)
            }
        }
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

    private var dataSourceLabel: String {
        switch healthStore.dataSource {
        case .empty: return "Empty"
        case .mockLive: return "Demo"
        case .appleHealthImport: return "Apple Health"
        case .iphoneSync: return "iPhone"
        case .watchLive: return "Watch"
        case .unknown: return "Unknown"
        }
    }

    private var aiModeColor: Color {
        switch runtimeStatus.providerMode {
        case .localRules: return .blue
        case .deepSeek: return .purple
        case .fallback: return .orange
        case .disabled: return .gray
        }
    }

    private func formatRelative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
