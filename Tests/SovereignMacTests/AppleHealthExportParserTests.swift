import XCTest
@testable import Sovereign

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

    func testParseWorkout() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Workout workoutActivityType="HKWorkoutActivityTypeRunning"
                   duration="30.5" totalDistance="5.0" totalEnergyBurned="350"
                   startDate="2024-01-15 07:00:00 +0800" endDate="2024-01-15 07:30:30 +0800"
                   sourceName="Apple Watch"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else {
            XCTFail("Failed to create XML data")
            return
        }

        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertNil(result.parseError)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts.first?.type, "Running")
        XCTAssertEqual(result.workouts.first?.durationSeconds, 30.5)
    }

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

    func testIgnoresUnsupportedMetrics() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="zh_CN">
          <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Withings" unit="kg"
                  startDate="2024-01-15 08:00:00 +0800" endDate="2024-01-15 08:00:00 +0800" value="70"/>
          <Record type="HKQuantityTypeIdentifierStepCount" sourceName="iPhone" unit="count"
                  startDate="2024-01-15 08:00:00 +0800" endDate="2024-01-15 08:01:00 +0800" value="100"/>
        </HealthData>
        """

        guard let data = xml.data(using: .utf8) else {
            XCTFail("Failed to create XML data")
            return
        }

        let parser = AppleHealthExportParser(data: data)
        let result = parser.parse()

        XCTAssertEqual(result.metrics.count, 1, "Should only parse supported metric types")
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
