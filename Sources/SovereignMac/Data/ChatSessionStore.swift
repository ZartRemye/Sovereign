import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ChatSessionStore: ObservableObject {
    static let shared = ChatSessionStore()

    @Published var sessions: [ChatSessionRecord] = []
    @Published var activeSession: ChatSessionRecord?
    @Published var activeMessages: [ChatMessageRecord] = []
    @Published var isLoading = false

    private var modelContext: ModelContext?

    private init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
        loadSessions()
    }

    // MARK: - Session Management

    func loadSessions() {
        guard let ctx = modelContext else { return }
        var descriptor = FetchDescriptor<ChatSessionRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.predicate = #Predicate { !$0.isArchived }
        sessions = (try? ctx.fetch(descriptor)) ?? []

        if let first = sessions.first {
            selectSession(first)
        }
    }

    func createNewSession(runtime: AIRuntimeStatus, dataRange: (start: Date?, end: Date?)? = nil) {
        guard let ctx = modelContext else { return }
        let session = ChatSessionRecord(
            title: "Chat \(sessions.count + 1)",
            dataSource: runtime.dataSource.rawValue,
            providerMode: runtime.providerMode.label,
            modelName: runtime.modelName,
            healthDataRangeStart: dataRange?.start,
            healthDataRangeEnd: dataRange?.end
        )
        ctx.insert(session)
        try? ctx.save()
        sessions.insert(session, at: 0)
        selectSession(session)
    }

    func selectSession(_ session: ChatSessionRecord) {
        activeSession = session
        activeMessages = session.messages?.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    func renameSession(_ session: ChatSessionRecord, title: String) {
        session.title = title
        try? modelContext?.save()
        if session.id == activeSession?.id { activeSession = session }
    }

    func deleteSession(_ session: ChatSessionRecord) {
        guard let ctx = modelContext else { return }
        ctx.delete(session)
        try? ctx.save()
        sessions.removeAll { $0.id == session.id }
        if session.id == activeSession?.id {
            if let first = sessions.first { selectSession(first) }
            else { activeSession = nil; activeMessages = [] }
        }
    }

    func clearActiveSession() {
        guard let ctx = modelContext, let session = activeSession else { return }
        if let msgs = session.messages {
            for msg in msgs { ctx.delete(msg) }
        }
        session.messages = []
        session.updatedAt = Date()
        try? ctx.save()
        activeMessages = []
    }

    func togglePin(_ session: ChatSessionRecord) {
        session.isPinned.toggle()
        try? modelContext?.save()
        sessions.sort { $0.isPinned && !$1.isPinned ? true : (!$0.isPinned && $1.isPinned ? false : $0.updatedAt > $1.updatedAt) }
    }

    func archiveSession(_ session: ChatSessionRecord) {
        session.isArchived = true
        try? modelContext?.save()
        sessions.removeAll { $0.id == session.id }
        if session.id == activeSession?.id {
            activeSession = nil
            activeMessages = []
        }
    }

    // MARK: - Messages

    func appendUserMessage(_ text: String) {
        guard let ctx = modelContext, let session = activeSession else { return }
        let msg = ChatMessageRecord(role: "user", contentMarkdown: text)
        msg.session = session
        ctx.insert(msg)
        session.updatedAt = Date()
        try? ctx.save()
        activeMessages.append(msg)
    }

    func appendAssistantMessage(markdown: String, runtime: AIRuntimeStatus, evidence: String?,
                                 finishReason: String? = nil, isTruncated: Bool = false) {
        guard let ctx = modelContext, let session = activeSession else { return }
        let clean = MarkdownSanitizer.displayMarkdown(from: markdown)
        let plain = MarkdownSanitizer.plainText(from: clean)
        let msg = ChatMessageRecord(
            role: "assistant",
            contentMarkdown: clean,
            contentPlainText: plain,
            contextSummary: evidence,
            evidenceData: evidence,
            isFallback: false,
            providerMode: runtime.providerMode.label,
            modelName: runtime.modelName,
            status: isTruncated ? "truncated" : "completed",
            finishReason: finishReason,
            isPartial: isTruncated
        )
        msg.session = session
        ctx.insert(msg)
        session.updatedAt = Date()
        try? ctx.save()
        activeMessages.append(msg)
    }

    /// Continue a truncated message by appending new content
    func continueLastAssistantMessage(additionalMarkdown: String, finishReason: String?) {
        guard let ctx = modelContext, let last = activeMessages.last, last.role == "assistant" else { return }
        last.contentMarkdown += "\n\n" + MarkdownSanitizer.displayMarkdown(from: additionalMarkdown)
        last.contentPlainText = MarkdownSanitizer.plainText(from: last.contentMarkdown)
        last.finishReason = finishReason
        last.status = finishReason == "stop" ? "completed" : "truncated"
        last.continuationCount += 1
        last.isPartial = (finishReason != "stop")
        if let session = activeSession { session.updatedAt = Date() }
        try? ctx.save()
    }

    func updateLastMessage(finishReason: String?, status: String) {
        guard let last = activeMessages.last, last.role == "assistant" else { return }
        last.finishReason = finishReason
        last.status = status
        last.isPartial = (status != "completed")
        if let session = activeSession { session.updatedAt = Date() }
        try? modelContext?.save()
    }

    func appendSystemMessage(_ text: String) {
        guard let ctx = modelContext, let session = activeSession else { return }
        let msg = ChatMessageRecord(role: "system", contentMarkdown: text)
        msg.session = session
        ctx.insert(msg)
        session.updatedAt = Date()
        try? ctx.save()
        activeMessages.append(msg)
    }

    func appendFallbackMessage(markdown: String, evidence: String?) {
        guard let ctx = modelContext, let session = activeSession else { return }
        let clean = MarkdownSanitizer.displayMarkdown(from: markdown)
        let msg = ChatMessageRecord(
            role: "assistant",
            contentMarkdown: clean,
            contentPlainText: MarkdownSanitizer.plainText(from: clean),
            contextSummary: evidence,
            isFallback: true
        )
        msg.session = session
        ctx.insert(msg)
        session.updatedAt = Date()
        try? ctx.save()
        activeMessages.append(msg)
    }

    func deleteMessage(_ message: ChatMessageRecord) {
        guard let ctx = modelContext else { return }
        ctx.delete(message)
        try? ctx.save()
        activeMessages.removeAll { $0.id == message.id }
    }

    // MARK: - Export

    func exportActiveSession() -> String {
        var lines: [String] = []
        lines.append("# \(activeSession?.title ?? "Chat")")
        lines.append("Date: \(activeSession?.createdAt.formatted() ?? "")")
        lines.append("Provider: \(activeSession?.providerMode ?? "")")
        lines.append("Data: \(activeSession?.dataSource ?? "")")
        lines.append("")
        for msg in activeMessages {
            let roleLabel = msg.role == "user" ? "You" : (msg.role == "system" ? "System" : "Sovereign")
            lines.append("**\(roleLabel)** (\(msg.createdAt.formatted(date: .abbreviated, time: .shortened))):")
            lines.append(msg.contentMarkdown)
            lines.append("")
        }
        let disclaimer = "\n> Sovereign AI Coach — not a doctor. This is not medical advice."
        return lines.joined(separator: "\n") + disclaimer
    }
}
