import SwiftUI
import Charts

struct ProfileView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @EnvironmentObject var chatStore: ChatSessionStore

    private var profile: PersonalHealthProfile {
        PersonalHealthProfileBuilder().build(
            summaries: healthStore.dailySummaries,
            workouts: healthStore.recentWorkouts,
            sleep: healthStore.recentSleep
        )
    }

    var body: some View {
        ScrollView {
            if healthStore.dataSource == .empty {
                EmptyStateView(systemImage: "person.fill.viewfinder", title: "No health data yet", message: "Import Apple Health data to build your health profile.")
            } else {
                VStack(spacing: AppSpacing.xl) {
                    profileHeader
                    profileTagRow
                    baselineGrid
                    readinessWheel
                    trainingLoadSection
                    sleepConsistencySection
                    workoutIdentitySection
                    strengthsConstraintsSection
                    askCoachButton
                }
                .padding(AppSpacing.xl)
            }
        }
        .navigationTitle("健康画像")
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Health Profile").font(AppTypography.largeTitle)
                HStack(spacing: 8) {
                    HStack(spacing:4){Circle().fill(healthStore.dataSource == .appleHealthImport ? Color.green : healthStore.dataSource == .mockLive ? .orange : .gray).frame(width:6,height:6);Text(healthStore.dataSource.rawValue).font(.caption2).foregroundColor(.secondary)}.padding(.horizontal,8).padding(.vertical,3).background(Color.secondary.opacity(0.08),in:Capsule())
                    if let s = profile.dataRangeStart, let e = profile.dataRangeEnd {
                        Text("\(s.formatted(date: .numeric, time: .omitted)) – \(e.formatted(date: .numeric, time: .omitted))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Text("Completeness \(String(format: "%.0f", profile.dataCompleteness * 100))%")
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: Capsule())
        }
    }

    // MARK: - Profile Tag

    private var profileTagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profile.dominantTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(tagColor(tag).opacity(0.12), in: Capsule())
                        .foregroundColor(tagColor(tag))
                }
            }
        }
    }

    // MARK: - Baseline Grid

    private var baselineGrid: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Health Baseline").font(AppTypography.title3)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.lg) {
                baselineCard("Avg Steps", profile.baselineSteps.map { String(format: "%.0f", $0) } ?? "—", "steps/day", "figure.walk", .mint)
                baselineCard("Avg Sleep", profile.baselineSleepHours.map { String(format: "%.1f", $0) } ?? "—", "hours", "moon.zzz.fill", .indigo)
                baselineCard("Resting HR", profile.baselineRestingHeartRate.map { String(format: "%.0f", $0) } ?? "—", "bpm", "heart.fill", .red)
                baselineCard("HRV", profile.baselineHRV.map { String(format: "%.0f", $0) } ?? "—", "ms", "waveform.path.ecg", .purple)
                baselineCard("Active Energy", profile.baselineActiveEnergy.map { String(format: "%.0f", $0) } ?? "—", "kJ", "flame.fill", .orange)
                baselineCard("Training Load", profile.baselineTrainingLoad.map { String(format: "%.0f", $0) } ?? "—", "pts", "chart.bar.fill", .blue)
            }
        }
    }

    // MARK: - Readiness Wheel

    private var readinessWheel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Readiness & Recovery").font(AppTypography.title3)
            HStack(spacing: AppSpacing.xl) {
                // Recovery ring
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.1), lineWidth: 8).frame(width: 100, height: 100)
                    Circle().trim(from: 0, to: min((profile.currentRecoveryScore ?? 0) / 100, 1))
                        .stroke(recoveryGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(String(format: "%.0f", profile.currentRecoveryScore ?? 0))").font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("Recovery").font(.caption2).foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    profileStatBar("Sleep", score: profile.sleepConsistencyScore ?? 0)
                    profileStatBar("Activity", score: profile.activityConsistencyScore ?? 0)
                    profileStatBar("Cardio", score: profile.cardioStabilityScore ?? 0)
                    profileStatBar("Training", score: profile.trainingRegularityScore ?? 0)
                }
            }
        }
    }

    // MARK: - Training Load

    private var trainingLoadSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Training Load Model").font(AppTypography.title3)
            HStack(spacing: AppSpacing.xl) {
                metricPill("Acute (7d)", profile.acuteTrainingLoad7d.map { String(format: "%.0f", $0) } ?? "—")
                metricPill("Chronic (28d)", profile.chronicTrainingLoad28d.map { String(format: "%.0f", $0) } ?? "—")
                metricPill("ACWR", profile.acuteChronicRatio.map { String(format: "%.2f", $0) } ?? "—")
                Spacer()
                Text(profile.acuteChronicRatio.map { acwr in acwr > 1.5 ? "↑ High Risk" : acwr > 1.2 ? "→ Moderate" : "✓ Optimal" } ?? "—")
                    .font(.headline).foregroundColor(profile.acuteChronicRatio.map { $0 > 1.5 ? Color.red : $0 > 1.2 ? .orange : .green } ?? .secondary)
            }
        }
    }

    // MARK: - Sleep Consistency

    private var sleepConsistencySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Sleep & Activity Patterns").font(AppTypography.title3)
            let recentSummaries = healthStore.dailySummaries.prefix(14)
            if #available(macOS 14.0, *), !recentSummaries.isEmpty {
                Chart {
                    ForEach(Array(recentSummaries), id: \.id) { s in
                        BarMark(x: .value("Date", s.dateFormatted), y: .value("Sleep", s.sleepHours))
                            .foregroundStyle(Color.indigo.opacity(0.5))
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic) }
                .frame(height: 120)
            }
        }
    }

    // MARK: - Workout Identity

    private var workoutIdentitySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Workout Identity").font(AppTypography.title3)
            HStack(spacing: 6) {
                ForEach(profile.dominantWorkoutTypes, id: \.self) { t in
                    Text(t).font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08), in: Capsule())
                }
                if profile.dominantWorkoutTypes.isEmpty {
                    Text("Not enough workout data").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Strengths & Constraints

    private var strengthsConstraintsSection: some View {
        HStack(alignment: .top, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Strengths").font(AppTypography.title3).foregroundColor(.green)
                ForEach(profile.strengths, id: \.self) { s in
                    Label(s, systemImage: "checkmark.circle.fill").font(.callout).foregroundColor(.green)
                }
                if profile.strengths.isEmpty { Text("More data needed").font(.caption).foregroundColor(.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Constraints").font(AppTypography.title3).foregroundColor(.orange)
                ForEach(profile.constraints, id: \.self) { c in
                    Label(c, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundColor(.orange)
                }
                if profile.constraints.isEmpty { Text("No major constraints").font(.caption).foregroundColor(.secondary) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Opportunities").font(AppTypography.title3).foregroundColor(.blue)
                ForEach(profile.opportunities, id: \.self) { o in
                    Label(o, systemImage: "lightbulb.fill").font(.callout).foregroundColor(.blue)
                }
                if profile.opportunities.isEmpty { Text("Import more data").font(.caption).foregroundColor(.secondary) }
            }
        }
    }

    // MARK: - Ask Coach

    private var askCoachButton: some View {
        Button(action: {
            chatStore.createNewSession(runtime: AIRuntimeStatus(providerMode: .localRules, hasAPIKey: false, isCloudAIEnabled: false, modelName: nil, hasRealHealthData: healthStore.hasRealData, dataSource: healthStore.dataSource, dataDateRange: nil))
            chatStore.appendUserMessage("请基于我的健康画像，解释我当前最重要的身体状态、主要限制因素，以及接下来 7 天最值得做的优化。")
        }) {
            Label("Ask Coach to explain my profile", systemImage: "brain.head.profile")
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private func baselineCard(_ title: String, _ value: String, _ unit: String, _ icon: String, _ color: Color) -> some View {
        CardView {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundColor(color).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundColor(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(value).font(.title3.weight(.medium))
                        Text(unit).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func metricPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.medium))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private func profileStatBar(_ label: String, score: Double) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 60, alignment: .leading).foregroundColor(.secondary)
            GeometryReader { g in
                Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(score > 0.7 ? Color.green : score > 0.4 ? .orange : .red).frame(width: g.size.width * score, height: 6)
                    }
            }.frame(width: 120, height: 6)
            Text("\(String(format: "%.0f", score * 100))%").font(.caption2).foregroundColor(.secondary).frame(width: 35, alignment: .trailing)
        }
    }

    private func tagColor(_ tag: String) -> Color {
        if tag.contains("Endurance") || tag.contains("Cardio") { return .blue }
        if tag.contains("Strength") { return .red }
        if tag.contains("Recovery") || tag.contains("Sleep") { return .orange }
        if tag.contains("Rebuild") { return .purple }
        return .gray
    }

    private var recoveryGradient: AngularGradient {
        AngularGradient(colors: [.green, .mint, .yellow, .orange, .red], center: .center)
    }
}
