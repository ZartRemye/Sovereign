import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let color: Color

    var body: some View {
        CardView {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(value)
                            .font(AppTypography.metricValue)
                            .foregroundColor(.primary)
                        if !unit.isEmpty {
                            Text(unit)
                                .font(AppTypography.metricUnit)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
