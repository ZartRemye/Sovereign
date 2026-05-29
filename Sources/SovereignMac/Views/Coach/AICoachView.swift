import SwiftUI

struct AICoachView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var useDeepSeek: Bool = UserDefaults.standard.bool(forKey: "deepseek_enabled")
    @State private var aiMode: String = "Local Rules"
    @State private var errorMessage: String?
    @State private var hasAPIKeyConfigured: Bool = false
    @State private var showDataBasis: UUID?

    private let safetyGuard = HealthSafetyGuard()
    private let localRules = LocalRuleAIService.shared

    private let quickQuestions = [
        "我今天适合训练吗？",
        "我最近恢复为什么变化？",
        "我这周训练应该怎么安排？",
        "我睡眠和疲劳有什么关系？",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            coachHeader

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppSpacing.md) {
                        if messages.isEmpty {
                            welcomeView
                        }

                        ForEach(messages) { message in
                            ChatMessageBubble(message: message, showDataBasis: $showDataBasis)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .padding()
                                Text("思考中...")
                                    .font(AppTypography.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundColor(.red)
                                .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Quick questions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(quickQuestions, id: \.self) { question in
                        Button(question) {
                            sendMessage(question)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Input bar
            HStack(spacing: AppSpacing.md) {
                TextField("输入健康相关问题...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage(inputText) }

                Button(action: { sendMessage(inputText) }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding()
        }
        .navigationTitle("AI 教练")
        .task {
            await checkAPIKey()
            await updateAIMode()
        }
    }

    // MARK: - Header

    private var coachHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 健康教练")
                    .font(AppTypography.largeTitle)
                HStack(spacing: AppSpacing.sm) {
                    // Data source badge
                    DataSourceBadge(source: healthStore.dataSource)

                    Circle()
                        .fill(aiModeColor)
                        .frame(width: 6, height: 6)
                    Text(aiMode)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            Toggle("DeepSeek", isOn: $useDeepSeek)
                .toggleStyle(.switch)
                .onChange(of: useDeepSeek) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "deepseek_enabled")
                    Task { await updateAIMode() }
                }
        }
        .padding()
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("你好！我是你的私人健康分析师")
                .font(AppTypography.title2)

            if healthStore.dataSource == .empty {
                VStack(spacing: 8) {
                    Text("目前没有健康数据。导入 Apple Health 数据后，我可以帮你分析趋势、评估恢复状态、给出训练建议。")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Text("所有分析基于本地数据，不是医疗诊断。")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("基于\(healthStore.dataSource == .mockLive ? "Demo 演示" : "真实 Apple Health")数据分析。\n选择一个快捷问题开始，或输入你的问题。")
                    .font(AppTypography.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !useDeepSeek || !hasAPIKeyConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("当前使用本地规则引擎。配置 DeepSeek API Key 可启用更智能的云端分析。")
                }
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 40)
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }

        inputText = ""
        errorMessage = nil

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        Task {
            isLoading = true
            defer { isLoading = false }

            // Safety check
            let safetyResult = safetyGuard.check(trimmed)
            if !safetyResult.isSafe, let warning = safetyResult.warningMessage {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: warning,
                    contextSummary: "安全拦截: \(safetyResult.category?.rawValue ?? "")",
                    isFallback: true
                ))
                return
            }

            // Try DeepSeek if enabled
            if useDeepSeek, (try? await resolveAPIKey()) != nil {
                await updateAIMode(to: "DeepSeek V4")
                do {
                    let context = HealthContextBuilder.build(
                        summaries: healthStore.dailySummaries,
                        workouts: healthStore.recentWorkouts,
                        sleepSessions: healthStore.recentSleep,
                        insights: healthStore.healthInsights,
                        dataSource: healthStore.dataSource
                    )

                    let prompt = HealthPromptBuilder.buildUserPrompt(question: trimmed, context: context)
                    let response = try await DeepSeekClient.shared.chat(
                        systemPrompt: HealthPromptBuilder.systemPrompt,
                        userMessage: prompt
                    )

                    let contextSummary = buildContextSummary(context: context)
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: response,
                        contextSummary: contextSummary,
                        isFallback: false
                    ))
                    return
                } catch {
                    await updateAIMode(to: "Fallback (Local Rules)")
                    messages.append(ChatMessage(
                        role: .system,
                        content: "DeepSeek 请求失败 (\(error.localizedDescription))，已切换本地规则引擎。",
                        timestamp: Date()
                    ))
                }
            }

            // Local rules fallback
            await updateAIMode(to: "Local Rules")
            let stream = await localRules.analyze(
                question: trimmed,
                summaries: healthStore.dailySummaries,
                workouts: healthStore.recentWorkouts,
                sleepSessions: healthStore.recentSleep
            )

            for await message in stream {
                messages.append(message)
            }
        }
    }

    // MARK: - Helpers

    private func buildContextSummary(context: HealthContext) -> String {
        var parts: [String] = []
        parts.append("基于 DeepSeek V4")
        parts.append("数据范围: \(context.dataQuality.dateRangeStart) 至 \(context.dataQuality.dateRangeEnd)")
        if context.isMockData {
            parts.append("⚠️ Demo 数据")
        } else {
            parts.append("真实数据")
        }
        return parts.joined(separator: " · ")
    }

    private func checkAPIKey() async {
        hasAPIKeyConfigured = ((try? await resolveAPIKey()) != nil)
    }

    private func updateAIMode(to mode: String? = nil) async {
        if let mode = mode {
            aiMode = mode
        } else {
            if useDeepSeek {
                let hasKey = (try? await resolveAPIKey()) != nil
                hasAPIKeyConfigured = hasKey
                aiMode = hasKey ? "DeepSeek V4" : "Local Rules (无 API Key)"
            } else {
                aiMode = "Local Rules"
            }
        }
    }

    private var aiModeColor: Color {
        if aiMode.contains("Local Rules") { return .blue }
        if aiMode.contains("DeepSeek") { return .purple }
        if aiMode.contains("Fallback") { return .orange }
        return .gray
    }
}

// MARK: - Data Source Badge

struct DataSourceBadge: View {
    let source: DataSource

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)
            Text(badgeText)
                .font(AppTypography.caption2)
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.1), in: Capsule())
    }

    private var badgeColor: Color {
        switch source {
        case .empty: return .gray
        case .mockLive: return .orange
        case .appleHealthImport: return .green
        case .iphoneSync: return .blue
        case .watchLive: return .purple
        case .unknown: return .gray
        }
    }

    private var badgeText: String {
        switch source {
        case .empty: return "无数据"
        case .mockLive: return "Demo Data"
        case .appleHealthImport: return "Apple Health"
        case .iphoneSync: return "iPhone"
        case .watchLive: return "Watch"
        case .unknown: return "未知"
        }
    }
}
