import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var reports: [HealthReport] = []
    @State private var selectedReportType: ReportType = .daily
    @State private var isGenerating = false
    @State private var selectedReport: HealthReport?

    enum ReportType: String, CaseIterable {
        case daily = "日报"
        case weekly = "周报"
        case monthly = "月报"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("健康报告")
                        .font(AppTypography.largeTitle)
                    Text("\(reports.count) 份报告")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()

                HStack(spacing: AppSpacing.md) {
                    Picker("类型", selection: $selectedReportType) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Button(action: generateReport) {
                        Label("生成报告", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }
            }
            .padding()

            Divider()

            if reports.isEmpty && !isGenerating {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: "暂无报告",
                    message: "点击「生成报告」创建你的第一份健康报告。\n每日报告基于最近24小时数据，每周报告基于最近7天数据。",
                    actionLabel: "生成日报",
                    action: generateReport
                )
            } else {
                List {
                    ForEach(reports) { report in
                        ReportRow(report: report)
                            .onTapGesture { selectedReport = report }
                    }
                }
                .listStyle(.inset)
            }

            if isGenerating {
                HStack {
                    ProgressView()
                    Text("正在生成报告...")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("健康报告")
        .sheet(item: $selectedReport) { report in
            ReportDetailView(report: report)
        }
    }

    private func generateReport() {
        isGenerating = true
        Task {
            let reportService = ReportGenerationService.shared

            let report: HealthReport
            switch selectedReportType {
            case .daily:
                let summary = healthStore.todaySummary ?? DailySummary(date: Date())
                report = await reportService.generateDailyReport(
                    date: Date(),
                    summary: summary,
                    insights: healthStore.healthInsights,
                    workouts: healthStore.recentWorkouts,
                    sleepSessions: healthStore.recentSleep
                )
            case .weekly:
                report = await reportService.generateWeeklyReport(
                    weekEnding: Date(),
                    summaries: healthStore.dailySummaries,
                    insights: healthStore.healthInsights,
                    workouts: healthStore.recentWorkouts
                )
            case .monthly:
                report = await reportService.generateMonthlyReport(
                    monthEnding: Date(),
                    summaries: healthStore.dailySummaries,
                    insights: healthStore.healthInsights,
                    workouts: healthStore.recentWorkouts
                )
            }

            reports.insert(report, at: 0)
            isGenerating = false
        }
    }
}

struct ReportRow: View {
    let report: HealthReport

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: report.type == .daily ? "doc.text" : (report.type == .weekly ? "doc.richtext" : "doc.text.magnifyingglass"))
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                    .font(AppTypography.callout.weight(.medium))
                Text("生成时间: \(formatDate(report.generatedAt))")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Text(report.source)
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
