import XCTest
@testable import SovereignMac

final class SovereignMacTests: XCTestCase {
    func testMockDataGeneration() async {
        let mock = MockHealthDataProvider.shared
        let data = await mock.generateAllData()

        XCTAssertEqual(data.dailySummaries.count, 90)
        XCTAssertGreaterThan(data.metrics.count, 0)
        XCTAssertGreaterThan(data.workouts.count, 0)
        XCTAssertGreaterThan(data.sleepSessions.count, 0)
    }

    func testLiveHeartRate() async {
        let mock = MockHealthDataProvider.shared
        let hr = await mock.generateLiveHeartRate()
        XCTAssertGreaterThan(hr, 40)
        XCTAssertLessThan(hr, 120)
    }

    func testLiveSteps() async {
        let mock = MockHealthDataProvider.shared
        let steps = await mock.generateLiveSteps()
        XCTAssertGreaterThan(steps, 0)
        XCTAssertLessThanOrEqual(steps, 12000)
    }
}
