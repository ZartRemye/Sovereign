import Foundation

/// Stream-based Apple Health Export XML parser using Foundation's XMLParser (SAX-style).
/// Do not load the entire XML into memory — parse incrementally.
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
    private var currentWorkoutDistance = ""
    private var currentWorkoutEnergy = ""
    private var currentWorkoutAvgHR = ""
    private var currentWorkoutMaxHR = ""

    // Progress tracking
    private var totalBytes: Int64 = 0
    private var parsedBytes: Int64 = 0
    var onProgress: ((Double) -> Void)?
    var isCancelled = false

    init?(fileURL: URL) {
        guard let parser = XMLParser(contentsOf: fileURL) else { return nil }
        self.parser = parser
        self.totalBytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        super.init()
        self.parser.delegate = self
    }

    init(data: Data) {
        self.parser = XMLParser(data: data)
        self.totalBytes = Int64(data.count)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> ImportParseResult {
        let success = parser.parse()
        if isCancelled {
            return ImportParseResult(
                metrics: parsedMetrics,
                workouts: parsedWorkouts,
                sleepSessions: parsedSleep,
                parsedByType: parsedByType,
                skippedReasons: skippedReasons,
                parseError: ImportError(message: "导入已取消", underlyingError: nil)
            )
        }
        if !success, let error = parser.parserError {
            return ImportParseResult(
                metrics: parsedMetrics,
                workouts: parsedWorkouts,
                sleepSessions: parsedSleep,
                parsedByType: parsedByType,
                skippedReasons: skippedReasons,
                parseError: ImportError(message: "XML 解析错误: \(error.localizedDescription)", underlyingError: error)
            )
        }
        return ImportParseResult(
            metrics: parsedMetrics,
            workouts: parsedWorkouts,
            sleepSessions: parsedSleep,
            parsedByType: parsedByType,
            skippedReasons: skippedReasons,
            parseError: nil
        )
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
            currentWorkoutDistance = attributeDict["totalDistance"] ?? ""
            currentWorkoutEnergy = attributeDict["totalEnergyBurned"] ?? ""
            currentRecordStartDate = attributeDict["startDate"] ?? ""
            currentRecordEndDate = attributeDict["endDate"] ?? ""
            currentRecordSourceName = attributeDict["sourceName"] ?? ""
            // Also parse WorkoutStatistics if present
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Record" {
            processRecord()
        } else if elementName == "Workout" {
            processWorkout()
        }

        // Report progress periodically
        if parsedMetrics.count % 5000 == 0 {
            onProgress?(min(Double(parsedMetrics.count) / 50000.0, 0.99))
        }
    }

    // MARK: - Processing

    private func processRecord() {
        let rawType = currentRecordType

        // Try to match the type (case-insensitive, with prefix variants)
        guard let matchedType = matchSupportedType(rawType) else {
            skippedReasons["不支持的类型", default: 0] += 1
            return
        }

        // Special handling for sleep records (categorical)
        if matchedType == "HKCategoryTypeIdentifierSleepAnalysis" {
            guard let startDate = parseHealthDate(currentRecordStartDate),
                  let endDate = parseHealthDate(currentRecordEndDate) else {
                skippedReasons["日期解析失败", default: 0] += 1
                return
            }

            // value is a category string like HKCategoryValueSleepAnalysisAsleep
            let valueStr = currentRecordValue
            let sleepValue = parseSleepCategory(valueStr)

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

            let sleep = ParsedSleep(
                startDate: startDate,
                endDate: endDate,
                value: sleepValue,
                category: valueStr,
                sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName
            )
            parsedSleep.append(sleep)
            return
        }

        // Regular quantitative metrics
        guard let value = Double(currentRecordValue) else {
            skippedReasons["数值解析失败", default: 0] += 1
            return
        }

        guard let startDate = parseHealthDate(currentRecordStartDate) else {
            skippedReasons["日期解析失败", default: 0] += 1
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

        let displayType = displayName(for: matchedType)
        parsedByType[displayType, default: 0] += 1
    }

    private func processWorkout() {
        guard let startDate = parseHealthDate(currentRecordStartDate),
              let endDate = parseHealthDate(currentRecordEndDate) else {
            skippedReasons["运动日期解析失败", default: 0] += 1
            return
        }

        let typeName = normalizeWorkoutType(currentWorkoutType)
        let duration = Double(currentWorkoutDuration) ?? (endDate.timeIntervalSince(startDate))
        let distance = Double(currentWorkoutDistance)
        let energy = Double(currentWorkoutEnergy)

        let workout = ParsedWorkout(
            type: typeName,
            originalType: currentWorkoutType,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: duration,
            distanceMeters: distance,
            energyKJ: energy,
            avgHeartRate: nil,
            maxHeartRate: nil,
            sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName
        )
        parsedWorkouts.append(workout)
        parsedByType["Workout_\(typeName)", default: 0] += 1
    }

    // MARK: - Type Matching (case-insensitive, prefix variants)

    private let supportedTypePatterns: [String] = [
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

    private func matchSupportedType(_ raw: String) -> String? {
        let lowercased = raw.lowercased()

        // Exact match first (fast path)
        for pattern in supportedTypePatterns {
            if raw == pattern { return pattern }
        }

        // Case-insensitive match
        for pattern in supportedTypePatterns {
            if lowercased == pattern.lowercased() { return pattern }
        }

        // Partial match — strip prefixes and try
        let simplified = raw
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")

        for pattern in supportedTypePatterns {
            let patternSimple = pattern
                .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
                .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
            if simplified.caseInsensitiveCompare(patternSimple) == .orderedSame {
                return pattern
            }
        }

        return nil
    }

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

    /// Parse sleep category value to numeric coding:
    /// 0 = InBed, 1 = AsleepUnspecified, 2 = AsleepCore, 3 = AsleepDeep, 4 = AsleepREM, 5 = Awake
    private func parseSleepCategory(_ raw: String) -> Double {
        let lowercased = raw.lowercased()
        if lowercased.contains("asleepdeep") || lowercased.contains("deep") { return 3.0 }
        if lowercased.contains("asleeprem") || lowercased.contains("rem") { return 4.0 }
        if lowercased.contains("asleepcore") || lowercased.contains("core") || lowercased.contains("light") { return 2.0 }
        if lowercased.contains("asleep") { return 1.0 }
        if lowercased.contains("awake") { return 5.0 }
        if lowercased.contains("inbed") { return 0.0 }
        return 1.0 // Default to asleep unspecified
    }

    // MARK: - Date Parsing (robust)

    private func parseHealthDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }

        // Try formats in order of likelihood
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "yyyy-MM-dd HH:mm:ss Z",       // 2026-05-29 08:12:00 +0800
            "yyyy-MM-dd HH:mm:ss xx",       // 2026-05-29 08:12:00 +08:00
            "yyyy-MM-dd'T'HH:mm:ssZ",       // 2026-05-29T08:12:00+0800
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",   // 2026-05-29T08:12:00+08:00
            "yyyy-MM-dd'T'HH:mm:ss",        // 2026-05-29T08:12:00 (no tz)
            "yyyy-MM-dd HH:mm:ss",          // 2026-05-29 08:12:00 (no tz)
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // ISO8601 as last resort
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        return nil
    }

    // MARK: - Workout Type Mapping (comprehensive)

    private func normalizeWorkoutType(_ raw: String) -> String {
        if raw.isEmpty { return "Other" }

        let mapping: [String: String] = [
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

        if let mapped = mapping[raw] {
            return mapped
        }

        // Case-insensitive fallback
        for (key, value) in mapping {
            if raw.caseInsensitiveCompare(key) == .orderedSame {
                return value
            }
        }

        // Try stripping prefix
        let stripped = raw.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        if !stripped.isEmpty && stripped != raw {
            return stripped.capitalizedCamelCase()
        }

        return "Other"
    }
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
    let durationSeconds: Double
    let distanceMeters: Double?
    let energyKJ: Double?
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
        // Convert "TraditionalStrengthTraining" -> "Traditional Strength Training"
        var result = ""
        for char in self {
            if char.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(char)
        }
        return result
    }
}
