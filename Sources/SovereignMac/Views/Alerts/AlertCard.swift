import SwiftUI

struct AlertCard: View {
    let alert: AlertRecord
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: alertIcon)
                .font(.title3)
                .foregroundColor(alertColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(AppTypography.callout.weight(.semibold))
                    if !alert.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(alert.message)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text(alert.date, style: .relative)
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            if !alert.isRead {
                Button("标记已读") { onDismiss() }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
            }
        }
    }

    private var alertIcon: String {
        switch alert.type {
        case "sleep_deprivation": return "moon.zzz.fill"
        case "recovery_low": return "arrow.triangle.2.circlepath"
        case "training_load_high": return "chart.bar.fill"
        case "inactivity": return "figure.stand"
        case "analysis_complete": return "checkmark.circle.fill"
        case "analysis_failed": return "xmark.circle.fill"
        default: return "bell.fill"
        }
    }

    private var alertColor: Color {
        switch alert.type {
        case "sleep_deprivation": return .indigo
        case "recovery_low": return .red
        case "training_load_high": return .orange
        case "inactivity": return .blue
        case "analysis_complete": return .green
        case "analysis_failed": return .red
        default: return .gray
        }
    }
}
