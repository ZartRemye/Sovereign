import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @StateObject private var coordinator = ImportCoordinator.shared
    @State private var isDragging: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var importMode: ImportMode = .incremental

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Text("数据导入")
                    .font(AppTypography.largeTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Import mode picker
                importModePicker

                // Current data status
                dataStatusCard

                // Drop zone
                ImportDropZone(
                    isDragging: $isDragging,
                    isImporting: coordinator.isImporting,
                    onFileSelected: importFile
                )

                // Progress — rich display
                if coordinator.isImporting || coordinator.state.phase == .parsingXML {
                    importProgressCard
                }

                // Result
                if case .completed = coordinator.state, let result = coordinator.latestResult {
                    ImportResultDetailCard(result: result)

                    Button("清除结果") {
                        coordinator.clearLastResult()
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
                }

                if case .failed = coordinator.state, let error = coordinator.errorMessage {
                    CardView {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("导入失败")
                                    .font(AppTypography.headline)
                                Text(error)
                                    .font(AppTypography.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Button("清除错误") {
                        coordinator.clearLastResult()
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.caption)
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
                    }
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("数据导入")
    }

    // MARK: - Import Mode Picker

    private var importModePicker: some View {
        HStack(spacing: AppSpacing.md) {
            Text("导入模式")
                .font(AppTypography.callout)

            Picker("", selection: $importMode) {
                Text("增量导入").tag(ImportMode.incremental)
                Text("全量重建").tag(ImportMode.fullRebuild)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .disabled(coordinator.isImporting)

            Spacer()

            // Checkpoint info
            if importMode == .incremental {
                if let ctx = healthStore.modelContext,
                   let cp = ImportCoordinator.shared.latestCheckpoint(context: ctx) {
                    Text("已有数据至 \(cp.formattedEndDate)")
                        .font(AppTypography.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
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

    // MARK: - Import Progress Card

    private var importProgressCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coordinator.progress.phase.rawValue)
                            .font(AppTypography.headline)
                        if !coordinator.progress.message.isEmpty {
                            Text(coordinator.progress.message)
                                .font(AppTypography.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(coordinator.progress.percentComplete)%")
                        .font(AppTypography.title2)
                        .foregroundColor(.accentColor)
                }

                // Size bar
                VStack(spacing: 4) {
                    ProgressView(value: coordinator.progress.fractionComplete)
                        .tint(.accentColor)

                    HStack {
                        Text("\(coordinator.progress.formattedProcessedSize) / \(coordinator.progress.formattedTotalSize)")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(coordinator.progress.formattedSpeed) · 剩余 \(coordinator.progress.formattedETA)")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Record counters
                HStack(spacing: AppSpacing.xl) {
                    counterView(label: "已扫描", value: coordinator.progress.formattedScanned)
                    counterView(label: "已导入", value: coordinator.progress.formattedImported)
                    counterView(label: "已跳过", value: coordinator.progress.formattedSkipped)
                    if coordinator.progress.workoutsParsed > 0 {
                        counterView(label: "运动", value: "\(coordinator.progress.workoutsParsed)")
                    }
                    if coordinator.progress.sleepRecordsParsed > 0 {
                        counterView(label: "睡眠", value: "\(coordinator.progress.sleepRecordsParsed)")
                    }
                }

                if !coordinator.progress.currentRecordType.isEmpty {
                    HStack {
                        Text("当前: \(coordinator.progress.currentRecordType)")
                            .font(AppTypography.caption2)
                            .foregroundColor(.secondary)
                        if let date = coordinator.progress.currentRecordDate {
                            Text("· \(date, style: .date)")
                                .font(AppTypography.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Background hint
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("你可以切换页面，导入会继续。")
                        .font(AppTypography.caption2)
                }
                .foregroundColor(.secondary.opacity(0.6))

                // Cancel
                Button("取消导入") {
                    coordinator.cancelImport()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func counterView(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppTypography.headline)
            Text(label)
                .font(AppTypography.caption2)
                .foregroundColor(.secondary)
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
                        Text("尚未导入任何数据。")
                            .font(AppTypography.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Import Action

    private func importFile(url: URL) {
        Task {
            await coordinator.startImport(from: url, mode: importMode)
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
                    statView("指标样本", "\(result.totalMetricSamples)")
                    statView("运动记录", "\(result.totalWorkouts)")
                    statView("睡眠记录", "\(result.totalSleepSessions)")
                    statView("每日摘要", "\(result.totalDailySummaries)")
                }

                if let start = result.dateRangeStart, let end = result.dateRangeEnd {
                    Text("数据范围: \(formatDate(start)) — \(formatDate(end))")
                        .font(AppTypography.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func statView(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(AppTypography.title2)
            Text(label).font(AppTypography.caption).foregroundColor(.secondary)
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
                            Text(type).font(AppTypography.caption)
                            Spacer()
                            Text("\(count) 条").font(AppTypography.caption).foregroundColor(.secondary)
                        }
                    }
                }

                if !diagnostic.skippedReasons.isEmpty {
                    Divider()
                    Text("跳过原因")
                        .font(AppTypography.headline)
                    ForEach(diagnostic.skippedReasons.sorted(by: { $0.value > $1.value }), id: \.key) { reason, count in
                        HStack {
                            Text(reason).font(AppTypography.caption)
                            Spacer()
                            Text("\(count) 条").font(AppTypography.caption).foregroundColor(.orange)
                        }
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
