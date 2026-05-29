import Foundation
import SwiftData

/// Orchestrates import of Apple Health data — parses, normalizes, deduplicates, persists, builds summaries.
actor HealthImportService {
    static let shared = HealthImportService()
    private let normalizer = HealthDataNormalizer()

    private init() {}

    typealias ImportProgressHandler = (Double, String) -> Void

    // MARK: - Full Import Pipeline (parse + normalize + persist)

    func importAndPersist(
        at url: URL,
        into context: ModelContext,
        progress: @escaping ImportProgressHandler
    ) async throws -> DetailedImportResult {
        // Phase 1: Parse
        let parseResult: ImportParseResult
        if url.pathExtension.lowercased() == "zip" {
            let importer = AppleHealthZipImporter()
            parseResult = try await importer.importZip(at: url, progress: progress)
        } else if url.lastPathComponent == "export.xml" || url.pathExtension.lowercased() == "xml" {
            progress(0.0, "解析 XML...")
            guard let parser = AppleHealthExportParser(fileURL: url) else {
                throw ImportError(message: "无法读取文件", underlyingError: nil)
            }
            parser.onProgress = { p in progress(0.05 + p * 0.45, "解析中...") }
            parseResult = parser.parse()
        } else {
            throw ImportError(message: "不支持的文件格式。请导入 export.xml 或 Apple Health 导出的 ZIP 文件。", underlyingError: nil)
        }

        if let error = parseResult.parseError, parseResult.metrics.isEmpty {
            throw error
        }

        // Phase 2: Normalize
        progress(0.50, "标准化数据...")
        let (normalizedMetrics, normalizedWorkouts, normalizedSleep) = normalizer.normalize(
            metrics: parseResult.metrics,
            workouts: parseResult.workouts,
            sleepRecords: parseResult.sleepSessions
        )

        // Phase 3: Dedup and persist
        progress(0.60, "去重并保存...")
        let stats = await deduplicateAndPersist(
            metrics: normalizedMetrics,
            workouts: normalizedWorkouts,
            sleep: normalizedSleep,
            into: context
        )

        // Phase 4: Build daily summaries
        progress(0.80, "生成每日摘要...")
        let summaries = await buildDailySummaries(
            from: stats.dateRangeStart ?? Date().addingTimeInterval(-90 * 86400),
            to: Date(),
            context: context
        )

        progress(0.95, "保存摘要...")
        // Delete old summaries and insert new ones
        try? context.delete(model: DailySummary.self)
        for summary in summaries {
            context.insert(summary)
        }
        try? context.save()

        progress(1.0, "完成")

        return DetailedImportResult(
            fileName: url.lastPathComponent,
            importTime: Date(),
            success: parseResult.parseError == nil,
            dateRangeStart: stats.dateRangeStart,
            dateRangeEnd: stats.dateRangeEnd,
            parsedByType: parseResult.parsedByType,
            savedByType: stats.savedByType,
            skippedReasons: stats.skippedReasons,
            totalMetricSamples: stats.savedMetrics,
            totalWorkouts: stats.savedWorkouts,
            totalSleepSessions: stats.savedSleep,
            totalDailySummaries: summaries.count,
            parseError: parseResult.parseError?.message
        )
    }

    // MARK: - Legacy import (parse only, for diagnostics)

    func importFile(
        at url: URL,
        progress: @escaping ImportProgressHandler
    ) async throws -> ImportSummary {
        let parseResult: ImportParseResult

        if url.pathExtension.lowercased() == "zip" {
            let importer = AppleHealthZipImporter()
            parseResult = try await importer.importZip(at: url, progress: progress)
        } else if url.lastPathComponent == "export.xml" || url.pathExtension.lowercased() == "xml" {
            progress(0.1, "解析 XML...")
            guard let parser = AppleHealthExportParser(fileURL: url) else {
                throw ImportError(message: "无法读取文件", underlyingError: nil)
            }
            parser.onProgress = { p in progress(0.1 + p * 0.85, "解析中...") }
            parseResult = parser.parse()
        } else {
            throw ImportError(message: "不支持的文件格式。请导入 export.xml 或 Apple Health 导出的 ZIP 文件。", underlyingError: nil)
        }

        if let error = parseResult.parseError {
            throw error
        }

        return ImportSummary(
            metricSamples: parseResult.metrics.count,
            workoutSessions: parseResult.workouts.count,
            sleepSessions: parseResult.sleepSessions.count,
            dateRange: computeDateRange(metrics: parseResult.metrics),
            fileName: url.lastPathComponent
        )
    }

    // MARK: - Normalize (public for external use)

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

    // MARK: - Dedup + Persist

    private func deduplicateAndPersist(
        metrics: [HealthMetricSample],
        workouts: [WorkoutSession],
        sleep: [SleepSession],
        into context: ModelContext
    ) async -> PersistStats {
        var savedMetrics = 0
        var savedWorkouts = 0
        var savedSleep = 0
        var savedByType: [String: Int] = [:]
        var skippedReasons: [String: Int] = [:]
        var dateRangeStart: Date?
        var dateRangeEnd: Date?

        // Load existing fingerprints for dedup
        let existingMetrics = (try? context.fetch(FetchDescriptor<HealthMetricSample>())) ?? []
        let existingWorkouts = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let existingSleep = (try? context.fetch(FetchDescriptor<SleepSession>())) ?? []

        let metricFingerprints = Set(existingMetrics.map { metricFingerprint($0) })
        let workoutFingerprints = Set(existingWorkouts.map { workoutFingerprint($0) })
        let sleepFingerprints = Set(existingSleep.map { sleepFingerprint($0) })

        // Insert metrics with dedup
        for metric in metrics {
            let fp = metricFingerprint(metric)
            if metricFingerprints.contains(fp) {
                skippedReasons["重复数据", default: 0] += 1
                continue
            }
            context.insert(metric)
            savedMetrics += 1
            savedByType[metric.metricTypeRaw, default: 0] += 1

            if dateRangeStart == nil || metric.date < dateRangeStart! {
                dateRangeStart = metric.date
            }
            if dateRangeEnd == nil || metric.date > dateRangeEnd! {
                dateRangeEnd = metric.date
            }
        }

        // Insert workouts with dedup
        for workout in workouts {
            let fp = workoutFingerprint(workout)
            if workoutFingerprints.contains(fp) {
                skippedReasons["重复运动", default: 0] += 1
                continue
            }
            context.insert(workout)
            savedWorkouts += 1
            savedByType["Workout_\(workout.workoutTypeRaw)", default: 0] += 1

            if dateRangeStart == nil || workout.startDate < dateRangeStart! {
                dateRangeStart = workout.startDate
            }
            if dateRangeEnd == nil || workout.endDate > dateRangeEnd! {
                dateRangeEnd = workout.endDate
            }
        }

        // Insert sleep with dedup
        for s in sleep {
            let fp = sleepFingerprint(s)
            if sleepFingerprints.contains(fp) {
                skippedReasons["重复睡眠", default: 0] += 1
                continue
            }
            context.insert(s)
            savedSleep += 1
            savedByType["SleepSession", default: 0] += 1
        }

        try? context.save()

        return PersistStats(
            savedMetrics: savedMetrics,
            savedWorkouts: savedWorkouts,
            savedSleep: savedSleep,
            savedByType: savedByType,
            skippedReasons: skippedReasons,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd
        )
    }

    // MARK: - Fingerprints

    private func metricFingerprint(_ m: HealthMetricSample) -> String {
        "\(m.sourceRaw)|\(m.metricTypeRaw)|\(Int(m.date.timeIntervalSince1970))|\(String(format: "%.3f", m.value))|\(m.unit)"
    }

    private func workoutFingerprint(_ w: WorkoutSession) -> String {
        "\(w.sourceRaw)|\(w.workoutTypeRaw)|\(Int(w.startDate.timeIntervalSince1970))|\(Int(w.endDate.timeIntervalSince1970))|\(String(format: "%.1f", w.durationSeconds))|\(String(format: "%.1f", w.distanceMeters ?? 0))|\(String(format: "%.1f", w.activeEnergyKJ ?? 0))"
    }

    private func sleepFingerprint(_ s: SleepSession) -> String {
        "\(s.sourceRaw)|\(Int(s.startDate.timeIntervalSince1970))|\(Int(s.endDate.timeIntervalSince1970))|\(String(format: "%.1f", s.durationSeconds))"
    }

    // MARK: - Daily Summary Builder

    private func buildDailySummaries(
        from startDate: Date,
        to endDate: Date,
        context: ModelContext
    ) async -> [DailySummary] {
        let calendar = Calendar.current
        let allMetrics = (try? context.fetch(FetchDescriptor<HealthMetricSample>())) ?? []
        let allWorkouts = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let allSleep = (try? context.fetch(FetchDescriptor<SleepSession>())) ?? []

        var summaries: [DailySummary] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        while currentDate <= endDay {
            let summary = DailySummaryBuilder.build(
                date: currentDate,
                metrics: allMetrics,
                workouts: allWorkouts,
                sleepSessions: allSleep,
                previousSummaries: summaries
            )
            summaries.append(summary)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return summaries
    }

    // MARK: - Helpers

    private func computeDateRange(metrics: [ParsedHealthMetric]) -> (start: Date, end: Date)? {
        guard let first = metrics.first?.startDate, let last = metrics.last?.endDate else {
            return nil
        }
        return (first, last)
    }
}

// MARK: - Detailed Import Result (for diagnostics)

struct DetailedImportResult {
    let fileName: String
    let importTime: Date
    let success: Bool
    let dateRangeStart: Date?
    let dateRangeEnd: Date?
    let parsedByType: [String: Int]
    let savedByType: [String: Int]
    let skippedReasons: [String: Int]
    let totalMetricSamples: Int
    let totalWorkouts: Int
    let totalSleepSessions: Int
    let totalDailySummaries: Int
    let parseError: String?
}

// MARK: - Internal persist stats

private struct PersistStats {
    let savedMetrics: Int
    let savedWorkouts: Int
    let savedSleep: Int
    let savedByType: [String: Int]
    let skippedReasons: [String: Int]
    let dateRangeStart: Date?
    let dateRangeEnd: Date?
}
