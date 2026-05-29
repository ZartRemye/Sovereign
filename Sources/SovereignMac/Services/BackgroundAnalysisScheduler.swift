import Foundation

/// Schedules periodic local rule analysis in the background.
/// DeepSeek calls are rate-limited to morning/evening summaries only.
@MainActor
final class BackgroundAnalysisScheduler: ObservableObject {
    static let shared = BackgroundAnalysisScheduler()

    @Published var isRunning = false
    @Published var lastAnalysisTime: Date?
    @Published var isBackgroundAnalysisEnabled = true
    @Published var analysisInterval: TimeInterval = 900 // 15 minutes default

    private var timer: Timer?
    private weak var store: MacHealthStore?

    private var lastDeepSeekMorningCall: Date?
    private var lastDeepSeekEveningCall: Date?

    private init() {}

    func configure(store: MacHealthStore) {
        self.store = store
    }

    // MARK: - Start/Stop

    func start() {
        guard isBackgroundAnalysisEnabled else { return }
        stop()
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: analysisInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runAnalysisCycle()
            }
        }
        // Run immediately on start
        Task { await runAnalysisCycle() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func updateInterval(_ minutes: Int) {
        analysisInterval = TimeInterval(minutes * 60)
        if isRunning {
            start() // Restart with new interval
        }
    }

    // MARK: - Analysis Cycle

    private func runAnalysisCycle() async {
        guard let store else { return }
        await store.runLocalAnalysis()
        lastAnalysisTime = Date()

        // Check if we should run DeepSeek analysis (at most 2x/day)
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        // Morning summary: 7-9am, once per day
        if hour >= 7 && hour <= 9 {
            if lastDeepSeekMorningCall == nil || !calendar.isDate(lastDeepSeekMorningCall!, inSameDayAs: now) {
                await runDeepSeekAnalysis(type: "morning_summary")
                lastDeepSeekMorningCall = now
            }
        }

        // Evening summary: 7-9pm, once per day
        if hour >= 19 && hour <= 21 {
            if lastDeepSeekEveningCall == nil || !calendar.isDate(lastDeepSeekEveningCall!, inSameDayAs: now) {
                await runDeepSeekAnalysis(type: "evening_summary")
                lastDeepSeekEveningCall = now
            }
        }
    }

    private func runDeepSeekAnalysis(type: String) async {
        guard let store else { return }
        let aiEnabled = UserDefaults.standard.bool(forKey: "deepseek_enabled")
        guard aiEnabled, let _ = try? await resolveAPIKey() else { return }

        let context = HealthContextBuilder.build(
            summaries: store.dailySummaries,
            workouts: store.recentWorkouts,
            sleepSessions: store.recentSleep,
            insights: store.healthInsights,
            dataSource: store.dataSource
        )

        let runtime = await AIRuntimeStatus.current(dataSource: store.dataSource, summaries: store.dailySummaries)
        let prompt = HealthPromptBuilder.buildUserPrompt(
            question: type == "morning_summary" ? "生成今天的晨间健康总结和训练建议。" : "生成今天的晚间健康总结和明日建议。",
            context: context,
            runtime: runtime
        )

        do {
            let response = try await DeepSeekClient.shared.chat(
                systemPrompt: HealthPromptBuilder.systemPrompt(for: runtime),
                userMessage: prompt
            )

            // Cache the response
            let hash = prompt.hashValue.description
            let cache = AIAnalysisCache(promptHash: hash, response: response, modelUsed: "deepseek-v4-pro")
            // Note: modelContext is not accessible from here; caller should persist

            // Generate notification
            await NotificationService.shared.sendAnalysisCompleteNotification(
                title: type == "morning_summary" ? "晨间分析已生成" : "晚间分析已生成",
                body: String(response.prefix(100))
            )
        } catch {
            await NotificationService.shared.sendAnalysisFailedNotification(error: error)
        }
    }

    /// Request one-off analysis (user-triggered)
    func requestNow() async {
        await runAnalysisCycle()
    }
}
