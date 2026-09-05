import Security
import XCTest
@testable import BilingualVideo

@MainActor
final class AppModelIntegrationTests: XCTestCase {
    func testRefreshAddsResourcesWithoutChangingSavedPlan() throws {
        let environment = try TemporaryAppEnvironment()
        try createPair(id: "5", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 4, calendar: calendar)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            now: { now }
        )
        let plan = try XCTUnwrap(model.makeCandidate(startDate: now))
        try model.savePlan(plan)
        let savedSnapshot = model.savedPlan

        try createPair(id: "20", in: environment)
        model.refreshLibrary()

        XCTAssertEqual(model.savedPlan, savedSnapshot)
        XCTAssertEqual(model.scanResult.pairs.map(\.id), [5, 20])
        XCTAssertEqual(model.savedPlan?.orderedPairIDs, [5])
    }

    func testMissingTodayResourceDoesNotFallbackOrMutatePlan() throws {
        let environment = try TemporaryAppEnvironment()
        try createPair(id: "5", in: environment)
        try createPair(id: "20", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 4, calendar: calendar)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            now: { now }
        )
        let plan = try XCTUnwrap(model.makeCandidate(startDate: now))
        try model.savePlan(plan)
        let savedSnapshot = model.savedPlan

        try environment.removeFile("5.mp4", language: .english)
        model.refreshToday(at: now)

        XCTAssertEqual(model.todayState, .scheduledResourceUnavailable(pairID: 5))
        XCTAssertEqual(model.savedPlan, savedSnapshot)
        XCTAssertNil(model.playableVideo(for: .chinese))
    }

    func testUnrelatedScanErrorDoesNotBlockValidTodayPair() throws {
        let environment = try TemporaryAppEnvironment()
        try createPair(id: "5", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 4, calendar: calendar)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            now: { now }
        )
        let plan = try XCTUnwrap(model.makeCandidate(startDate: now))
        try model.savePlan(plan)

        try environment.createFile("99.mp4", language: .chinese)
        model.refreshToday(at: now)

        XCTAssertFalse(model.scanResult.isValidForGeneration)
        XCTAssertEqual(model.todayState, .playable(VideoPair(
            id: 5,
            chineseFileName: "5.mp4",
            englishFileName: "5.mp4"
        )))
    }

    func testNewAppModelRestoresSavedPlanAndTodayPair() throws {
        let environment = try TemporaryAppEnvironment()
        try createPair(id: "5", in: environment)
        try createPair(id: "20", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 5, calendar: calendar)
        let firstModel = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            now: { now }
        )
        let plan = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [5, 20],
            updatedAt: .distantPast
        )
        try firstModel.savePlan(plan)

        let restartedModel = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            now: { now }
        )

        XCTAssertEqual(restartedModel.savedPlan?.startDay, plan.startDay)
        XCTAssertEqual(restartedModel.savedPlan?.orderedPairIDs, plan.orderedPairIDs)
        XCTAssertEqual(restartedModel.todayState, .playable(VideoPair(
            id: 20,
            chineseFileName: "20.mp4",
            englishFileName: "20.mp4"
        )))
    }

    func testPINFormatKeepsLeadingZeroAndRejectsNonASCIIDigits() {
        XCTAssertTrue(ParentAccessService.isValidPIN("0123"))
        XCTAssertTrue(ParentAccessService.isValidPIN("123456"))
        XCTAssertFalse(ParentAccessService.isValidPIN("123"))
        XCTAssertFalse(ParentAccessService.isValidPIN("1234567"))
        XCTAssertFalse(ParentAccessService.isValidPIN("１２３４"))
        XCTAssertFalse(ParentAccessService.isValidPIN("12a4"))
    }

    func testPINKeychainRoundTripAndReplacement() throws {
        let serviceName = "com.jax.BilingualVideoTests.\(UUID().uuidString)"
        let parentAccess = ParentAccessService(service: serviceName)
        let cleanupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "parent-pin"
        ]
        defer { _ = SecItemDelete(cleanupQuery as CFDictionary) }

        XCTAssertFalse(try parentAccess.hasPIN())
        try parentAccess.setPIN("0123")
        XCTAssertTrue(try parentAccess.hasPIN())
        XCTAssertTrue(try parentAccess.verifyPIN("0123"))
        XCTAssertFalse(try parentAccess.verifyPIN("1234"))

        try parentAccess.setPIN("654321")
        XCTAssertFalse(try parentAccess.verifyPIN("0123"))
        XCTAssertTrue(try parentAccess.verifyPIN("654321"))
    }

    private func createPair(id: String, in environment: TemporaryAppEnvironment) throws {
        try environment.createFile("\(id).mp4", language: .chinese)
        try environment.createFile("\(id).mp4", language: .english)
    }
}
