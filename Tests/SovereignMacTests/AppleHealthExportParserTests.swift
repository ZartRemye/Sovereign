import XCTest
@testable import SovereignMac

final class AppleHealthExportParserTests: XCTestCase {
    func testParseMinimalXML() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count"
                  startDate="2024-01-15 08:00:00 +0800" endDate="2024-01-15 08:01:00 +0800" value="100"/>
          <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="Apple Watch" unit="count/min"
                  startDate="2024-01-15 08:00:00 +0800" endDate="2024-01-15 08:00:05 +0800" value="72"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else {
            XCTFail("Failed to create XML data")
            return
        }

        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError, "Should parse without error")
        XCTAssertEqual(result.metrics.count, 2)
        XCTAssertTrue(result.metrics.contains { $0.type == "HKQuantityTypeIdentifierStepCount" })
        XCTAssertTrue(result.metrics.contains { $0.type == "HKQuantityTypeIdentifierHeartRate" })
    }

    // MARK: - Workout Duration Tests

    func testParseWorkout_durationUnitMin() {
        /// Apple Health: duration="43.5" durationUnit="min" → should be ~2610 seconds, ~43.5 min
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeTraditionalStrengthTraining"
                   duration="43.5" durationUnit="min"
                   startDate="2026-05-16 21:44:00 +0800" endDate="2026-05-16 22:28:00 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else { XCTFail(); return }
        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError)
        XCTAssertEqual(result.workouts.count, 1)

        let w = result.workouts.first!
        XCTAssertEqual(w.rawDuration, 43.5)
        XCTAssertEqual(w.rawDurationUnit, "min")

        // Normalize
        let normalizer = HealthDataNormalizer()
        let sessions = normalizer.normalizeWorkouts([w])
        XCTAssertEqual(sessions.count, 1)

        let session = sessions.first!
        let expectedSeconds = 43.5 * 60.0 // 2610
        XCTAssertEqual(session.durationSeconds, expectedSeconds, accuracy: 1.0,
                       "43.5 min should be ~2610 seconds, got \(session.durationSeconds)")
        XCTAssertEqual(session.durationFormatted, "44m",
                       "43.5 min should format as ~44m, got \(session.durationFormatted)")
    }

    func testParseWorkout_durationUnitHr() {
        /// duration="1.25" durationUnit="hr" → 4500 seconds → 1h 15m
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeRunning"
                   duration="1.25" durationUnit="hr"
                   startDate="2026-05-16 06:00:00 +0800" endDate="2026-05-16 07:15:00 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else { XCTFail(); return }
        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError)
        let w = result.workouts.first!
        XCTAssertEqual(w.rawDuration, 1.25)
        XCTAssertEqual(w.rawDurationUnit, "hr")

        let normalizer = HealthDataNormalizer()
        let sessions = normalizer.normalizeWorkouts([w])
        let session = sessions.first!

        XCTAssertEqual(session.durationSeconds, 4500, accuracy: 1.0,
                       "1.25 hr should be 4500s, got \(session.durationSeconds)")
        XCTAssertTrue(session.durationFormatted.contains("1h"),
                      "Should format as 1h 15m, got \(session.durationFormatted)")
    }

    func testParseWorkout_durationUnitSec() {
        /// duration="1800" durationUnit="s" → 1800 seconds → 30m
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeWalking"
                   duration="1800" durationUnit="s"
                   startDate="2026-05-16 10:00:00 +0800" endDate="2026-05-16 10:30:00 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else { XCTFail(); return }
        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError)
        let normalizer = HealthDataNormalizer()
        let sessions = normalizer.normalizeWorkouts(result.workouts)
        let session = sessions.first!

        XCTAssertEqual(session.durationSeconds, 1800, accuracy: 1.0)
        XCTAssertEqual(session.durationFormatted, "30m")
    }

    func testParseWorkout_noDuration_fallbackToDates() {
        /// No duration → use startDate/endDate diff → 5400s → 1h 30m
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeRunning"
                   startDate="2026-05-16 10:00:00 +0800" endDate="2026-05-16 11:30:00 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else { XCTFail(); return }
        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError)

        let normalizer = HealthDataNormalizer()
        let sessions = normalizer.normalizeWorkouts(result.workouts)
        let session = sessions.first!

        XCTAssertEqual(session.durationSeconds, 5400, accuracy: 1.0)
        XCTAssertEqual(session.durationSource, "Start/End Date")
        XCTAssertTrue(session.durationFormatted.contains("1h"),
                      "Should be 1h 30m, got \(session.durationFormatted)")
    }

    func testParseWorkout_mismatchWarning() {
        /// duration="43.5" durationUnit="min" → 2610s
        /// start/end diff: 44 min = 2640s
        /// Small diff, no warning
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeTraditionalStrengthTraining"
                   duration="43.5" durationUnit="min"
                   startDate="2026-05-16 21:44:00 +0800" endDate="2026-05-16 22:28:00 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else { XCTFail(); return }
        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        let normalizer = HealthDataNormalizer()
        let sessions = normalizer.normalizeWorkouts(result.workouts)
        let session = sessions.first!

        // 44 min = 2640s, AH: 43.5 min = 2610s, diff = 30s, 1.1% → no warning
        XCTAssertNil(session.durationWarning,
                     "Small mismatch should not warn, got: \(session.durationWarning ?? "nil")")
    }

    func testParseWorkout_originalTypePreserved() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeTraditionalStrengthTraining"
                   duration="43.5" durationUnit="min"
                   startDate="2026-05-16 21:44:00 +0800" endDate="2026-05-16 22:28:00 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else { XCTFail(); return }
        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        let w = result.workouts.first!
        XCTAssertEqual(w.originalType, "HKWorkoutActivityTypeTraditionalStrengthTraining")
        XCTAssertEqual(w.type, "Strength Training")

        let normalizer = HealthDataNormalizer()
        let sessions = normalizer.normalizeWorkouts([w])
        XCTAssertEqual(sessions.first?.rawWorkoutActivityType, "HKWorkoutActivityTypeTraditionalStrengthTraining")
    }

    // MARK: - Existing tests (updated)

    func testParseSleepAnalysis() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Apple Watch" unit="category"
                  startDate="2024-01-14 23:00:00 +0800" endDate="2024-01-15 07:00:00 +0800" value="0"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else {
            XCTFail("Failed to create XML data")
            return
        }

        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError)
        XCTAssertEqual(result.sleepSessions.count, 1)
        XCTAssertEqual(result.metrics.count, 1)
    }

    func testHandlesMalformedXML() {
        let xml = "<HealthData><Record type=\"HKQuantityTypeIdentifierStepCount\"</HealthData>"
        guard let data = xml.data(using: .utf8) else {
            XCTFail("Failed to create XML data")
            return
        }

        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNotNil(result.parseError, "Should report parse error for malformed XML")
    }
}
