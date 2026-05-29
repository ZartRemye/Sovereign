import Foundation

/// Stream-based Apple Health Export XML parser using Foundation's XMLParser (SAX-style).
/// Tracks byte-level progress via a ProgressTrackingInputStream wrapper.
final class AppleHealthExportParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var parsedMetrics: [ParsedHealthMetric] = []
    private var parsedWorkouts: [ParsedWorkout] = []
    private var parsedSleep: [ParsedSleep] = []

    /// Per-type parse counts for diagnostics
    private(set) var parsedByType: [String: Int] = [:]
    /// Skipped records with reasons for diagnostics
    private(set) var skippedReasons: [String: Int] = [:]

    private var currentElement = ""
    private var currentAttributes: [String: String] = [:]
    private var currentText = ""

    // Record type being parsed
    private var currentRecordType = ""
    private var currentRecordValue = ""
    private var currentRecordUnit = ""
    private var currentRecordStartDate = ""
    private var currentRecordEndDate = ""
    private var currentRecordSourceName = ""
    private var currentRecordDevice: String?

    // Workout fields
    private var currentWorkoutType = ""
    private var currentWorkoutDuration = ""
    private var currentWorkoutDurationUnit = ""
    private var currentWorkoutDistance = ""
    private var currentWorkoutDistanceUnit = ""
    private var currentWorkoutEnergy = ""
    private var currentWorkoutEnergyUnit = ""

    // Progress tracking
    private let progressStream: ProgressTrackingInputStream?
    private let estimatedSize: Int64

    // Counters
    private(set) var recordsScanned: Int64 = 0
    private(set) var recordsImported: Int64 = 0
    private(set) var recordsSkipped: Int64 = 0

    // Rich progress callbacks
    var onRichProgress: ((_ parsedBytes: Int64, _ scanned: Int64, _ imported: Int64, _ skipped: Int64, _ currentType: String, _ currentDate: Date?) -> Void)?
    var onWorkoutParsed: (() -> Void)?
    var onSleepParsed: (() -> Void)?
    var isCancelled = false

    /// Initialize with a file stream for byte-level progress
    init?(stream: FileHandle, estimatedSize: Int64) {
        self.estimatedSize = estimatedSize
        let trackingStream = ProgressTrackingInputStream(fileHandle: stream, totalSize: estimatedSize)
        self.progressStream = trackingStream

        let parser = XMLParser(stream: trackingStream)
        self.parser = parser
        super.init()
        self.parser.delegate = self
    }

    /// Initialize from file URL (legacy, no byte progress)
    init?(fileURL: URL) {
        self.estimatedSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        self.progressStream = nil
        guard let parser = XMLParser(contentsOf: fileURL) else { return nil }
        self.parser = parser
        super.init()
        self.parser.delegate = self
    }

    /// Initialize from Data
    init(data: Data) {
        self.estimatedSize = Int64(data.count)
        self.progressStream = nil
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> ImportParseResult {
        let success = parser.parse()
        if isCancelled {
            return makeResult(error: ImportError(message: "导入已取消", underlyingError: nil))
        }
        if !success, let error = parser.parserError {
            return makeResult(error: ImportError(message: "XML 解析错误: \(error.localizedDescription)", underlyingError: error))
        }
        return makeResult(error: nil)
    }

    private func makeResult(error: ImportError?) -> ImportParseResult {
        ImportParseResult(
            metrics: parsedMetrics,
            workouts: parsedWorkouts,
            sleepSessions: parsedSleep,
            parsedByType: parsedByType,
            skippedReasons: skippedReasons,
            parseError: error
        )
    }

    /// Current byte position from the progress stream
    var currentBytePosition: Int64 {
        progressStream?.bytesRead ?? 0
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentAttributes = attributeDict
        currentText = ""

        if elementName == "Record" {
            currentRecordType = attributeDict["type"] ?? ""
            currentRecordValue = attributeDict["value"] ?? ""
            currentRecordUnit = attributeDict["unit"] ?? ""
            currentRecordStartDate = attributeDict["startDate"] ?? ""
            currentRecordEndDate = attributeDict["endDate"] ?? ""
            currentRecordSourceName = attributeDict["sourceName"] ?? ""
            currentRecordDevice = attributeDict["device"]
        } else if elementName == "Workout" {
            currentWorkoutType = attributeDict["workoutActivityType"] ?? ""
            currentWorkoutDuration = attributeDict["duration"] ?? ""
            currentWorkoutDurationUnit = attributeDict["durationUnit"] ?? ""
            currentWorkoutDistance = attributeDict["totalDistance"] ?? ""
            currentWorkoutDistanceUnit = attributeDict["totalDistanceUnit"] ?? ""
            currentWorkoutEnergy = attributeDict["totalEnergyBurned"] ?? ""
            currentWorkoutEnergyUnit = attributeDict["totalEnergyBurnedUnit"] ?? ""
            currentRecordStartDate = attributeDict["startDate"] ?? ""
            currentRecordEndDate = attributeDict["endDate"] ?? ""
            currentRecordSourceName = attributeDict["sourceName"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Record" {
            recordsScanned += 1
            processRecord()
        } else if elementName == "Workout" {
            recordsScanned += 1
            processWorkout()
        }

        // Report rich progress periodically (throttled by caller via onRichProgress callback)
        if recordsScanned % 2000 == 0, let stream = progressStream {
            let date = parseHealthDate(currentRecordStartDate)
            let displayType = displayNameShort(currentRecordType)
            onRichProgress?(stream.bytesRead, recordsScanned, recordsImported, recordsSkipped, displayType, date)
        }
    }

    // MARK: - Processing

    private func processRecord() {
        let rawType = currentRecordType

        guard let matchedType = matchSupportedType(rawType) else {
            skippedReasons["不支持的类型", default: 0] += 1
            recordsSkipped += 1
            return
        }

        // Sleep records (categorical)
        if matchedType == "HKCategoryTypeIdentifierSleepAnalysis" {
            guard let startDate = parseHealthDate(currentRecordStartDate),
                  let endDate = parseHealthDate(currentRecordEndDate) else {
                skippedReasons["日期解析失败", default: 0] += 1
                recordsSkipped += 1
                return
            }

            let sleepValue = parseSleepCategory(currentRecordValue)

            let metric = ParsedHealthMetric(
                type: matchedType,
                value: sleepValue,
                unit: "category",
                startDate: startDate,
                endDate: endDate,
                sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName,
                device: currentRecordDevice
            )
            parsedMetrics.append(metric)
            parsedByType["SleepAnalysis", default: 0] += 1
            recordsImported += 1

            let sleep = ParsedSleep(
                startDate: startDate,
                endDate: endDate,
                value: sleepValue,
                category: currentRecordValue,
                sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName
            )
            parsedSleep.append(sleep)
            onSleepParsed?()
            return
        }

        // Regular quantitative metrics
        guard let value = Double(currentRecordValue) else {
            skippedReasons["数值解析失败", default: 0] += 1
            recordsSkipped += 1
            return
        }

        guard let startDate = parseHealthDate(currentRecordStartDate) else {
            skippedReasons["日期解析失败", default: 0] += 1
            recordsSkipped += 1
            return
        }

        let endDate = parseHealthDate(currentRecordEndDate) ?? startDate
        let unit = currentRecordUnit.isEmpty ? standardUnit(for: matchedType) : currentRecordUnit

        let metric = ParsedHealthMetric(
            type: matchedType,
            value: value,
            unit: unit,
            startDate: startDate,
            endDate: endDate,
            sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName,
            device: currentRecordDevice
        )
        parsedMetrics.append(metric)
        recordsImported += 1

        let displayType = displayName(for: matchedType)
        parsedByType[displayType, default: 0] += 1
    }

    private func processWorkout() {
        guard let startDate = parseHealthDate(currentRecordStartDate),
              let endDate = parseHealthDate(currentRecordEndDate) else {
            skippedReasons["运动日期解析失败", default: 0] += 1
            recordsSkipped += 1
            return
        }

        let typeName = normalizeWorkoutType(currentWorkoutType)
        let rawDuration = Double(currentWorkoutDuration)
        let rawDurationUnit = currentWorkoutDurationUnit.isEmpty ? nil : currentWorkoutDurationUnit
        let dateBasedSeconds = endDate.timeIntervalSince(startDate)

        let rawDistance = Double(currentWorkoutDistance)
        let rawDistanceUnit = currentWorkoutDistanceUnit.isEmpty ? nil : currentWorkoutDistanceUnit
        let rawEnergy = Double(currentWorkoutEnergy)
        let rawEnergyUnit = currentWorkoutEnergyUnit.isEmpty ? nil : currentWorkoutEnergyUnit

        let workout = ParsedWorkout(
            type: typeName,
            originalType: currentWorkoutType,
            startDate: startDate,
            endDate: endDate,
            rawDuration: rawDuration,
            rawDurationUnit: rawDurationUnit,
            dateBasedDurationSeconds: dateBasedSeconds,
            rawDistance: rawDistance,
            rawDistanceUnit: rawDistanceUnit,
            rawEnergy: rawEnergy,
            rawEnergyUnit: rawEnergyUnit,
            avgHeartRate: nil,
            maxHeartRate: nil,
            sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName
        )
        parsedWorkouts.append(workout)
        recordsImported += 1
        parsedByType["Workout_\(typeName)", default: 0] += 1
        onWorkoutParsed?()
    }

    // MARK: - Type Matching

    private let supportedTypePatterns: Set<String> = [
        "HKQuantityTypeIdentifierStepCount",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierRestingHeartRate",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKQuantityTypeIdentifierAppleExerciseTime",
        "HKQuantityTypeIdentifierDistanceWalkingRunning",
        "HKQuantityTypeIdentifierDistanceCycling",
        "HKQuantityTypeIdentifierVO2Max",
        "HKQuantityTypeIdentifierBodyMass",
        "HKQuantityTypeIdentifierHeight",
        "HKCategoryTypeIdentifierSleepAnalysis",
    ]

    // Cached lowercased set for fast lookup
    private lazy var lowercasedPatterns: Set<String> = {
        Set(supportedTypePatterns.map { $0.lowercased() })
    }()

    private lazy var simplifiedPatterns: [(String, String)] = {
        supportedTypePatterns.map { pattern in
            let simple = pattern
                .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
                .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
            return (simple, pattern)
        }
    }()

    private func matchSupportedType(_ raw: String) -> String? {
        // Fast path: exact match
        if supportedTypePatterns.contains(raw) { return raw }

        // Case-insensitive
        let lowercased = raw.lowercased()
        if lowercasedPatterns.contains(lowercased) {
            return supportedTypePatterns.first { $0.lowercased() == lowercased }
        }

        // Partial match
        let simplified = raw
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")

        for (simple, pattern) in simplifiedPatterns {
            if simplified.caseInsensitiveCompare(simple) == .orderedSame {
                return pattern
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func standardUnit(for type: String) -> String {
        switch type {
        case "HKQuantityTypeIdentifierStepCount": return "count"
        case "HKQuantityTypeIdentifierHeartRate": return "count/min"
        case "HKQuantityTypeIdentifierRestingHeartRate": return "count/min"
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return "ms"
        case "HKQuantityTypeIdentifierActiveEnergyBurned": return "kJ"
        case "HKQuantityTypeIdentifierAppleExerciseTime": return "min"
        case "HKQuantityTypeIdentifierDistanceWalkingRunning": return "km"
        case "HKQuantityTypeIdentifierDistanceCycling": return "km"
        case "HKQuantityTypeIdentifierVO2Max": return "mL/kg·min"
        case "HKQuantityTypeIdentifierBodyMass": return "kg"
        case "HKQuantityTypeIdentifierHeight": return "cm"
        case "HKCategoryTypeIdentifierSleepAnalysis": return "category"
        default: return "count"
        }
    }

    private func displayName(for type: String) -> String {
        switch type {
        case "HKQuantityTypeIdentifierStepCount": return "StepCount"
        case "HKQuantityTypeIdentifierHeartRate": return "HeartRate"
        case "HKQuantityTypeIdentifierRestingHeartRate": return "RestingHeartRate"
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return "HRV"
        case "HKQuantityTypeIdentifierActiveEnergyBurned": return "ActiveEnergy"
        case "HKQuantityTypeIdentifierAppleExerciseTime": return "ExerciseTime"
        case "HKQuantityTypeIdentifierDistanceWalkingRunning": return "Distance"
        case "HKQuantityTypeIdentifierDistanceCycling": return "CyclingDistance"
        case "HKQuantityTypeIdentifierVO2Max": return "VO2Max"
        case "HKQuantityTypeIdentifierBodyMass": return "BodyMass"
        case "HKQuantityTypeIdentifierHeight": return "Height"
        default: return type
        }
    }

    private func displayNameShort(_ type: String) -> String {
        if type.isEmpty { return "—" }
        if type.contains("StepCount") { return "Steps" }
        if type.contains("RestingHeartRate") { return "RestingHR" }
        if type.contains("HeartRateVariability") { return "HRV" }
        if type.contains("HeartRate") { return "HeartRate" }
        if type.contains("ActiveEnergy") { return "Energy" }
        if type.contains("ExerciseTime") { return "Exercise" }
        if type.contains("Distance") { return "Distance" }
        if type.contains("VO2Max") { return "VO2Max" }
        if type.contains("BodyMass") { return "Weight" }
        if type.contains("Height") { return "Height" }
        if type.contains("Sleep") { return "Sleep" }
        return type
    }

    private func parseSleepCategory(_ raw: String) -> Double {
        let lowercased = raw.lowercased()
        if lowercased.contains("asleepdeep") || lowercased.contains("deep") { return 3.0 }
        if lowercased.contains("asleeprem") || lowercased.contains("rem") { return 4.0 }
        if lowercased.contains("asleepcore") || lowercased.contains("core") || lowercased.contains("light") { return 2.0 }
        if lowercased.contains("asleep") { return 1.0 }
        if lowercased.contains("awake") { return 5.0 }
        if lowercased.contains("inbed") { return 0.0 }
        return 1.0
    }

    // MARK: - Date Parsing

    private func parseHealthDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss xx",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        return nil
    }

    // MARK: - Workout Type Mapping

    private let workoutMapping: [String: String] = [
        "HKWorkoutActivityTypeRunning": "Running",
        "HKWorkoutActivityTypeWalking": "Walking",
        "HKWorkoutActivityTypeCycling": "Cycling",
        "HKWorkoutActivityTypeTraditionalStrengthTraining": "Strength Training",
        "HKWorkoutActivityTypeFunctionalStrengthTraining": "Functional Strength",
        "HKWorkoutActivityTypeSwimming": "Swimming",
        "HKWorkoutActivityTypeHiking": "Hiking",
        "HKWorkoutActivityTypeYoga": "Yoga",
        "HKWorkoutActivityTypeHighIntensityIntervalTraining": "HIIT",
        "HKWorkoutActivityTypeCrossTraining": "Cross Training",
        "HKWorkoutActivityTypeElliptical": "Elliptical",
        "HKWorkoutActivityTypeRower": "Rowing",
        "HKWorkoutActivityTypeStairClimbing": "Stair Climbing",
        "HKWorkoutActivityTypeDance": "Dance",
        "HKWorkoutActivityTypePilates": "Pilates",
        "HKWorkoutActivityTypeTaiChi": "Tai Chi",
        "HKWorkoutActivityTypeMixedCardio": "Mixed Cardio",
        "HKWorkoutActivityTypePlay": "Play",
        "HKWorkoutActivityTypeOther": "Other",
    ]

    private func normalizeWorkoutType(_ raw: String) -> String {
        if raw.isEmpty { return "Other" }
        if let mapped = workoutMapping[raw] { return mapped }
        for (key, value) in workoutMapping {
            if raw.caseInsensitiveCompare(key) == .orderedSame { return value }
        }
        let stripped = raw.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        if !stripped.isEmpty && stripped != raw {
            return stripped.capitalizedCamelCase()
        }
        return "Other"
    }
}

// MARK: - Progress Tracking InputStream

/// InputStream wrapper that tracks bytes read for import progress reporting.
final class ProgressTrackingInputStream: InputStream {
    private let fileHandle: FileHandle
    private let totalSize: Int64
    private(set) var bytesRead: Int64 = 0
    private var _streamStatus: Stream.Status = .notOpen
    private var _streamError: Error?
    private var pendingData = Data()
    private var pendingOffset = 0

    override var streamStatus: Stream.Status { _streamStatus }
    override var streamError: Error? { _streamError }
    override var hasBytesAvailable: Bool {
        if pendingOffset < pendingData.count { return true }
        do {
            let remaining = try fileHandle.offset()
            return remaining < totalSize
        } catch { return false }
    }

    init(fileHandle: FileHandle, totalSize: Int64) {
        self.fileHandle = fileHandle
        self.totalSize = totalSize
        super.init(data: Data()) // dummy
        _streamStatus = .notOpen
    }

    override func open() {
        _streamStatus = .open
        bytesRead = 0
        pendingData = Data()
        pendingOffset = 0
    }

    override func close() {
        _streamStatus = .closed
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard _streamStatus == .open else { return -1 }

        // Serve pending data first
        if pendingOffset < pendingData.count {
            let available = pendingData.count - pendingOffset
            let toCopy = min(available, len)
            pendingData.copyBytes(to: buffer, from: pendingOffset..<pendingOffset + toCopy)
            pendingOffset += toCopy
            if pendingOffset >= pendingData.count {
                pendingData = Data()
                pendingOffset = 0
            }
            return toCopy
        }

        // Read next chunk from file
        do {
            let chunkSize = min(len, 65536) // 64KB chunks
            if let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                bytesRead += Int64(chunk.count)

                // Copy directly to buffer
                chunk.copyBytes(to: buffer, count: chunk.count)

                // Also buffer for re-reads
                pendingData = chunk
                pendingOffset = chunk.count

                return chunk.count
            } else {
                _streamStatus = .atEnd
                return 0
            }
        } catch {
            _streamError = error
            _streamStatus = .error
            return -1
        }
    }

    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}

    override func property(forKey key: Stream.PropertyKey) -> Any? { nil }
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }
}

// MARK: - Parse Result Types

struct ImportParseResult {
    let metrics: [ParsedHealthMetric]
    let workouts: [ParsedWorkout]
    let sleepSessions: [ParsedSleep]
    let parsedByType: [String: Int]
    let skippedReasons: [String: Int]
    let parseError: ImportError?
}

struct ParsedHealthMetric {
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let sourceName: String?
    let device: String?
}

struct ParsedWorkout {
    let type: String
    let originalType: String
    let startDate: Date
    let endDate: Date

    // Raw Apple Health fields
    let rawDuration: Double?
    let rawDurationUnit: String?
    let dateBasedDurationSeconds: Double

    let rawDistance: Double?
    let rawDistanceUnit: String?

    let rawEnergy: Double?
    let rawEnergyUnit: String?

    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let sourceName: String?
}

struct ParsedSleep {
    let startDate: Date
    let endDate: Date
    let value: Double
    let category: String
    let sourceName: String?
}

// MARK: - String Helper

private extension String {
    func capitalizedCamelCase() -> String {
        var result = ""
        for char in self {
            if char.isUppercase && !result.isEmpty { result.append(" ") }
            result.append(char)
        }
        return result
    }
}
