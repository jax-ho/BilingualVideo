import Security
import XCTest
@testable import BilingualVideo

@MainActor
final class AppModelIntegrationTests: XCTestCase {
    func testStrictDefaultAndEnabledLoopPreserveExplicitNormalAndDisabledLoopSettings() throws {
        let environment = try TemporaryAppEnvironment()
        for id in [1, 2, 3, 4, 5] { try createPair(id: String(id), in: environment) }
        let now = testDate(2026, 9, 5)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences, now: { now }
        )
        XCTAssertEqual(model.playbackMode, .strict)
        XCTAssertTrue(model.isNormalPlaybackLooping)
        XCTAssertNil(environment.preferences.object(forKey: "playbackMode"))
        XCTAssertNil(environment.preferences.object(forKey: "normalPlaybackLooping"))
        XCTAssertEqual(PlaybackMode.allCases, [.normal, .strict])
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: testDate(2026, 9, 4))))
        let savedBytes = try Data(contentsOf: environment.directories.scheduleURL)
        XCTAssertEqual(model.todayStates.map(\.id), [2, 3, 4])

        model.setDailyGroupCount(2)
        model.setPlaybackMode(.normal)
        model.setNormalPlaybackLooping(false)
        XCTAssertEqual(environment.preferences.string(forKey: "playbackMode"), "normal")
        XCTAssertEqual(model.todayStates.map(\.id), [2, 3])
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), savedBytes)
        for language in VideoLanguage.allCases {
            XCTAssertNotNil(model.playableVideo(pairID: 2, for: language))
            XCTAssertNotNil(model.playableVideo(pairID: 3, for: language))
            XCTAssertNil(model.playableVideo(pairID: 4, for: language))
        }

        let restarted = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences, now: { now }
        )
        XCTAssertEqual(restarted.playbackMode, .normal)
        XCTAssertFalse(restarted.isNormalPlaybackLooping)
        XCTAssertEqual(restarted.dailyGroupCount, 2)
        XCTAssertEqual(restarted.todayStates, model.todayStates)
        XCTAssertEqual(restarted.savedPlan, model.savedPlan)
    }

    func testUnrecognizedPlaybackModeFallsBackToStrict() throws {
        let environment = try TemporaryAppEnvironment()
        environment.preferences.set("unrecognized-mode", forKey: "playbackMode")
        try createPair(id: "5", in: environment)
        let now = testDate(2026, 9, 4)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences, now: { now }
        )
        XCTAssertEqual(model.playbackMode, .strict)
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: now)))
        XCTAssertEqual(model.todayStates.map(\.id), [5])
        XCTAssertNil(model.playableVideo(pairID: 5, for: .chinese))
        XCTAssertNotNil(try model.beginStrictPlayback())
    }

    func testDailyGroupSettingDefaultsPersistsAndDoesNotRewritePlan() throws {
        let environment = try TemporaryAppEnvironment()
        for id in [1, 2, 3, 4, 5] { try createPair(id: String(id), in: environment) }
        var now = testDate(2026, 9, 4)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences, now: { now }
        )
        XCTAssertEqual(model.dailyGroupCount, 3)
        model.setPlaybackMode(.normal)
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: now)))
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
        model.recordPlayback(at: now)

        now = testDate(2026, 9, 5)
        model.activate()
        defer { model.deactivate() }
        let savedBytes = try Data(contentsOf: environment.directories.scheduleURL)
        XCTAssertEqual(model.todayStates.map(\.id), [2, 3, 4])
        XCTAssertNil(model.playableVideo(pairID: 1, for: .chinese))
        XCTAssertNil(model.playableVideo(pairID: 5, for: .english))
        for id in [2, 3, 4] {
            for language in VideoLanguage.allCases {
                let video = try XCTUnwrap(model.playableVideo(pairID: id, for: language))
                XCTAssertEqual(video.pairID, id)
                XCTAssertEqual(video.language, language)
                XCTAssertEqual(video.url.lastPathComponent, "\(id).mp4")
            }
        }
        model.setDailyGroupCount(1)
        XCTAssertEqual(model.todayStates.map(\.id), [2])
        XCTAssertNil(model.playableVideo(pairID: 3, for: .chinese))
        model.setDailyGroupCount(0)
        XCTAssertEqual(model.dailyGroupCount, 1)
        model.setDailyGroupCount(4)
        XCTAssertEqual(model.todayStates.map(\.id), [2, 3, 4, 5])
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), savedBytes)

        let restarted = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences, now: { now }
        )
        XCTAssertEqual(restarted.dailyGroupCount, 4)
        XCTAssertEqual(restarted.todayStates.map(\.id), [2, 3, 4, 5])
        XCTAssertEqual(restarted.savedPlan, model.savedPlan)
    }

    func testMissingWindowResourceDoesNotPullInNextGroup() throws {
        let environment = try TemporaryAppEnvironment()
        environment.preferences.set(PlaybackMode.normal.rawValue, forKey: "playbackMode")
        for id in [1, 2, 3, 4] { try createPair(id: String(id), in: environment) }
        let now = testDate(2026, 9, 4)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences, now: { now }
        )
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: now)))
        try environment.removeFile("2.mp4", language: .english)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
        XCTAssertEqual(model.todayStates[1], .scheduledResourceUnavailable(pairID: 2))
        XCTAssertNil(model.playableVideo(pairID: 2, for: .chinese))
        XCTAssertNil(model.playableVideo(pairID: 4, for: .english))
        XCTAssertNotNil(model.playableVideo(pairID: 3, for: .english))
    }

    func testRefreshAddsResourcesWithoutChangingSavedPlan() throws {
        let environment = try TemporaryAppEnvironment()
        try createPair(id: "5", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 4, calendar: calendar)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            preferences: environment.preferences,
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
        environment.preferences.set(PlaybackMode.normal.rawValue, forKey: "playbackMode")
        try createPair(id: "5", in: environment)
        try createPair(id: "20", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 4, calendar: calendar)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            preferences: environment.preferences,
            now: { now }
        )
        let plan = try XCTUnwrap(model.makeCandidate(startDate: now))
        try model.savePlan(plan)
        let savedSnapshot = model.savedPlan

        try environment.removeFile("5.mp4", language: .english)
        model.refreshToday(at: now)

        XCTAssertEqual(model.todayStates, [
            .scheduledResourceUnavailable(pairID: 5),
            .playable(VideoPair(id: 20, chineseFileName: "20.mp4", englishFileName: "20.mp4"))
        ])
        XCTAssertEqual(model.savedPlan, savedSnapshot)
        XCTAssertNil(model.playableVideo(pairID: 5, for: .chinese))
        XCTAssertNotNil(model.playableVideo(pairID: 20, for: .chinese))
    }

    func testUnrelatedScanErrorDoesNotBlockValidTodayPair() throws {
        let environment = try TemporaryAppEnvironment()
        try createPair(id: "5", in: environment)
        let calendar = testCalendar()
        let now = testDate(2026, 9, 4, calendar: calendar)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: calendar),
            preferences: environment.preferences,
            now: { now }
        )
        let plan = try XCTUnwrap(model.makeCandidate(startDate: now))
        try model.savePlan(plan)

        try environment.createFile("99.mp4", language: .chinese)
        model.refreshToday(at: now)

        XCTAssertFalse(model.scanResult.isValidForGeneration)
        XCTAssertEqual(model.todayStates, [.playable(VideoPair(
            id: 5,
            chineseFileName: "5.mp4",
            englishFileName: "5.mp4"
        ))])
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
            preferences: environment.preferences,
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
            preferences: environment.preferences,
            now: { now }
        )

        XCTAssertEqual(restartedModel.savedPlan?.startDay, plan.startDay)
        XCTAssertEqual(restartedModel.savedPlan?.orderedPairIDs, plan.orderedPairIDs)
        XCTAssertEqual(restartedModel.todayStates, [.playable(VideoPair(
            id: 20,
            chineseFileName: "20.mp4",
            englishFileName: "20.mp4"
        ))])
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
