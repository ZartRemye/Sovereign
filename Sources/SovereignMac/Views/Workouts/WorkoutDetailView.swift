import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType.rawValue)
                        .font(AppTypography.title)
                    Text(formatDateTime(workout.startDate))
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    // Key stats
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.lg) {
                        DetailStatCard(
                            title: "时长",
                            value: workout.durationFormatted,
                            systemImage: "clock.fill",
                            color: .blue
                        )
                        if let dist = workout.distanceFormatted {
                            DetailStatCard(
                                title: "距离",
                                value: dist,
                                systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill",
                                color: .green
                            )
                        }
                        if let hr = workout.avgHeartRate {
                            DetailStatCard(
                                title: "平均心率",
                                value: "\(String(format: "%.0f", hr)) bpm",
                                systemImage: "heart.fill",
                                color: .red
                            )
                        }
                        if let maxHR = workout.maxHeartRate {
                            DetailStatCard(
                                title: "最大心率",
                                value: "\(String(format: "%.0f", maxHR)) bpm",
                                systemImage: "heart.circle.fill",
                                color: .pink
                            )
                        }
                        if let energy = workout.activeEnergyKJ {
                            DetailStatCard(
                                title: "消耗能量",
                                value: energy > 4184 ? String(format: "%.0f kcal", energy / 4.184) : "\(String(format: "%.0f", energy)) kJ",
                                systemImage: "flame.fill",
                                color: .orange
                            )
                        }
                        DetailStatCard(
                            title: "训练负荷",
                            value: "\(String(format: "%.0f", workout.trainingLoad))",
                            systemImage: "chart.bar.fill",
                            color: .purple
                        )
                    }

                    // Recovery suggestion
                    CardView {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.blue)
                                Text("恢复建议")
                                    .font(AppTypography.title3)
                            }
                            Text(recoverySuggestion)
                                .font(AppTypography.callout)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Metadata
                    CardView {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("详情")
                                .font(AppTypography.title3)
                            HStack {
                                Text("数据来源")
                                Spacer()
                                Text(workout.source.rawValue)
                                    .foregroundColor(.secondary)
                            }
                            if let notes = workout.notes {
                                HStack {
                                    Text("备注")
                                    Spacer()
                                    Text(notes)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 550)
    }

    private var recoverySuggestion: String {
        let load = workout.trainingLoad
        let durationHours = workout.durationSeconds / 3600

        if load > 150 {
            return "这是一次高强度训练（负荷 \(String(format: "%.0f", load))）。建议：\n- 保证充足睡眠（7-8小时）\n- 适当补充蛋白质和水分\n- 下次高强度训练间隔至少48小时\n这仅是行为建议，不是运动医学指导。"
        } else if load > 80 {
            return "中等强度训练。建议：\n- 充分休息和补水\n- 注意训练后的肌肉恢复\n- 保持规律作息"
        } else {
            return "低到中等强度训练。恢复需求较低，可以较快恢复日常活动。保持活动有助于整体健康。"
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

struct DetailStatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        CardView {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(color)

                Text(value)
                    .font(AppTypography.headline)

                Text(title)
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
