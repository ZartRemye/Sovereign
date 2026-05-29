import Foundation

/// Orchestrates import of Apple Health data into the app's data store via a callback.
actor HealthImportService {
    static let shared = HealthImportService()
    private let normalizer = HealthDataNormalizer()

    private init() {}

    typealias ImportProgressHandler = (Double, String) -> Void

    func importFile(
        at url: URL,
        progress: @escaping ImportProgressHandler
    ) async throws -> ImportSummary {
        let result: ImportParseResult

        if url.pathExtension.lowercased() == "zip" {
            let importer = AppleHealthZipImporter()
            result = try await importer.importZip(at: url, progress: progress)
        } else if url.lastPathComponent == "export.xml" || url.pathExtension.lowercased() == "xml" {
            progress(0.1, "解析 XML...")
            guard let parser = AppleHealthExportParser(fileURL: url) else {
                throw ImportError(message: "无法读取文件", underlyingError: nil)
            }
            parser.onProgress = { p in progress(0.1 + p * 0.85, "解析中...") }
            result = parser.parse()
        } else {
            throw ImportError(message: "不支持的文件格式。请导入 export.xml 或 Apple Health 导出的 ZIP 文件。", underlyingError: nil)
        }

        if let error = result.parseError {
            if !result.metrics.isEmpty || !result.workouts.isEmpty {
                let summary = ImportSummary(
                    metricSamples: result.metrics.count,
                    workoutSessions: result.workouts.count,
                    sleepSessions: result.sleepSessions.count,
                    dateRange: computeDateRange(metrics: result.metrics),
                    fileName: url.lastPathComponent
                )
                throw error // Caller can still access partial data
            }
            throw error
        }

        progress(1.0, "完成")
        return ImportSummary(
            metricSamples: result.metrics.count,
            workoutSessions: result.workouts.count,
            sleepSessions: result.sleepSessions.count,
            dateRange: computeDateRange(metrics: result.metrics),
            fileName: url.lastPathComponent
        )
    }

    /// Normalize parsed data into app models — returns arrays for caller to persist
    func normalize(
        metrics: [ParsedHealthMetric],
        workouts: [ParsedWorkout],
        sleepRecords: [ParsedSleep]
    ) -> (metrics: [HealthMetricSample], workouts: [WorkoutSession], sleep: [SleepSession]) {
        let normalizedMetrics = normalizer.normalizeMetrics(metrics)
        let normalizedWorkouts = normalizer.normalizeWorkouts(workouts)
        let normalizedSleep = normalizer.normalizeSleep(sleepRecords)
        return (normalizedMetrics, normalizedWorkouts, normalizedSleep)
    }

    private func computeDateRange(metrics: [ParsedHealthMetric]) -> (start: Date, end: Date)? {
        guard let first = metrics.first?.startDate, let last = metrics.last?.endDate else {
            return nil
        }
        return (first, last)
    }
}
