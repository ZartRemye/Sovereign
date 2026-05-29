import SwiftUI
import SwiftData

@main
struct SovereignMacApp: App {
    @StateObject private var healthStore = MacHealthStore.shared

    let container: ModelContainer = {
        let schema = Schema([
            HealthMetricSample.self,
            WorkoutSession.self,
            SleepSession.self,
            DailySummary.self,
            RecoveryScoreRecord.self,
            TrainingLoadRecord.self,
            HealthInsight.self,
            AlertRecord.self,
            AIAnalysisCache.self,
            ImportDiagnostic.self,
        ])
        return try! ModelContainer(for: schema)
    }()

    var body: some Scene {
        // MARK: - Main Window
        Window("Sovereign", id: "main") {
            RootView()
                .environmentObject(healthStore)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    healthStore.configure(with: container.mainContext)
                    BackgroundAnalysisScheduler.shared.configure(store: healthStore)
                    BackgroundAnalysisScheduler.shared.start()
                    Task {
                        await healthStore.refresh()
                        // Only load mock data if no real data exists AND user hasn't explicitly disabled it
                        if healthStore.dataSource == .empty {
                            let useMock = UserDefaults.standard.bool(forKey: "use_mock_data")
                            if useMock {
                                await healthStore.loadMockData()
                            }
                        }
                        await healthStore.runLocalAnalysis()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("生成今日总结") {
                    Task { await BackgroundAnalysisScheduler.shared.requestNow() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        // MARK: - Menu Bar
        MenuBarExtra("Sovereign", systemImage: "heart.text.clipboard.fill") {
            MenuBarContentView()
                .environmentObject(healthStore)
        }
        .menuBarExtraStyle(.window)

        // MARK: - Settings
        Settings {
            SettingsView()
                .environmentObject(healthStore)
        }
    }
}

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
    @EnvironmentObject var healthStore: MacHealthStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Status header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(statusLabel)
                    .font(AppTypography.headline)
            }
            .padding(.bottom, 4)

            Divider()

            // Quick stats
            if let today = healthStore.todaySummary {
                MenuBarStatRow(icon: "figure.walk", label: "步数", value: "\(today.steps)")
                MenuBarStatRow(icon: "heart", label: "心率", value: "\(String(format: "%.0f", today.restingHeartRate)) bpm")
                MenuBarStatRow(icon: "moon.zzz", label: "睡眠", value: today.sleepFormatted)
                MenuBarStatRow(icon: "arrow.triangle.2.circlepath", label: "恢复", value: "\(String(format: "%.0f", today.recoveryScore))")
            } else {
                Text("暂无数据")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }

            if !healthStore.healthInsights.isEmpty {
                Divider()
                Text("提醒")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                ForEach(healthStore.healthInsights.prefix(2)) { insight in
                    Text(insight.title)
                        .font(AppTypography.caption)
                        .foregroundColor(insight.severity == .warning ? .orange : .secondary)
                }
            }

            Divider()

            // Actions
            Button("打开 Sovereign") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Button("生成今日总结") {
                Task { await BackgroundAnalysisScheduler.shared.requestNow() }
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 240)
    }

    private var statusIcon: String {
        let score = healthStore.latestRecoveryScore
        if score >= 70 { return "heart.circle.fill" }
        if score >= 40 { return "heart.circle" }
        return "heart.text.square"
    }

    private var statusColor: Color {
        let score = healthStore.latestRecoveryScore
        if score >= 70 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    private var statusLabel: String {
        healthStore.todaySummary?.healthStatus.rawValue ?? "数据不足"
    }
}

struct MenuBarStatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(AppTypography.caption.weight(.medium))
        }
    }
}
