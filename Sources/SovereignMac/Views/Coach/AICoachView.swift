import SwiftUI

struct AICoachView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @EnvironmentObject var chatStore: ChatSessionStore
    @StateObject private var importCoordinator = ImportCoordinator.shared
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var useDeepSeek: Bool = UserDefaults.standard.bool(forKey: "deepseek_enabled")
    @State private var aiMode: String = "Local Rules"
    @State private var errorMessage: String?
    @State private var hasAPIKeyConfigured: Bool = false
    @State private var showDataBasis: UUID?
    @State private var showSessionList: Bool = true
    @State private var runtimeStatus: AIRuntimeStatus = AIRuntimeStatus()

    private let safetyGuard = HealthSafetyGuard()
    private let localRules = LocalRuleAIService.shared

    private var quickQuestions: [String] {
        healthStore.dataSource == .empty
            ? ["如何导入 Apple Health 数据？", "你现在使用什么模型？", "为什么还不能分析？", "Demo 和真实数据有什么区别？"]
            : ["我今天适合训练吗？", "我最近恢复为什么变化？", "我这周训练应该怎么安排？", "我睡眠和疲劳有什么关系？"]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Session sidebar
            if showSessionList {
                sessionSidebar
                    .frame(width: 220)
                Divider()
            }

            // Main chat area
            VStack(spacing: 0) {
                coachHeader
                if importCoordinator.isImporting { importBanner }
                Divider()
                messagesList
                Divider()
                quickQuestionsBar
                inputBar
            }
        }
        .navigationTitle("AI 教练")
        .task {
            await checkAPIKey()
            await updateAIMode()
            runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries)
        }
        .onChange(of: healthStore.dataSource) { _ in
            Task { runtimeStatus = await AIRuntimeStatus.current(dataSource: healthStore.dataSource, summaries: healthStore.dailySummaries) }
        }
    }

    // MARK: - Session Sidebar

    private var sessionSidebar: some View {
        VStack(spacing: 0) {
            // New chat button
            Button(action: {
                Task {
                    let range = healthStore.dailySummaries.map(\.date).min().map { s in (s, Date()) } ?? (nil, nil)
                    chatStore.createNewSession(runtime: runtimeStatus, dataRange: (range.0, range.1))
                }
            }) {
                Label("New Chat", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(10)

            Divider()

            // Session list
            List(selection: Binding<UUID?>(
                get: { chatStore.activeSession?.id },
                set: { id in
                    if let id, let s = chatStore.sessions.first(where: { $0.id == id }) {
                        chatStore.selectSession(s)
                    }
                }
            )) {
                ForEach(chatStore.sessions) { session in
                    HStack(spacing: 6) {
                        if session.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(session.updatedAt, style: .relative).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Pin") { chatStore.togglePin(session) }
                        Button("Rename") { /* sheet */ }
                        Button("Archive", role: .destructive) { chatStore.archiveSession(session) }
                        Button("Delete", role: .destructive) { withConfirmation { chatStore.deleteSession(session) } }
                    }
                    .tag(session.id)
                }
            }
            .listStyle(.plain)

            Divider()

            // Session actions
            HStack(spacing: 8) {
                Button(action: { chatStore.clearActiveSession() }) {
                    Image(systemName: "eraser").font(.caption)
                }
                .help("Clear current chat")
                .buttonStyle(.plain)

                Button(action: { exportChat() }) {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                }
                .help("Export chat")
                .buttonStyle(.plain)

                Spacer()

                Text("\(chatStore.sessions.count) chats")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Header

    private var coachHeader: some View {
        HStack {
            Button(action: { withAnimation { showSessionList.toggle() } }) {
                Image(systemName: "sidebar.left").font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(chatStore.activeSession?.title ?? "AI Coach")
                    .font(AppTypography.title3)
                HStack(spacing: 6) {
                    Circle().fill(dataSourceColor).frame(width: 5, height: 5)
                    Text(dataSourceLabel).font(.system(size: 11))
                    Text("·").foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Circle().fill(aiModeColor).frame(width: 5, height: 5)
                        Text(aiMode).font(.system(size: 11))
                    }
                }
                .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("DeepSeek", isOn: $useDeepSeek).toggleStyle(.switch)
                .onChange(of: useDeepSeek) { v in UserDefaults.standard.set(v, forKey: "deepseek_enabled"); Task { await updateAIMode() } }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Import banner

    private var importBanner: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
            Text("Importing \(importCoordinator.progress.formattedProcessedSize) / \(importCoordinator.progress.formattedTotalSize) · \(importCoordinator.progress.percentComplete)%")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    if chatStore.activeMessages.isEmpty {
                        welcomeView
                    }
                    ForEach(chatStore.activeMessages, id: \.id) { msg in
                        MessageBubbleView(message: msg, showDataBasis: $showDataBasis)
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(msg.contentMarkdown, forType: .string)
                                }
                                Button("Delete", role: .destructive) {
                                    chatStore.deleteMessage(msg)
                                }
                            }
                    }
                    if isLoading {
                        HStack { ProgressView().padding(); Text("分析中...").font(.caption).foregroundColor(.secondary); Spacer() }
                    }
                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundColor(.red).padding()
                    }
                }
                .padding()
            }
            .onChange(of: chatStore.activeMessages.count) { _ in
                if let last = chatStore.activeMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "brain.head.profile").font(.system(size: 40)).foregroundColor(.accentColor)
            Text("你好！我是 Sovereign 里的 AI 健康教练").font(AppTypography.title2)
            VStack(spacing: 4) {
                if !runtimeStatus.hasRealHealthData && healthStore.dataSource == .empty {
                    Text("你的健康数据库目前为空。导入 Apple Health 数据后，我可以帮你分析趋势、评估恢复状态。")
                } else if runtimeStatus.hasRealHealthData {
                    Text("基于 \(healthStore.dataSource.rawValue) 数据 (\(healthStore.dbSummaryCount) 天)。当前后端: \(runtimeStatus.providerMode.shortLabel)。")
                } else {
                    Text("当前使用 Demo 数据演示。后端: \(runtimeStatus.providerMode.label)。")
                }
            }
            .font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            if !runtimeStatus.isCloudAIEnabled {
                Text(!useDeepSeek ? "当前使用本地规则引擎。开启 DeepSeek 并配置 API Key 可获得更智能的分析。" : "DeepSeek 已开启但未配置 API Key。请在 Settings → AI 设置中保存 Key。")
                    .font(.caption).foregroundColor(.secondary).padding().background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: 420).padding(.vertical, 40)
    }

    // MARK: - Quick Questions

    private var quickQuestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickQuestions, id: \.self) { q in
                    Button(q) { sendMessage(q) }.buttonStyle(.bordered).controlSize(.small)
                }
            }.padding(.horizontal).padding(.vertical, 6)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: AppSpacing.md) {
            TextField("输入问题...", text: $inputText).textFieldStyle(.roundedBorder).onSubmit { sendMessage(inputText) }
            Button(action: { sendMessage(inputText) }) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }.padding(.horizontal).padding(.bottom, 10)
    }

    // MARK: - Send

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }
        inputText = ""; errorMessage = nil

        // Ensure active session
        if chatStore.activeSession == nil {
            chatStore.createNewSession(runtime: runtimeStatus)
        }

        chatStore.appendUserMessage(trimmed)

        // Identity question → local
        if isIdentityQuestion(trimmed) {
            let answer = buildIdentityResponse()
            chatStore.appendAssistantMessage(markdown: answer, runtime: runtimeStatus, evidence: "身份说明 · \(runtimeStatus.providerMode.shortLabel)")
            return
        }

        Task {
            isLoading = true; defer { isLoading = false }
            let safetyResult = safetyGuard.check(trimmed)
            if !safetyResult.isSafe, let warning = safetyResult.warningMessage {
                chatStore.appendFallbackMessage(markdown: warning, evidence: "安全拦截")
                return
            }
            if runtimeStatus.isCloudAIEnabled {
                await updateAIMode(to: "DeepSeek V4")
                do {
                    let context = HealthContextBuilder.build(summaries: healthStore.dailySummaries, workouts: healthStore.recentWorkouts, sleepSessions: healthStore.recentSleep, insights: healthStore.healthInsights, dataSource: healthStore.dataSource)
                    let modelBuilder = PersonalHealthModelBuilder()
                    let healthModel = modelBuilder.build(summaries: healthStore.dailySummaries, workouts: healthStore.recentWorkouts, sleep: healthStore.recentSleep)
                    let forecast = ForecastEngine().forecast(from: healthModel)
                    let prescription = ExercisePrescriptionEngine().prescribe(from: healthModel)
                    let prompt = HealthPromptBuilder.buildUserPrompt(question: trimmed, context: context, runtime: runtimeStatus, healthModel: healthModel, forecast: forecast, prescription: prescription)
                    let response = try await DeepSeekClient.shared.chat(systemPrompt: HealthPromptBuilder.systemPrompt(for: runtimeStatus), userMessage: prompt)
                    let evidence = "DeepSeek V4 · \(context.dataQuality.dateRangeStart) – \(context.dataQuality.dateRangeEnd)" + (context.isMockData ? " · Demo" : "")
                    chatStore.appendAssistantMessage(markdown: response, runtime: runtimeStatus, evidence: evidence)
                    return
                } catch {
                    await updateAIMode(to: "Fallback (Local Rules)")
                    chatStore.appendSystemMessage("DeepSeek 请求失败 (\(error.localizedDescription))，已切换本地规则引擎。")
                }
            }
            await updateAIMode(to: "Local Rules")
            let stream = await localRules.analyze(question: trimmed, summaries: healthStore.dailySummaries, workouts: healthStore.recentWorkouts, sleepSessions: healthStore.recentSleep)
            for await msg in stream {
                chatStore.appendAssistantMessage(markdown: msg.content, runtime: runtimeStatus, evidence: msg.contextSummary)
            }
        }
    }

    // MARK: - Identity

    private func isIdentityQuestion(_ text: String) -> Bool {
        ["你是谁", "你是什么", "deepseek", "你是deepseek", "你用什么模型", "什么模型", "哪个模型", "你的后端", "介绍一下你自己", "你是医生吗", "你能做什么"].contains { text.lowercased().contains($0) }
    }

    private func buildIdentityResponse() -> String {
        var p: [String] = ["我是 **Sovereign App 里的 AI 健康教练与运动恢复分析师**。"]
        if runtimeStatus.providerMode.isCloud {
            p.append("当前语言模型后端是 **DeepSeek V4**（模型 \(runtimeStatus.modelName ?? "deepseek-v4-pro")）。DeepSeek 是我的后端，不是我本身。")
        } else {
            p.append("当前使用**本地规则引擎**。你可以在 Settings 中开启 DeepSeek 并配置 API Key 以启用云端分析。")
        }
        if !runtimeStatus.hasRealHealthData { p.append("目前没有真实 Apple Health 数据，无法做个性化分析。") }
        p.append("我不是医生，不能做医疗诊断或开药。我的任务是帮你理解健康趋势、恢复状态、训练负荷和活动模式。")
        return p.joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private func exportChat() {
        let md = chatStore.exportActiveSession()
        let savePanel = NSSavePanel()
        savePanel.title = "Export Chat"
        savePanel.nameFieldStringValue = "Sovereign Chat \(Date().formatted(date: .numeric, time: .omitted)).md"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? md.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func withConfirmation(_ action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "确认删除？"
        alert.informativeText = "此操作不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }

    private func checkAPIKey() async { hasAPIKeyConfigured = (try? await resolveAPIKey()) != nil }
    private func updateAIMode(to mode: String? = nil) async { aiMode = mode ?? runtimeStatus.providerMode.label }
    private var aiModeColor: Color { aiMode.contains("Local") ? .blue : aiMode.contains("DeepSeek") ? .purple : aiMode.contains("Fallback") ? .orange : .gray }
    private var dataSourceColor: Color { healthStore.dataSource == .appleHealthImport ? .green : healthStore.dataSource == .mockLive ? .orange : .gray }
    private var dataSourceLabel: String { healthStore.dataSource == .empty ? "No Data" : healthStore.dataSource == .mockLive ? "Demo" : "Apple Health" }
}

// MARK: - Markdown Message Bubble

struct MessageBubbleView: View {
    let message: ChatMessageRecord
    @Binding var showDataBasis: UUID?

    private var attributedContent: AttributedString {
        (try? AttributedString(markdown: message.contentMarkdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.contentPlainText)
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role != "user" {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attributedContent)
                        .font(.callout)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.08), lineWidth: 0.5))
                        .textSelection(.enabled)

                    // Evidence toggle
                    if let evidence = message.contextSummary, !evidence.isEmpty {
                        Button(action: { showDataBasis = showDataBasis == message.id ? nil : message.id }) {
                            HStack(spacing: 3) {
                                Image(systemName: showDataBasis == message.id ? "chevron.up" : "info.circle").font(.caption2)
                                Text(showDataBasis == message.id ? "收起" : "数据依据").font(.caption2)
                            }.foregroundColor(.secondary).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.06), in: Capsule())
                        }.buttonStyle(.plain)

                        if showDataBasis == message.id {
                            Text(evidence).font(.caption2).foregroundColor(.secondary).padding(6)
                                .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Text(message.createdAt, style: .time).font(.caption2).foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(attributedContent)
                        .font(.callout).foregroundColor(.white)
                        .padding(10).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                    Text(message.createdAt, style: .time).font(.caption2).foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 2)
        .id(message.id)
    }
}
