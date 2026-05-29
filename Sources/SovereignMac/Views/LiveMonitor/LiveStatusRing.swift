import SwiftUI

struct LiveStatusRing: View {
    let title: String
    let value: Double
    let maxValue: Double
    let color: Color
    var valueFormatter: ((Double) -> String)?

    var body: some View {
        CardView {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: min(value / max(maxValue, 1), 1.0))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))

                    if let formatter = valueFormatter {
                        Text(formatter(value))
                            .font(AppTypography.caption.weight(.bold))
                    } else {
                        Text("\(String(format: "%.0f", value))")
                            .font(AppTypography.title2)
                    }
                }

                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
