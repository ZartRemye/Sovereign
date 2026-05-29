import SwiftUI

struct InsightCard: View {
    let insight: HealthInsight

    var body: some View {
        CardView {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: severityIcon)
                    .font(.title3)
                    .foregroundColor(severityColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(AppTypography.headline)

                    Text(insight.message)
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                    if let action = insight.suggestedAction {
                        Text(action)
                            .font(AppTypography.caption)
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                    }

                    HStack {
                        Text("来源: \(insight.sourceRaw)")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("置信度: \(String(format: "%.0f", insight.confidence * 100))%")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var severityIcon: String {
        switch insight.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .positive: return "checkmark.circle.fill"
        }
    }

    private var severityColor: Color {
        switch insight.severity {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        case .positive: return .green
        }
    }
}
