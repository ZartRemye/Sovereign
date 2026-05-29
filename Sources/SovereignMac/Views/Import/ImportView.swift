import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var healthStore: MacHealthStore
    @State private var importStatus: ImportStatus = .idle
    @State private var importProgress: Double = 0
    @State private var importMessage: String = ""
    @State private var importResult: ImportSummary?
    @State private var isDragging: Bool = false

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
                    ImportResultCard(result: result)
                }

                if case .error(let message) = importStatus {
                    CardView {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("导入失败")
                                    .font(AppTypography.headline)
                                Text(message)
                                    .font(AppTypography.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

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

                        Text("Sovereign 只解析以下数据类型：步数、心率、静息心率、HRV、活动能量、运动时间、距离、最大摄氧量、睡眠分析、运动记录。")
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

    private func importFile(url: URL) {
        importStatus = .importing
        importProgress = 0
        importMessage = "准备导入..."

        Task {
            do {
                let service = HealthImportService.shared
                let result = try await service.importFile(at: url) { progress, message in
                    importProgress = progress
                    importMessage = message
                }

                importResult = result
                importStatus = .completed

                // Trigger data refresh
                await healthStore.refresh()
                await healthStore.runLocalAnalysis()
            } catch {
                importStatus = .error(error.localizedDescription)
            }
        }
    }
}

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
