import SwiftUI

/// Shows what health data was used to answer a question.
struct ContextPreviewView: View {
    let context: HealthContext

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("AI 回答基于以下数据", systemImage: "info.circle")
                .font(AppTypography.caption.weight(.semibold))

            Group {
                ContextRow(
                    icon: "calendar",
                    label: "数据范围",
                    value: "\(context.dataQuality.dateRangeStart) 至 \(context.dataQuality.dateRangeEnd)"
                )
                ContextRow(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "数据来源",
                    value: context.dataSource
                )
                ContextRow(
                    icon: "exclamationmark.triangle",
                    label: "缺失指标",
                    value: context.dataQuality.missingMetrics.joined(separator: ", ")
                )

                if context.isMockData {
                    ContextRow(
                        icon: "info.circle.fill",
                        label: "数据类型",
                        value: "Mock 模拟数据"
                    )
                }
            }
            .font(AppTypography.caption2)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ContextRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundColor(.secondary)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}
