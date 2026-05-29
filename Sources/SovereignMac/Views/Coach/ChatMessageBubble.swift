import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant || message.role == .system {
                // Assistant message — left aligned
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.accentColor)
                        Text("Sovereign")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }

                    Text(message.content)
                        .font(AppTypography.callout)
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                        )

                    if let context = message.contextSummary {
                        Text(context)
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
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
