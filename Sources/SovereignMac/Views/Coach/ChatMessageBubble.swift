import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    @Binding var showDataBasis: UUID?

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant || message.role == .system {
                // Assistant message — left aligned
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: message.isFallback ? "exclamationmark.shield.fill" : "brain.head.profile")
                            .foregroundColor(message.isFallback ? .orange : .accentColor)
                        Text(message.isFallback ? "安全提示" : "Sovereign")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(message.isFallback ? .orange : .accentColor)
                    }

                    Text(message.content)
                        .font(AppTypography.callout)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                        )

                    if let context = message.contextSummary, !context.isEmpty {
                        Button(action: {
                            if showDataBasis == message.id {
                                showDataBasis = nil
                            } else {
                                showDataBasis = message.id
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showDataBasis == message.id ? "chevron.up" : "info.circle")
                                    .font(.caption2)
                                Text(showDataBasis == message.id ? "收起依据" : "数据依据")
                                    .font(AppTypography.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if showDataBasis == message.id {
                            Text(context)
                                .font(AppTypography.caption2)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Text(message.timestamp, style: .time)
                        .font(AppTypography.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            } else {
                // User message — right aligned
                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack {
                        Text("你")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(.blue)
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                    }

                    Text(message.content)
                        .font(AppTypography.callout)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))

                    Text(message.timestamp, style: .time)
                        .font(AppTypography.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .id(message.id)
    }
}
