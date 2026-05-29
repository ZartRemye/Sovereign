import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var selectedFilter: WorkoutFilter = .all
    @State private var selectedWorkout: WorkoutSession?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("运动分析")
                            .font(AppTypography.largeTitle)
                        Text("最近 \(filteredWorkouts.count) 条运动记录")
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(WorkoutFilter.allCases) { filter in
                            FilterChip(
                                label: filter.rawValue,
                                systemImage: filter.systemImage,
                                isSelected: selectedFilter == filter,
                                action: { selectedFilter = filter }
                            )
                        }
                    }
                }

                // Workout summary stats
                workoutSummaryCard

                // Workout list
                workoutList
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("运动分析")
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
    }

    private var filteredWorkouts: [WorkoutSession] {
        let workouts = healthStore.recentWorkouts
        switch selectedFilter {
        case .all: return workouts
        case .running: return workouts.filter { $0.workoutType == .running }
        case .walking: return workouts.filter { $0.workoutType == .walking }
        case .cycling: return workouts.filter { $0.workoutType == .cycling }
        case .strength: return workouts.filter { $0.workoutType == .strength }
        case .other: return workouts.filter { !["Running", "Walking", "Cycling", "Strength Training"].contains($0.workoutType.rawValue) }
        }
    }

    // MARK: - Summary Card

    private var workoutSummaryCard: some View {
        CardView {
            HStack(spacing: AppSpacing.xl) {
                SummaryStat(
                    title: "运动次数",
                    value: "\(filteredWorkouts.count)",
                    unit: "次",
                    systemImage: "figure.run",
                    color: .green
                )
                SummaryStat(
                    title: "总时长",
                    value: totalDurationFormatted,
                    unit: "",
                    systemImage: "clock",
                    color: .blue
                )
                SummaryStat(
                    title: "总距离",
                    value: totalDistanceFormatted,
                    unit: "",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    color: .orange
                )
                SummaryStat(
                    title: "总能量",
                    value: totalEnergyFormatted,
                    unit: "",
                    systemImage: "flame",
                    color: .red
                )
            }
        }
    }

    // MARK: - Workout List

    private var workoutList: some View {
        LazyVStack(spacing: AppSpacing.md) {
            ForEach(filteredWorkouts) { workout in
                WorkoutRow(workout: workout)
                    .onTapGesture { selectedWorkout = workout }
            }

            if filteredWorkouts.isEmpty {
                EmptyStateView(
                    systemImage: "figure.run",
                    title: "暂无运动记录",
                    message: "所选分类中没有运动记录。"
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var totalDurationFormatted: String {
        let total = filteredWorkouts.map(\.durationSeconds).reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private var totalDistanceFormatted: String {
        let total = filteredWorkouts.compactMap(\.distanceMeters).reduce(0, +)
        return String(format: "%.1f km", total / 1000)
    }

    private var totalEnergyFormatted: String {
        let total = filteredWorkouts.compactMap(\.activeEnergyKJ).reduce(0, +)
        if total >= 4184 {
            return String(format: "%.0f kcal", total / 4.184)
        }
        return "\(String(format: "%.0f", total)) kJ"
    }
}

// MARK: - Workout Filter

enum WorkoutFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case running = "跑步"
    case walking = "步行"
    case cycling = "骑行"
    case strength = "力量训练"
    case other = "其他"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "figure.mixed.cardio"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell"
        case .other: return "figure.mind.and.body"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(AppTypography.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary Stat

struct SummaryStat: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(color)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppTypography.title3)
                if !unit.isEmpty {
                    Text(unit)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(title)
                .font(AppTypography.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {
    let workout: WorkoutSession

    var body: some View {
        CardView {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: workout.workoutType.systemImage)
                    .font(.title2)
                    .foregroundColor(workoutTypeColor)
                    .frame(width: 40, height: 40)
                    .background(workoutTypeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType.rawValue)
                        .font(AppTypography.headline)

                    HStack(spacing: AppSpacing.lg) {
                        Label(workout.durationFormatted, systemImage: "clock")
                        if let dist = workout.distanceFormatted {
                            Label(dist, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        if let hr = workout.avgHeartRate {
                            Label("\(String(format: "%.0f", hr)) bpm", systemImage: "heart")
                        }
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDate(workout.startDate))
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                    Text("负荷: \(String(format: "%.0f", workout.trainingLoad))")
                        .font(AppTypography.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var workoutTypeColor: Color {
        switch workout.workoutType {
        case .running: return .orange
        case .walking: return .mint
        case .cycling: return .blue
        case .strength, .functionalStrength: return .red
        case .swimming: return .cyan
        case .yoga, .pilates, .taiChi: return .indigo
        case .hiit: return .pink
        case .hiking: return .green
        case .crossTraining, .elliptical, .mixedCardio: return .teal
        case .rowing: return .blue
        case .stairClimbing: return .brown
        case .dance: return .pink
        case .other: return .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}
