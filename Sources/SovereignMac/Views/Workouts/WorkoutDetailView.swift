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
                        if let kcal = workout.activeEnergyKcal {
                            DetailStatCard(
                                title: "消耗能量",
                                value: "\(String(format: "%.0f", kcal)) kcal",
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

                    // Training load details
                    CardView {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundColor(.purple)
                                Text("训练负荷")
                                    .font(AppTypography.title3)
                            }
                            HStack {
                                Text("计算方式")
                                Spacer()
                                Text(TrainingLoadAnalyzer.confidence(avgHeartRate: workout.avgHeartRate))
                                    .foregroundColor(.secondary)
                            }
                            .font(AppTypography.callout)
                            Text(recoverySuggestion)
                                .font(AppTypography.callout)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Raw data verification
                    CardView {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundColor(.blue)
                                Text("原始数据核对")
                                    .font(AppTypography.title3)
                            }

                            Divider()

                            Group {
                                // Duration verification
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Duration").font(AppTypography.caption.weight(.semibold)).foregroundColor(.secondary)
                                    HStack {
                                        Text("标准化")
                                        Spacer()
                                        Text(workout.durationFormatted)
                                    }
                                    if let raw = workout.rawDurationFormatted {
                                        HStack {
                                            Text("原始 Apple Health")
                                            Spacer()
                                            Text(raw).foregroundColor(.secondary)
                                        }
                                    }
                                    HStack {
                                        Text("来源")
                                        Spacer()
                                        Text(workout.durationSource ?? "—")
                                            .foregroundColor(.secondary)
                                    }
                                    if let warning = workout.durationWarning {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text(warning)
                                                .foregroundColor(.orange)
                                        }
                                        .font(AppTypography.caption2)
                                    }
                                }

                                Divider()

                                // Date/time
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("时间").font(AppTypography.caption.weight(.semibold)).foregroundColor(.secondary)
                                    HStack {
                                        Text("开始")
                                        Spacer()
                                        Text(formatDateTime(workout.startDate)).foregroundColor(.secondary)
                                    }
                                    HStack {
                                        Text("结束")
                                        Spacer()
                                        Text(formatDateTime(workout.endDate)).foregroundColor(.secondary)
                                    }
                                }

                                // Energy
                                if let rawEnergy = workout.rawEnergyFormatted {
                                    Divider()
                                    HStack {
                                        Text("原始能量")
                                        Spacer()
                                        Text(rawEnergy).foregroundColor(.secondary)
                                    }
                                    if let kcal = workout.activeEnergyKcal {
                                        HStack {
                                            Text("标准化")
                                            Spacer()
                                            Text("\(String(format: "%.0f", kcal)) kcal").foregroundColor(.secondary)
                                        }
                                    }
                                }

                                // Distance
                                if let rawDist = workout.rawDistanceFormatted {
                                    Divider()
                                    HStack {
                                        Text("原始距离")
                                        Spacer()
                                        Text(rawDist).foregroundColor(.secondary)
                                    }
                                    if let dist = workout.distanceFormatted {
                                        HStack {
                                            Text("标准化")
                                            Spacer()
                                            Text(dist).foregroundColor(.secondary)
                                        }
                                    }
                                }

                                // Source
                                Divider()
                                HStack {
                                    Text("来源")
                                    Spacer()
                                    Text(workout.sourceName ?? workout.source.rawValue)
                                        .foregroundColor(.secondary)
                                }

                                if let rawType = workout.rawWorkoutActivityType {
                                    HStack {
                                        Text("原始类型")
                                        Spacer()
                                        Text(rawType).font(AppTypography.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .font(AppTypography.caption)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 600)
    }

    private var recoverySuggestion: String {
        let load = workout.trainingLoad
        let minutes = workout.durationSeconds / 60

        if load > 150 {
            return "高强度训练（\(String(format: "%.0f", load)) 负荷）。建议保证 7-8h 睡眠，补充蛋白质和水分，高强度训练间隔 ≥ 48h。"
        } else if load > 80 {
            return "中等强度。注意充分休息和补水，保持规律作息。"
        } else if load > 20 {
            return "低-中等强度。恢复需求较低，可较快恢复日常活动。"
        } else if minutes < 2 {
            return "⚠️ 时长异常短（\(String(format: "%.1f", minutes)) 分钟）。如果实际运动更长，说明原始数据 unit 解析可能有误。"
        } else {
            return "低强度活动。保持规律运动有助于整体健康。"
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
