import Foundation
import SwiftUI

// MARK: - AI Request State

enum AIRequestState: Equatable {
    case idle
    case thinking(phase: String)  // e.g. "Building health model..."
    case streaming
    case completed
    case failed(String)
}

// MARK: - AI Request Coordinator (global, survives page navigation)

@MainActor
final class AIRequestCoordinator: ObservableObject {
    static let shared = AIRequestCoordinator()

    @Published var state: AIRequestState = .idle
    @Published var currentQuestion: String?
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Submit a health question. Returns immediately; result goes to ChatSessionStore.
    func ask(question: String, store: MacHealthStore, chatStore: ChatSessionStore,
             runtime: AIRuntimeStatus, useDeepSeek: Bool) {

        // Cancel any in-flight request
        cancel()

        currentQuestion = question
        state = .thinking(phase: "安全检查...")
        errorMessage = nil

        // Auto-create session if needed
        if chatStore.activeSession == nil {
            chatStore.createNewSession(runtime: runtime)
        }
        chatStore.appendUserMessage(question)

        currentTask = Task { [weak self] in
            guard let self else { return }

            // Safety check
            let safetyResult = HealthSafetyGuard().check(question)
            if !safetyResult.isSafe {
                await MainActor.run {
                    self.state = .completed
                    if let warning = safetyResult.warningMessage {
                        chatStore.appendFallbackMessage(markdown: warning, evidence: "安全拦截")
                    }
                }
                return
            }

            // Identity question → local response
            if isIdentityQuestion(question) {
                await MainActor.run {
                    let answer = buildIdentityResponse(runtime: runtime, store: store)
                    chatStore.appendAssistantMessage(markdown: answer, runtime: runtime, evidence: "身份说明")
                    self.state = .completed
                }
                return
            }

            // Health analysis
            if useDeepSeek && runtime.isCloudAIEnabled {
                await runDeepSeekAnalysis(question: question, store: store, chatStore: chatStore, runtime: runtime)
            } else {
                await runLocalAnalysis(question: question, store: store, chatStore: chatStore)
            }

            await MainActor.run { self.state = .completed }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
        currentQuestion = nil
        errorMessage = nil
    }

    // MARK: - DeepSeek Path

    private func runDeepSeekAnalysis(question: String, store: MacHealthStore,
                                      chatStore: ChatSessionStore, runtime: AIRuntimeStatus) async {
        await MainActor.run { state = .thinking(phase: "构建健康画像...") }
        guard !Task.isCancelled else { return }

        let modelBuilder = PersonalHealthModelBuilder()
        let healthModel = modelBuilder.build(summaries: store.dailySummaries, workouts: store.recentWorkouts, sleep: store.recentSleep)

        await MainActor.run { state = .thinking(phase: "预测短期趋势...") }
        guard !Task.isCancelled else { return }
        let forecast = ForecastEngine().forecast(from: healthModel)

        await MainActor.run { state = .thinking(phase: "生成运动建议...") }
        guard !Task.isCancelled else { return }
        let prescription = ExercisePrescriptionEngine().prescribe(from: healthModel)

        await MainActor.run { state = .thinking(phase: "构建分析上下文...") }
        guard !Task.isCancelled else { return }
        let context = HealthContextBuilder.build(
            summaries: store.dailySummaries, workouts: store.recentWorkouts,
            sleepSessions: store.recentSleep, insights: store.healthInsights,
            dataSource: store.dataSource
        )

        await MainActor.run { state = .thinking(phase: "调用 DeepSeek...") }
        guard !Task.isCancelled else { return }

        do {
            let prompt = HealthPromptBuilder.buildUserPrompt(
                question: question, context: context, runtime: runtime,
                healthModel: healthModel, forecast: forecast, prescription: prescription
            )
            let systemPrompt = HealthPromptBuilder.systemPrompt(for: runtime)
            let response = try await DeepSeekClient.shared.chat(systemPrompt: systemPrompt, userMessage: prompt)

            await MainActor.run {
                let evidence = "DeepSeek V4 · \(context.dataQuality.dateRangeStart) – \(context.dataQuality.dateRangeEnd)"
                chatStore.appendAssistantMessage(markdown: response, runtime: runtime, evidence: evidence)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                chatStore.appendSystemMessage("DeepSeek 请求失败 (\(error.localizedDescription))，已切换本地规则引擎。")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Local Rules Path

    private func runLocalAnalysis(question: String, store: MacHealthStore,
                                   chatStore: ChatSessionStore) async {
        await MainActor.run { state = .thinking(phase: "本地规则分析...") }
        guard !Task.isCancelled else { return }

        let stream = await LocalRuleAIService.shared.analyze(
            question: question, summaries: store.dailySummaries,
            workouts: store.recentWorkouts, sleepSessions: store.recentSleep
        )
        for await msg in stream {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                chatStore.appendAssistantMessage(markdown: msg.content, runtime: AIRuntimeStatus(), evidence: msg.contextSummary)
            }
        }
    }

    // MARK: - Identity

    private func isIdentityQuestion(_ text: String) -> Bool {
        let patterns = ["你是谁", "你是什么", "deepseek", "你是deepseek", "你用什么模型",
                        "什么模型", "哪个模型", "你的后端", "介绍一下你自己", "你是医生吗", "你能做什么"]
        return patterns.contains { text.lowercased().contains($0) }
    }

    private func buildIdentityResponse(runtime: AIRuntimeStatus, store: MacHealthStore) -> String {
        var p: [String] = ["我是 **Sovereign App 里的 AI 健康教练与运动恢复分析师**。"]
        if runtime.providerMode.isCloud {
            p.append("当前语言模型后端是 **DeepSeek V4**。DeepSeek 是我的后端语言模型，不是我本身。")
        } else {
            p.append("当前使用**本地规则引擎**。你可以在设置中开启 DeepSeek 并配置 API Key。")
        }
        if store.dataSource == .empty { p.append("目前没有真实 Apple Health 数据，无法做个性化分析。") }
        p.append("我不是医生，不能做医疗诊断或开药。")
        return p.joined(separator: "\n\n")
    }
}
