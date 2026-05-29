import XCTest
@testable import Sovereign

final class HealthSafetyGuardTests: XCTestCase {
    let guard_ = HealthSafetyGuard()

    func testSafeInput() {
        let result = guard_.check("我今天适合训练吗")
        XCTAssertTrue(result.isSafe, "Normal health query should be safe")
        XCTAssertNil(result.category)
    }

    func testChestPainDetection() {
        let result = guard_.check("我最近胸口疼，应该怎么办")
        XCTAssertFalse(result.isSafe)
        XCTAssertEqual(result.category, .chestPain)
        XCTAssertNotNil(result.warningMessage)
    }

    func testSuicideDetection() {
        let result = guard_.check("我想自杀")
        XCTAssertFalse(result.isSafe)
        XCTAssertEqual(result.category, .suicide)
    }

    func testMedicalDiagnosis() {
        let result = guard_.check("我是不是得了心脏病")
        XCTAssertFalse(result.isSafe)
        XCTAssertEqual(result.category, .medicalDiagnosis)
    }

    func testMedicationDosage() {
        let result = guard_.check("我应该吃多少降压药")
        XCTAssertFalse(result.isSafe)
        XCTAssertEqual(result.category, .medicationDosage)
    }

    func testExtremeOvertraining() {
        let result = guard_.check("我每天训练6小时需要减少吗")
        XCTAssertFalse(result.isSafe)
        XCTAssertEqual(result.category, .overtraining)
    }

    func testNormalDiscussionOfTraining() {
        let result = guard_.check("我今天做了30分钟跑步，明天可以继续吗")
        XCTAssertTrue(result.isSafe, "Normal training discussion should be safe")
    }

    func testBreathingDifficulty() {
        let result = guard_.check("我喘不上气")
        XCTAssertFalse(result.isSafe)
        XCTAssertEqual(result.category, .breathingDifficulty)
    }
}
