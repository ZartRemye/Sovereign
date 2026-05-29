import Foundation
import SwiftData

/// Orchestrates import of Apple Health data — parses, normalizes, deduplicates, persists, builds summaries.
/// Supports both full rebuild and incremental import modes.
actor HealthImportService {
    static let shared = HealthImportService()
    private let normalizer = HealthDataNormalizer()

    private init() {}

    typealias RichProgressHandler = (ImportProgress) -> Void

    // MARK: - Full Import Pipeline (with rich progress)

    func importAndPersist(
        at url: URL,
        into context: ModelContext,
        mode: ImportMode = .incremental,
        progress: @escaping RichProgressHandler,
        isCancelled: @escaping () -> Bool
    ) async throws -> DetailedImportResult {
        var prog = ImportProgress()
        prog.startedAt = Date()
        prog.fileName = url.lastPathComponent
        prog.fileSizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var estimator = ImportETAEstimator()

        // --- Phase 1: Parse ---
        let parseResult: ImportParseResult

        if url.pathExtension.lowercased() == "zip" {
            prog.phase = .unzipping
            prog.message = "Unzipping Apple Health export..."
            progress(prog)

            let importer = AppleHealthZipImporter()
            parseResult = try await importer.importZip(at: url, progress: { pct, msg in
                prog.phase = .unzipping
                prog.message = msg
                prog.processedBytes = Int64(Double(prog.fileSizeBytes) * pct)
                progress(prog)
            })
        } else {
            prog.phase = .openingXML
            prog.message = "Opening export.xml..."
            progress(prog)

            guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                throw ImportError(message: "无法读取文件", underlyingError: nil)
            }
            let actualSize = try fileHandle.seekToEnd()
            try fileHandle.seek(toOffset: 0)
            prog.fileSizeBytes = Int64(actualSize)

            guard let parser = AppleHealthExportParser(stream: fileHandle, estimatedSize: prog.fileSizeBytes) else {
                throw ImportError(message: "无法创建 XML 解析器", underlyingError: nil)
            }

            prog.phase = .parsingXML
            prog.message = "Parsing XML records..."
            progress(prog)

            var lastProgressUpdate = Date()
            parser.onRichProgress = { [weak self] parsedBytes, scanned, imported, skipped, currentType, currentDate in
                let now = Date()
                guard now.timeIntervalSince(lastProgressUpdate) > 0.3 else { return }
                lastProgressUpdate = now

                prog.processedBytes = parsedBytes
                prog.recordsScanned = scanned
                prog.recordsImported = imported
                prog.recordsSkipped = skipped
                prog.currentRecordType = currentType
                prog.currentRecordDate = currentDate
                prog.phase = .parsingXML
                prog.message = "Parsing \(currentType) · \(currentDate?.formatted(date: .numeric, time: .omitted) ?? "")"

                let eta = estimator.update(processedBytes: parsedBytes, totalBytes: prog.fileSizeBytes, now: now)
                prog.bytesPerSecond = eta.speed
                prog.estimatedSecondsRemaining = eta.remaining
                prog.lastUpdateAt = now

                progress(prog)
            }

            parser.onWorkoutParsed = {
                prog.workoutsParsed += 1
            }

            parser.onSleepParsed = {
                prog.sleepRecordsParsed += 1
            }

            parseResult = parser.parse()
        }

        if isCancelled() {
            throw CancellationError()
        }

        if let error = parseResult.parseError, parseResult.metrics.isEmpty {
            throw error
        }

        // Weighted progress helper
        let weights: [ImportPhase: Double] = [
            .validating: 0.01, .measuringFile: 0.01, .unzipping: 0.03, .locatingExportXML: 0.02, .openingXML: 0.02,
            .parsingXML: 0.45,
            .filteringIncrementalData: 0.02,
            .normalizing: 0.05,
            .deduplicating: 0.20,
            .buildingDailySummaries: 0.10,
            .saving: 0.08,
            .completed: 0.01
        ]
        var phaseBase: Double = 0
        func emitProgress(_ phase: ImportPhase, _ fractionWithinPhase: Double, msg: String) {
            let w = weights[phase] ?? 0.02
            let pct = min(phaseBase + w * max(0, min(1, fractionWithinPhase)), 0.995)
            prog.phase = phase
            prog.message = msg
            prog.processedBytes = Int64(pct * Double(prog.fileSizeBytes))
            prog.fractionComplete = pct
            progress(prog)
        }
        func endPhase(_ phase: ImportPhase) { phaseBase += weights[phase] ?? 0.02 }

        // --- Phase 2: Filter for incremental ---
        let metricsToProcess: [ParsedHealthMetric]
        let filterSkipCount: Int64

        if mode == .incremental, let checkpoint = await latestCheckpoint(context: context) {
            prog.phase = .filteringIncrementalData
            prog.message = "Filtering new records since \(checkpoint.formattedEndDate)..."
            progress(prog)

            let cutoff = checkpoint.latestSampleEndDate.addingTimeInterval(-86400) // 1 day buffer
            metricsToProcess = parseResult.metrics.filter { $0.startDate > cutoff }
            filterSkipCount = Int64(parseResult.metrics.count - metricsToProcess.count)
            prog.recordsSkipped += filterSkipCount
        } else {
            metricsToProcess = parseResult.metrics
            filterSkipCount = 0
        }

        // --- Phase 3: Normalize ---
        prog.phase = .normalizing
        prog.message = "Normalizing \(metricsToProcess.count) records..."
        progress(prog)

        let allWorkouts = parseResult.workouts
        let allSleep = parseResult.sleepSessions
        let (normalizedMetrics, normalizedWorkouts, normalizedSleep) = normalizer.normalize(
            metrics: metricsToProcess,
            workouts: allWorkouts,
            sleepRecords: allSleep
        )

        // --- Phase 4: Dedup and persist ---
        endPhase(.normalizing)
        let totalForDedup = metricsToProcess.count + allWorkouts.count + allSleep.count
        prog.phaseTotalRecords = Int64(totalForDedup)
        emitProgress(.deduplicating, 0, msg: "Deduplicating \(totalForDedup) records...")

        let stats = await deduplicateAndPersist(
            metrics: normalizedMetrics,
            workouts: normalizedWorkouts,
            sleep: normalizedSleep,
            into: context,
            progress: { processed, deduped in
                let frac = totalForDedup > 0 ? Double(processed) / Double(totalForDedup) : 0
                emitProgress(.deduplicating, frac, msg: "Checked \(processed)/\(totalForDedup) · Duplicates: \(deduped)")
            }
        )
        endPhase(.deduplicating)

        // --- Phase 5: Build daily summaries ---
        prog.phase = .buildingDailySummaries
        prog.message = "Building daily summaries..."
        progress(prog)

        let summaryStartDate: Date
        if mode == .incremental, let checkpoint = await latestCheckpoint(context: context) {
            summaryStartDate = checkpoint.latestSampleEndDate.addingTimeInterval(-86400 * 7)
        } else {
            summaryStartDate = stats.dateRangeStart ?? Date().addingTimeInterval(-90 * 86400)
        }

        let summaries = await buildDailySummaries(
            from: summaryStartDate,
            to: Date(),
            context: context,
            mode: mode
        )

        // --- Phase 6: Save ---
        prog.phase = .saving
        prog.message = "Saving \(summaries.count) daily summaries..."
        progress(prog)

        if mode == .fullRebuild {
            try? context.delete(model: DailySummary.self)
        } else {
            // Delete only affected date range summaries
            let deletePredicate = #Predicate<DailySummary> { $0.date >= summaryStartDate }
            try? context.delete(model: DailySummary.self, where: deletePredicate)
        }

        for summary in summaries {
            context.insert(summary)
        }
        try? context.save()

        prog.phase = .completed
        prog.message = "Import complete"
        progress(prog)

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

    // MARK: - Checkpoint

    private func latestCheckpoint(context: ModelContext) async -> ImportCheckpoint? {
        var descriptor = FetchDescriptor<ImportCheckpoint>(sortBy: [SortDescriptor<ImportCheckpoint>(\.lastSuccessfulImportAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
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
        into context: ModelContext,
        progress: ((_ processed: Int, _ deduped: Int64) -> Void)? = nil
    ) async -> PersistStats {
        var savedMetrics = 0
        var savedWorkouts = 0
        var savedSleep = 0
        var deduped: Int64 = 0
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

        // Batch insert for performance
        var metricBatch: [HealthMetricSample] = []
        var workoutBatch: [WorkoutSession] = []
        var sleepBatch: [SleepSession] = []

        for metric in metrics {
            let fp = metricFingerprint(metric)
            if metricFingerprints.contains(fp) {
                skippedReasons["重复数据", default: 0] += 1
                deduped += 1
                continue
            }
            metricBatch.append(metric)
            savedMetrics += 1
            savedByType[metric.metricTypeRaw, default: 0] += 1

            if dateRangeStart == nil || metric.date < dateRangeStart! { dateRangeStart = metric.date }
            if dateRangeEnd == nil || metric.date > dateRangeEnd! { dateRangeEnd = metric.date }

            // Flush batch periodically
            if metricBatch.count >= 500 {
                for m in metricBatch { context.insert(m) }
                metricBatch.removeAll()
                try? context.save()
                progress?(savedMetrics + savedWorkouts + savedSleep, deduped)
            }
        }
        for m in metricBatch { context.insert(m) }

        for workout in workouts {
            let fp = workoutFingerprint(workout)
            if workoutFingerprints.contains(fp) {
                skippedReasons["重复运动", default: 0] += 1
                deduped += 1
                continue
            }
            workoutBatch.append(workout)
            savedWorkouts += 1
            savedByType["Workout_\(workout.workoutTypeRaw)", default: 0] += 1
            if workoutBatch.count >= 100 { for w in workoutBatch { context.insert(w) }; workoutBatch.removeAll() }
        }
        for w in workoutBatch { context.insert(w) }

        for s in sleep {
            let fp = sleepFingerprint(s)
            if sleepFingerprints.contains(fp) {
                skippedReasons["重复睡眠", default: 0] += 1
                deduped += 1
                continue
            }
            sleepBatch.append(s)
            savedSleep += 1
            if sleepBatch.count >= 100 { for s in sleepBatch { context.insert(s) }; sleepBatch.removeAll() }
        }
        for s in sleepBatch { context.insert(s) }

        try? context.save()
        progress?(savedMetrics + savedWorkouts + savedSleep, deduped)

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
        context: ModelContext,
        mode: ImportMode = .fullRebuild
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
