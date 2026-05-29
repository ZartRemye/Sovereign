import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @EnvironmentObject var chatStore: ChatSessionStore
    @State private var selectedPane: SettingsPane = .ai

    enum SettingsPane: String, CaseIterable {
        case ai = "AI"
        case privacy = "Privacy"
        case data = "Data"
        case chat = "Chat"

        var systemImage: String {
            switch self {
            case .ai: "brain"
            case .privacy: "hand.raised"
            case .data: "gearshape.2"
            case .chat: "bubble.left.and.text.bubble.right"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selectedPane) {
                ForEach(SettingsPane.allCases, id: \.self) { pane in
                    Label(pane.rawValue, systemImage: pane.systemImage).tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            // Content
            Group {
                switch selectedPane {
                case .ai:      AISettingsView()
                case .privacy: PrivacySettingsView()
                case .data:    DataSettingsView()
                case .chat:    ChatSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 450)
    }
}

// MARK: - Chat Settings

struct ChatSettingsView: View {
    @EnvironmentObject var chatStore: ChatSessionStore
    @State private var showClearConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Chat History") {
                HStack {
                    Text("Active Sessions")
                    Spacer()
                    Text("\(chatStore.sessions.count)").foregroundColor(.secondary)
                }
                HStack {
                    Text("Current Messages")
                    Spacer()
                    Text("\(chatStore.activeMessages.count)").foregroundColor(.secondary)
                }
                if let session = chatStore.activeSession {
                    HStack {
                        Text("Current Session")
                        Spacer()
                        Text(session.title).foregroundColor(.secondary)
                    }
                }
            }

            Section("Actions") {
                Button("Clear Current Chat") {
                    showClearConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(chatStore.activeMessages.isEmpty)

                Button("Delete All Chats", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(chatStore.sessions.isEmpty)

                Button("Export Current Chat") {
                    let md = chatStore.exportActiveSession()
                    let savePanel = NSSavePanel()
                    savePanel.nameFieldStringValue = "Sovereign Chat \(Date().formatted(date: .numeric, time: .omitted)).md"
                    savePanel.allowedContentTypes = [.plainText]
                    savePanel.begin { response in
                        if response == .OK, let url = savePanel.url {
                            try? md.write(to: url, atomically: true, encoding: .utf8)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(chatStore.activeMessages.isEmpty)
            }
            .alert("Clear Current Chat", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { chatStore.clearActiveSession() }
            } message: { Text("This will delete all messages in the current session. This cannot be undone.") }
            .alert("Delete All Chats", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    for session in chatStore.sessions { chatStore.deleteSession(session) }
                }
            } message: { Text("This will permanently delete all chat sessions and messages. This cannot be undone.") }
        }
        .formStyle(.grouped)
    }
}
