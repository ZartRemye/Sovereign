import Foundation

/// Stream-based Apple Health Export XML parser using Foundation's XMLParser (SAX-style).
/// Do not load the entire XML into memory — parse incrementally.
final class AppleHealthExportParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var parsedMetrics: [ParsedHealthMetric] = []
    private var parsedWorkouts: [ParsedWorkout] = []
    private var parsedSleep: [ParsedSleep] = []

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
                parseError: ImportError(message: "导入已取消", underlyingError: nil)
            )
        }
        if !success, let error = parser.parserError {
            return ImportParseResult(
                metrics: parsedMetrics,
                workouts: parsedWorkouts,
                sleepSessions: parsedSleep,
                parseError: ImportError(message: "XML 解析错误: \(error.localizedDescription)", underlyingError: error)
            )
        }
        return ImportParseResult(
            metrics: parsedMetrics,
            workouts: parsedWorkouts,
            sleepSessions: parsedSleep,
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
        } else if elementName == "SleepAnalysis" {
            currentRecordType = "HKCategoryTypeIdentifierSleepAnalysis"
            currentRecordStartDate = attributeDict["startDate"] ?? ""
            currentRecordEndDate = attributeDict["endDate"] ?? ""
            currentRecordValue = attributeDict["value"] ?? ""
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

        // Report progress every ~1000 elements
        if parsedMetrics.count % 1000 == 0 {
            onProgress?(min(Double(parsedMetrics.count) / 10000.0, 0.99))
        }
    }

    // MARK: - Processing

    private func processRecord() {
        let type = currentRecordType

        // Check if this is a metric type we care about
        guard isSupportedMetric(type) else { return }

        guard let value = Double(currentRecordValue),
              let startDate = parseHealthDate(currentRecordStartDate) else {
            return
        }

        let endDate = parseHealthDate(currentRecordEndDate) ?? startDate
        let unit = supportedUnit(for: type)

        let metric = ParsedHealthMetric(
            type: type,
            value: value,
            unit: unit,
            startDate: startDate,
            endDate: endDate,
            sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName,
            device: currentRecordDevice
        )
        parsedMetrics.append(metric)

        // Check for sleep data
        if type == "HKCategoryTypeIdentifierSleepAnalysis" {
            let sleep = ParsedSleep(
                startDate: startDate,
                endDate: endDate,
                value: value,
                sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName
            )
            parsedSleep.append(sleep)
        }
    }

    private func processWorkout() {
        guard let startDate = parseHealthDate(currentRecordStartDate),
              let endDate = parseHealthDate(currentRecordEndDate) else {
            return
        }

        let duration = Double(currentWorkoutDuration) ?? 0
        let distance = Double(currentWorkoutDistance)
        let energy = Double(currentWorkoutEnergy)

        let workout = ParsedWorkout(
            type: normalizeWorkoutType(currentWorkoutType),
            startDate: startDate,
            endDate: endDate,
            durationSeconds: duration,
            distanceMeters: distance,
            energyKJ: energy,
            avgHeartRate: nil, // Parsed from associated records if needed
            maxHeartRate: nil,
            sourceName: currentRecordSourceName.isEmpty ? nil : currentRecordSourceName
        )
        parsedWorkouts.append(workout)
    }

    // MARK: - Helpers

    private func isSupportedMetric(_ type: String) -> Bool {
        supportedTypes.contains(type)
    }

    private let supportedTypes: Set<String> = [
        "HKQuantityTypeIdentifierStepCount",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierRestingHeartRate",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKQuantityTypeIdentifierAppleExerciseTime",
        "HKQuantityTypeIdentifierDistanceWalkingRunning",
        "HKQuantityTypeIdentifierVO2Max",
        "HKCategoryTypeIdentifierSleepAnalysis",
    ]

    private func supportedUnit(for type: String) -> String {
        switch type {
        case "HKQuantityTypeIdentifierStepCount": return "count"
        case "HKQuantityTypeIdentifierHeartRate": return "bpm"
        case "HKQuantityTypeIdentifierRestingHeartRate": return "bpm"
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return "ms"
        case "HKQuantityTypeIdentifierActiveEnergyBurned": return "kJ"
        case "HKQuantityTypeIdentifierAppleExerciseTime": return "min"
        case "HKQuantityTypeIdentifierDistanceWalkingRunning": return "km"
        case "HKQuantityTypeIdentifierVO2Max": return "mL/kg·min"
        case "HKCategoryTypeIdentifierSleepAnalysis": return "category"
        default: return "count"
        }
    }

    private func parseHealthDate(_ string: String) -> Date? {
        // Apple Health uses ISO 8601-like: "2024-01-15 08:30:00 +0800"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: string) { return date }

        // Try without timezone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: string) { return date }

        return nil
    }

    private func normalizeWorkoutType(_ raw: String) -> String {
        let mapping: [String: String] = [
            "HKWorkoutActivityTypeRunning": "Running",
            "HKWorkoutActivityTypeWalking": "Walking",
            "HKWorkoutActivityTypeCycling": "Cycling",
            "HKWorkoutActivityTypeTraditionalStrengthTraining": "Strength Training",
            "HKWorkoutActivityTypeFunctionalStrengthTraining": "Strength Training",
            "HKWorkoutActivityTypeSwimming": "Swimming",
            "HKWorkoutActivityTypeYoga": "Yoga",
            "HKWorkoutActivityTypeHighIntensityIntervalTraining": "HIIT",
        ]
        return mapping[raw] ?? raw.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
    }
}

// MARK: - Parse Result Types

struct ImportParseResult {
    let metrics: [ParsedHealthMetric]
    let workouts: [ParsedWorkout]
    let sleepSessions: [ParsedSleep]
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
    let sourceName: String?
}
