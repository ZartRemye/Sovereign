import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var importStatus: ImportStatus = .idle
    @State private var importProgress: Double = 0
    @State private var importMessage: String = ""
    @State private var importResult: DetailedImportResult?
    @State private var isDragging: Bool = false
    @State private var showDiagnostics: Bool = false

    enum ImportStatus: Equatable {
        case idle
        case importing
        case completed
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Text("数据导入")
                    .font(AppTypography.largeTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Current data status
                dataStatusCard

                // Drop zone
                ImportDropZone(
                    isDragging: $isDragging,
                    isImporting: importStatus == .importing,
                    onFileSelected: importFile
                )

                // Progress
                if importStatus == .importing {
                    VStack(spacing: AppSpacing.md) {
                        ProgressView(value: importProgress)
                            .frame(width: 300)
                        Text(importMessage)
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)

                        Button("取消") {
                            importStatus = .idle
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }

                // Result
                if importStatus == .completed, let result = importResult {
                    ImportResultDetailCard(result: result)
                }

                if case .error(let message) = importStatus {
                    CardView {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("导入失败")
                                    .font(AppTypography.headline)
                                Text(message)
                                    .font(AppTypography.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Import diagnostics
                importDiagnosticsSection

                // Instructions
                CardView {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("如何导入 Apple Health 数据")
                            .font(AppTypography.title3)

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            InstructionStep(number: "1", text: "在 iPhone 上打开「健康」App")
                            InstructionStep(number: "2", text: "点击右上角头像")
                            InstructionStep(number: "3", text: "点击「导出所有健康数据」")
                            InstructionStep(number: "4", text: "通过 AirDrop、iCloud 或邮件发送到 Mac")
                            InstructionStep(number: "5", text: "将 export.zip 或 export.xml 拖放到上方区域")
                        }

                        Text("Sovereign 解析：步数、心率、静息心率、HRV、活动能量、运动时间、距离、最大摄氧量、睡眠分析、运动记录、体重、身高。")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, AppSpacing.sm)
                    }
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("数据导入")
    }

    // MARK: - Data Status

    private var dataStatusCard: some View {
        CardView {
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前数据源")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dataSourceColor)
                            .frame(width: 8, height: 8)
                        Text(healthStore.dataSource.rawValue)
                            .font(AppTypography.headline)
                    }
                }

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("数据库")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                    Text("\(healthStore.dbMetricCount) 指标 · \(healthStore.dbWorkoutCount) 运动 · \(healthStore.dbSleepCount) 睡眠 · \(healthStore.dbSummaryCount) 摘要")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }

                if let diag = healthStore.lastImportDiagnostic {
                    Divider().frame(height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近导入")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                        Text("\(diag.fileName) · \(diag.importTime, style: .relative)前")
                            .font(AppTypography.caption)
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var importDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Button(action: { showDiagnostics.toggle() }) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text(showDiagnostics ? "收起导入诊断" : "展开导入诊断")
                    Spacer()
                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                }
                .font(AppTypography.callout)
            }
            .buttonStyle(.plain)

            if showDiagnostics {
                if let diag = healthStore.lastImportDiagnostic {
                    ImportDiagnosticsCard(diagnostic: diag)
                } else {
                    CardView {
                        Text("尚未导入任何数据。导入 Apple Health export.xml 或 ZIP 后将在此显示导入诊断信息。")
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Import Action

    private func importFile(url: URL) {
        importStatus = .importing
        importProgress = 0
        importMessage = "准备导入..."
        importResult = nil

        Task {
            do {
                let result = try await healthStore.importHealthData(from: url) { progress, message in
                    importProgress = progress
                    importMessage = message
                }
                importResult = result
                importStatus = .completed
            } catch {
                importStatus = .error(error.localizedDescription)
            }
        }
    }

    private var dataSourceColor: Color {
        switch healthStore.dataSource {
        case .empty: return .gray
        case .mockLive: return .orange
        case .appleHealthImport: return .green
        case .iphoneSync: return .blue
        case .watchLive: return .purple
        case .unknown: return .gray
        }
    }
}

// MARK: - Import Result Detail

struct ImportResultDetailCard: View {
    let result: DetailedImportResult

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导入完成")
                            .font(AppTypography.title3)
                        Text("文件: \(result.fileName)")
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack(spacing: AppSpacing.xl) {
                    VStack(alignment: .leading) {
                        Text("\(result.totalMetricSamples)").font(AppTypography.title2)
                        Text("指标样本").font(AppTypography.caption).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("\(result.totalWorkouts)").font(AppTypography.title2)
                        Text("运动记录").font(AppTypography.caption).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("\(result.totalSleepSessions)").font(AppTypography.title2)
                        Text("睡眠记录").font(AppTypography.caption).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("\(result.totalDailySummaries)").font(AppTypography.title2)
                        Text("每日摘要").font(AppTypography.caption).foregroundColor(.secondary)
                    }
                }

                if let start = result.dateRangeStart, let end = result.dateRangeEnd {
                    Text("数据范围: \(formatDate(start)) — \(formatDate(end))")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Import Diagnostics Card

struct ImportDiagnosticsCard: View {
    let diagnostic: ImportDiagnostic

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("导入诊断")
                    .font(AppTypography.title3)

                Group {
                    HStack {
                        Text("文件")
                        Spacer()
                        Text(diagnostic.fileName).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("导入时间")
                        Spacer()
                        Text(diagnostic.importTime, style: .date).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(diagnostic.success ? "成功" : "失败")
                            .foregroundColor(diagnostic.success ? .green : .red)
                    }
                    if let start = diagnostic.dateRangeStart, let end = diagnostic.dateRangeEnd {
                        HStack {
                            Text("日期范围")
                            Spacer()
                            Text("\(formatDate(start)) — \(formatDate(end))").foregroundColor(.secondary)
                        }
                    }
                }
                .font(AppTypography.callout)

                if !diagnostic.parsedByType.isEmpty {
                    Divider()
                    Text("解析统计")
                        .font(AppTypography.headline)
                    ForEach(diagnostic.parsedByType.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                        HStack {
                            Text(type)
                                .font(AppTypography.caption)
                            Spacer()
                            Text("\(count) 条")
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !diagnostic.skippedReasons.isEmpty {
                    Divider()
                    Text("跳过原因")
                        .font(AppTypography.headline)
                    ForEach(diagnostic.skippedReasons.sorted(by: { $0.value > $1.value }), id: \.key) { reason, count in
                        HStack {
                            Text(reason)
                                .font(AppTypography.caption)
                            Spacer()
                            Text("\(count) 条")
                                .font(AppTypography.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Divider()
                HStack {
                    Text("数据库当前总量")
                        .font(AppTypography.caption)
                    Spacer()
                    Text("指标: \(diagnostic.totalMetricSamples) · 运动: \(diagnostic.totalWorkouts) · 睡眠: \(diagnostic.totalSleepSessions) · 摘要: \(diagnostic.totalDailySummaries)")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Instruction Step

struct InstructionStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(number)
                .font(AppTypography.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(AppTypography.callout)
        }
    }
}

// MARK: - Import Result (Legacy)

struct ImportResultCard: View {
    let result: ImportSummary

    var body: some View {
        CardView {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("导入完成")
                        .font(AppTypography.title3)
                    Text("文件: \(result.fileName)")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)

                    HStack(spacing: AppSpacing.lg) {
                        Text("\(result.metricSamples) 条指标")
                        Text("\(result.workoutSessions) 条运动")
                        Text("\(result.sleepSessions) 条睡眠")
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)

                    if let (start, end) = result.dateRange {
                        Text("数据范围: \(formatDate(start)) - \(formatDate(end))")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
