import SwiftUI

struct LiveHeartRateCard: View {
    let heartRate: Double
    let history: [Double]
    let isInWorkout: Bool

    @State private var isPulsing = false

    var body: some View {
        GlassPanel(cornerRadius: 24, padding: AppSpacing.xl) {
            HStack(spacing: AppSpacing.xl) {
                // Heart icon with pulse animation
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 100, height: 100)
                        .scaleEffect(isPulsing ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                        .scaleEffect(isPulsing ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                }
                .onAppear { isPulsing = true }

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前心率")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(String(format: "%.0f", heartRate))")
                            .font(AppTypography.scoreLarge)
                        Text("bpm")
                            .font(AppTypography.title3)
                            .foregroundColor(.secondary)
                    }

                    if isInWorkout {
                        Label("运动中", systemImage: "figure.run")
                            .font(AppTypography.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    } else {
                        Label("静息", systemImage: "figure.stand")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }

                Spacer()

                // Mini HR range indicator
                VStack(alignment: .trailing, spacing: 4) {
                    Text("区间")
                        .font(AppTypography.caption2)
                        .foregroundColor(.secondary)
                    Text(hrZoneLabel)
                        .font(AppTypography.title3)
                        .foregroundColor(hrZoneColor)
                }
            }
        }
    }

    private var hrZoneLabel: String {
        if heartRate < 60 { return "静息" }
        if heartRate < 100 { return "轻度" }
        if heartRate < 140 { return "有氧" }
        if heartRate < 170 { return "无氧" }
        return "极限"
    }

    private var hrZoneColor: Color {
        if heartRate < 60 { return .gray }
        if heartRate < 100 { return .blue }
        if heartRate < 140 { return .green }
        if heartRate < 170 { return .orange }
        return .red
    }
}
