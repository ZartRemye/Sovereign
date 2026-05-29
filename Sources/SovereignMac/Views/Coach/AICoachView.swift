import SwiftUI

struct AICoachView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @StateObject private var importCoordinator = ImportCoordinator.shared
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

    @State private var runtimeStatus: AIRuntimeStatus = AIRuntimeStatus()

    private var quickQuestions: [String] {
        if healthStore.dataSource == .empty {
            return [
                "如何导入 Apple Health 数据？",
                "你现在使用什么模型？",
                "为什么还不能分析我的健康？",
                "Demo 数据和真实数据有什么区别？",
            ]
        }
        return [
            "我今天适合训练吗？",
            "我最近恢复为什么变化？",
            "我这周训练应该怎么安排？",
            "我睡眠和疲劳有什么关系？",
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            coachHeader

            // Import status banner
            if importCoordinator.isImporting {
                importStatusBanner
            }

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
                                Text("分析中...")
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
                TextField("输入问题...", text: $inputText)
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
            runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries)
        }
        .onChange(of: healthStore.dataSource) { _ in
            Task {
                runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries)
            }
        }
    }

    // MARK: - Header

    private var coachHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Coach")
                    .font(AppTypography.largeTitle)
                HStack(spacing: AppSpacing.sm) {
                    Text("Sovereign health analysis assistant")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    // Data
                    HStack(spacing: 4) {
                        Circle().fill(dataSourceColor).frame(width: 5, height: 5)
                        Text(dataSourceLabel)
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("·")
                        .foregroundColor(.secondary)

                    // Model
                    HStack(spacing: 4) {
                        Circle().fill(aiModeColor).frame(width: 5, height: 5)
                        Text(runtimeStatus.providerMode.shortLabel)
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
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

    // MARK: - Import Status Banner

    private var importStatusBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Importing Apple Health data")
                    .font(AppTypography.caption.weight(.medium))
                Text("\(importCoordinator.progress.formattedProcessedSize) / \(importCoordinator.progress.formattedTotalSize) · \(importCoordinator.progress.percentComplete)% · \(importCoordinator.progress.formattedETA) remaining")
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("你好！我是 Sovereign 里的 AI 健康教练")
                .font(AppTypography.title2)

            VStack(spacing: 6) {
                welcomeStatusText
            }
            .frame(maxWidth: 420)

            if !runtimeStatus.isCloudAIEnabled {
                VStack(spacing: 4) {
                    if !useDeepSeek {
                        Text("当前使用本地规则引擎。")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                        Text("开启上方的 DeepSeek 开关并配置 API Key，可获得更智能的云端分析。")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    } else if !hasAPIKeyConfigured {
                        Text("DeepSeek 已开启但未配置 API Key。")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                        Text("请在设置 → AI 设置中保存你的 API Key。")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: 450)
        .padding(.vertical, 40)
    }

    private var welcomeStatusText: Text {
        let status = runtimeStatus

        if !status.hasRealHealthData && healthStore.dataSource == .empty {
            return Text("你的健康数据库目前为空。导入 Apple Health 数据后，我可以帮你分析趋势、评估恢复状态、给出训练建议。")
        } else if status.hasRealHealthData {
            let modeText = status.providerMode.isCloud ? "DeepSeek V4 (\(status.modelName ?? "unknown"))" : "本地规则引擎"
            if let range = status.dataDateRange {
                return Text("基于 \(status.dataSource.rawValue) 数据分析。当前后端: \(modeText)。数据范围: \(range.lowerBound.formatted(date: .numeric, time: .omitted)) 至 \(range.upperBound.formatted(date: .numeric, time: .omitted))。")
            }
            return Text("基于 \(status.dataSource.rawValue) 数据分析。当前后端: \(modeText)。")
        } else {
            return Text("当前使用 Demo 数据演示。后端: \(status.providerMode.label)。真实数据导入后会替换。")
        }
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }

        inputText = ""
        errorMessage = nil

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Check if it's an identity/role question — handle locally
        if isIdentityQuestion(trimmed) {
            messages.append(ChatMessage(
                role: .assistant,
                content: buildIdentityResponse(),
                contextSummary: "身份说明 · \(runtimeStatus.providerMode.shortLabel)",
                isFallback: false
            ))
            return
        }

        Task {
            isLoading = true
            defer { isLoading = false }

            // Safety check
            let safetyResult = safetyGuard.check(trimmed)
            if !safetyResult.isSafe, let warning = safetyResult.warningMessage {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: warning,
                    contextSummary: "安全拦截",
                    isFallback: true
                ))
                return
            }

            // Try DeepSeek if enabled
            if runtimeStatus.isCloudAIEnabled {
                await updateAIMode(to: "DeepSeek V4")
                do {
                    let context = HealthContextBuilder.build(
                        summaries: healthStore.dailySummaries,
                        workouts: healthStore.recentWorkouts,
                        sleepSessions: healthStore.recentSleep,
                        insights: healthStore.healthInsights,
                        dataSource: healthStore.dataSource
                    )

                    let prompt = HealthPromptBuilder.buildUserPrompt(
                        question: trimmed,
                        context: context,
                        runtime: runtimeStatus
                    )
                    let response = try await DeepSeekClient.shared.chat(
                        systemPrompt: HealthPromptBuilder.systemPrompt(for: runtimeStatus),
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

    // MARK: - Identity Handling

    private func isIdentityQuestion(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let patterns = [
            "你是谁", "你是什么", "deepseek", "你是deepseek",
            "你用什么模型", "你的模型", "什么模型", "哪个模型",
            "你是ai", "你是人工智能", "你是本地", "你是云端",
            "你的后端", "你用什么后端", "你怎么工作", "你能做什么",
            "你是什么ai", "介绍一下你自己", "你是谁开发的",
        ]
        return patterns.contains { lowercased.contains($0) }
    }

    private func buildIdentityResponse() -> String {
        let status = runtimeStatus
        var parts: [String] = []

        parts.append("我是 Sovereign App 里的 AI 健康教练与运动恢复分析师。")

        if status.providerMode.isCloud {
            parts.append("我当前的语言模型后端是 DeepSeek V4（模型名：\(status.modelName ?? "deepseek-v4-pro")），云端 API 地址为 \(status.baseURL ?? "https://api.deepseek.com")。")
            parts.append("DeepSeek 是我的语言模型提供商，不是我本身。我运行在 Sovereign App 里，专门做健康数据分析。")
        } else if case .localRules = status.providerMode {
            if !useDeepSeek {
                parts.append("当前没有启用 DeepSeek，我使用本地规则引擎。这意味着我的回答能力更保守、更有限。你可以在 Settings 里开启 DeepSeek 并配置 API Key 以启用更智能的云端分析。")
            } else {
                parts.append("DeepSeek 已开启但未配置 API Key，当前使用本地规则引擎。请在 Settings → AI 设置中保存你的 API Key。")
            }
        } else if case .fallback(let reason) = status.providerMode {
            parts.append("当前由于「\(reason)」已降级为本地规则引擎。")
        }

        if !status.hasRealHealthData {
            parts.append("你还没有导入 Apple Health 数据，所以我不能基于真实身体数据做分析。请先在「数据导入」页面导入数据。")
        } else if let range = status.dataDateRange {
            parts.append("你的健康数据范围是 \(range.lowerBound.formatted(date: .numeric, time: .omitted)) 至 \(range.upperBound.formatted(date: .numeric, time: .omitted))，数据来源为 \(status.dataSource.rawValue)。")
        }

        parts.append("我不是通用聊天机器人。我的任务是帮你理解健康趋势、睡眠、恢复、活动量和训练负荷。")
        parts.append("我不是医生，不能做医疗诊断。所有建议仅供个人参考。")

        return parts.joined(separator: "\n\n")
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
            let status = runtimeStatus
            aiMode = status.providerMode.label
        }
    }

    private var aiModeColor: Color {
        if aiMode.contains("Local Rules") { return .blue }
        if aiMode.contains("DeepSeek") { return .purple }
        if aiMode.contains("Fallback") { return .orange }
        return .gray
    }

    private var dataSourceColor: Color {
        switch healthStore.dataSource {
        case .empty: return .gray
        case .mockLive: return .orange
        case .appleHealthImport: return .green
        default: return .gray
        }
    }

    private var dataSourceLabel: String {
        switch healthStore.dataSource {
        case .empty: return "No Data"
        case .mockLive: return "Demo"
        case .appleHealthImport: return "Apple Health"
        default: return healthStore.dataSource.rawValue
        }
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
