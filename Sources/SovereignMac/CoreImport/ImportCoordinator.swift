import Foundation
import SwiftData

// MARK: - Import Coordinator (global, survives page navigation)

@MainActor
final class ImportCoordinator: ObservableObject {
    static let shared = ImportCoordinator()

    @Published var state: ImportState = .idle
    @Published var progress: ImportProgress = .zero
    @Published var latestResult: DetailedImportResult?
    @Published var isImporting: Bool = false
    @Published var errorMessage: String?

    private var cancellationFlag = false
    private var modelContext: ModelContext?

    private init() {}

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Start Import

    func startImport(from url: URL, mode: ImportMode = .incremental) async {
        guard let context = modelContext else {
            errorMessage = "数据库未初始化"
            state = .failed
            return
        }

        cancellationFlag = false
        isImporting = true
        errorMessage = nil
        latestResult = nil
        state = .importing(phase: .validating)
        progress = ImportProgress(
            fileName: url.lastPathComponent,
            fileSizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        )

        let startTime = Date()

        do {
            let service = HealthImportService.shared
            let result = try await service.importAndPersist(
                at: url,
                into: context,
                mode: mode,
                progress: { [weak self] p in
                    guard let self else { return }
                    Task { @MainActor in
                        self.progress = p
                        self.state = .importing(phase: p.phase)
                    }
                },
                isCancelled: { [weak self] in
                    self?.cancellationFlag ?? false
                }
            )

            if cancellationFlag {
                state = .cancelled
                isImporting = false
                return
            }

            latestResult = result
            state = .completed

            // Save import diagnostic
            let diagnostic = ImportDiagnostic(
                fileName: result.fileName,
                importTime: result.importTime,
                success: result.success,
                dateRangeStart: result.dateRangeStart,
                dateRangeEnd: result.dateRangeEnd,
                parsedByType: result.parsedByType,
                savedByType: result.savedByType,
                skippedReasons: result.skippedReasons,
                totalMetricSamples: result.totalMetricSamples,
                totalWorkouts: result.totalWorkouts,
                totalSleepSessions: result.totalSleepSessions,
                totalDailySummaries: result.totalDailySummaries,
                errorMessage: result.parseError
            )
            context.insert(diagnostic)
            try? context.save()

            // Save import checkpoint for incremental imports
            if let endDate = result.dateRangeEnd {
                saveCheckpoint(
                    fileName: result.fileName,
                    fileSize: progress.fileSizeBytes,
                    latestSampleEndDate: endDate,
                    context: context
                )
            }

            // Notify health store to refresh
            await MacHealthStore.shared.refresh()
            await MacHealthStore.shared.runLocalAnalysis()
            await MacHealthStore.shared.detectDataSource()

        } catch is CancellationError {
            state = .cancelled
        } catch {
            state = .failed
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    // MARK: - Cancel

    func cancelImport() {
        cancellationFlag = true
        state = .cancelling
    }

    func clearLastResult() {
        latestResult = nil
        errorMessage = nil
        state = .idle
        progress = .zero
    }

    // MARK: - Checkpoint

    func latestCheckpoint(context: ModelContext) -> ImportCheckpoint? {
        var descriptor = FetchDescriptor<ImportCheckpoint>(sortBy: [SortDescriptor<ImportCheckpoint>(\.lastSuccessfulImportAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func saveCheckpoint(fileName: String, fileSize: Int64, latestSampleEndDate: Date, context: ModelContext) {
        let checkpoint = ImportCheckpoint(
            fileName: fileName,
            fileSize: fileSize,
            lastSuccessfulImportAt: Date(),
            latestSampleEndDate: latestSampleEndDate
        )
        context.insert(checkpoint)
        try? context.save()
    }

    func resetCheckpoint(context: ModelContext) {
        try? context.delete(model: ImportCheckpoint.self)
        try? context.save()
    }
}

// MARK: - Import State

enum ImportState: Equatable {
    case idle
    case importing(phase: ImportPhase)
    case cancelling
    case completed
    case cancelled
    case failed

    var phase: ImportPhase {
        if case .importing(let phase) = self { return phase }
        return .idle
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .importing: return "Importing"
        case .cancelling: return "Cancelling..."
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Import Phase

enum ImportPhase: String, Codable, CaseIterable {
    case idle = "Idle"
    case validating = "Validating file"
    case measuringFile = "Measuring file"
    case unzipping = "Unzipping"
    case locatingExportXML = "Locating export.xml"
    case openingXML = "Opening XML"
    case parsingXML = "Parsing XML records"
    case filteringIncrementalData = "Filtering new data"
    case normalizing = "Normalizing data"
    case deduplicating = "Deduplicating"
    case buildingDailySummaries = "Building daily summaries"
    case saving = "Saving to database"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

// MARK: - Import Progress

struct ImportProgress: Equatable {
    var phase: ImportPhase = .idle
    var message: String = ""

    // File
    var fileName: String = ""
    var fileSizeBytes: Int64 = 0
    var processedBytes: Int64 = 0

    // Records
    var recordsScanned: Int64 = 0
    var recordsImported: Int64 = 0
    var recordsSkipped: Int64 = 0
    var recordsDeduplicated: Int64 = 0
    var workoutsParsed: Int = 0
    var sleepRecordsParsed: Int = 0

    // Current activity
    var currentRecordType: String = ""
    var currentRecordDate: Date?

    // Timing
    var startedAt: Date = Date()
    var lastUpdateAt: Date = Date()
    var bytesPerSecond: Double = 0

    // ETA
    var estimatedSecondsRemaining: TimeInterval?

    static let zero = ImportProgress()

    // Derived
    var fractionComplete: Double {
        guard fileSizeBytes > 0 else { return 0 }
        return min(Double(processedBytes) / Double(fileSizeBytes), 1.0)
    }

    var percentComplete: Int {
        Int(fractionComplete * 100)
    }

    var formattedProcessedSize: String {
        ByteCountFormatterHelper.string(from: processedBytes)
    }

    var formattedTotalSize: String {
        ByteCountFormatterHelper.string(from: fileSizeBytes)
    }

    var formattedSpeed: String {
        guard bytesPerSecond > 0 else { return "—" }
        return "\(ByteCountFormatterHelper.string(from: Int64(bytesPerSecond)))/s"
    }

    var formattedETA: String {
        guard let eta = estimatedSecondsRemaining, eta > 0 else { return "—" }
        if eta < 60 { return "\(Int(eta)) sec" }
        if eta < 3600 {
            let min = Int(eta / 60)
            let sec = Int(eta.truncatingRemainder(dividingBy: 60))
            return "\(min) min \(sec) sec"
        }
        let hr = Int(eta / 3600)
        let min = Int(eta.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hr) hr \(min) min"
    }

    var formattedScanned: String {
        formatCount(recordsScanned)
    }

    var formattedImported: String {
        formatCount(recordsImported)
    }

    var formattedSkipped: String {
        formatCount(recordsSkipped)
    }

    private func formatCount(_ count: Int64) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Import Mode

enum ImportMode {
    case fullRebuild
    case incremental
}

// MARK: - Byte Count Formatter

struct ByteCountFormatterHelper {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Import ETA Estimator

struct ImportETAEstimator {
    private var lastBytes: Int64 = 0
    private var lastTime: Date = Date()
    private var samples: [(Double, Double)] = [] // (time, bytes/sec)

    mutating func update(processedBytes: Int64, totalBytes: Int64, now: Date) -> ImportETA {
        let elapsed = now.timeIntervalSince(lastTime)
        guard elapsed > 0.1 else {
            return ImportETA(speed: 0, remaining: nil, processed: processedBytes, total: totalBytes)
        }

        let bytesDelta = processedBytes - lastBytes
        let speed = Double(bytesDelta) / elapsed

        // Rolling average of last 10 samples
        samples.append((now.timeIntervalSince1970, speed))
        if samples.count > 10 { samples.removeFirst() }
        let avgSpeed = samples.map(\.1).reduce(0, +) / Double(samples.count)

        let remaining = totalBytes > processedBytes
            ? Double(totalBytes - processedBytes) / avgSpeed
            : nil

        lastBytes = processedBytes
        lastTime = now

        return ImportETA(speed: avgSpeed, remaining: remaining, processed: processedBytes, total: totalBytes)
    }
}

struct ImportETA {
    let speed: Double       // bytes/sec
    let remaining: TimeInterval?
    let processed: Int64
    let total: Int64
}

// MARK: - Import Checkpoint Model

@Model
final class ImportCheckpoint {
    var id: UUID = UUID()
    var fileName: String = ""
    var fileSize: Int64 = 0
    var lastSuccessfulImportAt: Date = Date()
    var latestSampleEndDate: Date = Date()

    init(fileName: String, fileSize: Int64, lastSuccessfulImportAt: Date, latestSampleEndDate: Date) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.lastSuccessfulImportAt = lastSuccessfulImportAt
        self.latestSampleEndDate = latestSampleEndDate
    }

    var formattedEndDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: latestSampleEndDate)
    }
}

// MARK: - AI Provider Mode & Runtime Status

enum AIProviderMode: Equatable {
    case localRules
    case deepSeek(model: String)
    case fallback(reason: String)
    case disabled

    var label: String {
        switch self {
        case .localRules: return "Local Rules"
        case .deepSeek(let model): return "DeepSeek (\(model))"
        case .fallback(let reason): return "Fallback — \(reason)"
        case .disabled: return "Disabled"
        }
    }

    var shortLabel: String {
        switch self {
        case .localRules: return "Local"
        case .deepSeek: return "DeepSeek"
        case .fallback: return "Fallback"
        case .disabled: return "Off"
        }
    }

    var isCloud: Bool {
        if case .deepSeek = self { return true }
        return false
    }
}

struct AIRuntimeStatus {
    var providerMode: AIProviderMode = .localRules
    var hasAPIKey: Bool = false
    var isCloudAIEnabled: Bool = false
    var isHealthContextAllowed: Bool = true
    var modelName: String? = "deepseek-v4-pro"
    var baseURL: String? = "https://api.deepseek.com"
    var hasRealHealthData: Bool = false
    var dataSource: DataSource = .empty
    var dataDateRange: ClosedRange<Date>?

    init() {}
    init(providerMode: AIProviderMode, hasAPIKey: Bool, isCloudAIEnabled: Bool, modelName: String?, hasRealHealthData: Bool, dataSource: DataSource, dataDateRange: ClosedRange<Date>?) {
        self.providerMode = providerMode
        self.hasAPIKey = hasAPIKey
        self.isCloudAIEnabled = isCloudAIEnabled
        self.modelName = modelName
        self.hasRealHealthData = hasRealHealthData
        self.dataSource = dataSource
        self.dataDateRange = dataDateRange
    }

    static func current(dataSource: DataSource, summaries: [DailySummary]) async -> AIRuntimeStatus {
        let useDeepSeek = UserDefaults.standard.bool(forKey: "deepseek_enabled")
        let hasKey = await KeychainService.shared.hasAPIKey()
        let modelName = UserDefaults.standard.string(forKey: "deepseek_model") ?? "deepseek-v4-pro"

        let mode: AIProviderMode
        if !useDeepSeek {
            mode = .localRules
        } else if !hasKey {
            mode = .localRules
        } else {
            mode = .deepSeek(model: modelName)
        }

        let dates = summaries.map(\.date)
        let range: ClosedRange<Date>?
        if let minDate = dates.min(), let maxDate = dates.max() {
            range = minDate...maxDate
        } else {
            range = nil
        }

        return AIRuntimeStatus(
            providerMode: mode,
            hasAPIKey: hasKey,
            isCloudAIEnabled: useDeepSeek && hasKey,
            modelName: modelName,
            hasRealHealthData: dataSource == .appleHealthImport,
            dataSource: dataSource,
            dataDateRange: range
        )
    }
}
