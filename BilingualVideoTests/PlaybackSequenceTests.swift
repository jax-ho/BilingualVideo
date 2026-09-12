import XCTest
@testable import BilingualVideo

@MainActor
final class PlaybackSequenceTests: XCTestCase {
    func testChineseAdvancesToEnglishBeforeNextGroup() throws {
        let environment = try TemporaryAppEnvironment()
        for language in VideoLanguage.allCases {
            try environment.createFile("20.mp4", language: language)
        }
        let model = makeModel(environment)
        try model.savePlan(ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [20], updatedAt: .distantPast
        ))
        let chinese = try XCTUnwrap(model.playableVideo(pairID: 20, for: .chinese))
        let english = try XCTUnwrap(model.playableVideo(pairID: 20, for: .english))
        XCTAssertEqual(try model.nextVideo(after: chinese), english)
    }

    func testAutoAdvanceFollowsBilingualCardsAndPlanOrderWithinToday() throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        try model.savePlan(makePlan())
        model.setNormalPlaybackLooping(false)
        XCTAssertFalse(model.isNormalPlaybackLooping)
        XCTAssertEqual(model.todayStates.map(\.id), [20, 5, 100])

        let expected = try [20, 5, 100].flatMap { pairID in
            try VideoLanguage.allCases.map { language in
                try XCTUnwrap(model.playableVideo(pairID: pairID, for: language))
            }
        }
        var current: PlayableVideo? = expected[0]
        for video in expected {
            XCTAssertEqual(current, video)
            current = try model.nextVideo(after: XCTUnwrap(current))
        }
        XCTAssertNil(current, "Cannot advance to tomorrow's extra group")
        XCTAssertEqual(try model.nextVideo(after: expected[1]), expected[2], "Starting on English continues to the next group's Chinese")
        model.setNormalPlaybackLooping(true)
        XCTAssertEqual(try model.nextVideo(after: expected[5]), expected[0])
    }

    func testLoopSettingPersistsWithoutChangingPlanOrGroupCount() throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        try model.savePlan(makePlan())
        model.setDailyGroupCount(2)
        let bytes = try Data(contentsOf: environment.directories.scheduleURL)
        model.setNormalPlaybackLooping(true)
        let restarted = makeModel(environment)
        XCTAssertTrue(restarted.isNormalPlaybackLooping)
        XCTAssertEqual(restarted.dailyGroupCount, 2)
        XCTAssertEqual(restarted.playbackMode, .normal)
        XCTAssertEqual(restarted.savedPlan, model.savedPlan)
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), bytes)
        restarted.setNormalPlaybackLooping(false)
        XCTAssertFalse(makeModel(environment).isNormalPlaybackLooping)
    }

    func testSingleGroupOnlyRepeatsWhenLoopingIsEnabled() throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        try model.savePlan(makePlan())
        model.setDailyGroupCount(1)
        model.setNormalPlaybackLooping(false)
        let chinese = try XCTUnwrap(model.playableVideo(pairID: 20, for: .chinese))
        let english = try XCTUnwrap(model.playableVideo(pairID: 20, for: .english))
        XCTAssertEqual(try model.nextVideo(after: chinese), english)
        XCTAssertNil(try model.nextVideo(after: english))
        model.setNormalPlaybackLooping(true)
        XCTAssertEqual(try model.nextVideo(after: english), chinese)
    }

    func testMissingNextOrFirstGroupStopsInsteadOfSkipping() throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        try model.savePlan(makePlan())
        let first = try XCTUnwrap(model.playableVideo(pairID: 20, for: .english))
        let last = try XCTUnwrap(model.playableVideo(pairID: 100, for: .english))
        try environment.removeFile("5.mp4", language: .english)
        XCTAssertThrowsError(try model.nextVideo(after: first))
        model.setNormalPlaybackLooping(true)
        try environment.removeFile("20.mp4", language: .chinese)
        XCTAssertThrowsError(try model.nextVideo(after: last))
    }

    func testMissingEnglishInCurrentGroupStopsInsteadOfAdvancingToNextGroup() throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        try model.savePlan(makePlan())
        let chinese = try XCTUnwrap(model.playableVideo(pairID: 20, for: .chinese))
        try environment.removeFile("20.mp4", language: .english)
        XCTAssertThrowsError(try model.nextVideo(after: chinese))
    }

    func testMidnightOrSmallerWindowCannotContinueAnExpiredVideo() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences,
            now: { now }
        )
        model.setPlaybackMode(.normal)
        try model.savePlan(makePlan())
        let first = try XCTUnwrap(model.playableVideo(pairID: 20, for: .english))
        let last = try XCTUnwrap(model.playableVideo(pairID: 100, for: .english))
        model.setNormalPlaybackLooping(true)
        model.setDailyGroupCount(1)
        XCTAssertNil(try model.nextVideo(after: last))
        model.recordPlayback(at: now)
        now = testDate(2026, 9, 5)
        XCTAssertNil(try model.nextVideo(after: first))
        XCTAssertEqual(model.todayStates.map(\.id), [5])
    }

    private func makeEnvironment() throws -> TemporaryAppEnvironment {
        let environment = try TemporaryAppEnvironment()
        for id in [5, 20, 100, 200] {
            for language in VideoLanguage.allCases {
                try environment.createFile("\(id).mp4", language: language)
            }
        }
        return environment
    }

    private func makeModel(_ environment: TemporaryAppEnvironment) -> AppModel {
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences,
            now: { testDate(2026, 9, 4) }
        )
        model.setPlaybackMode(.normal)
        return model
    }

    func testNormalModeLoopsToFirstChineseByDefault() throws {
        let environment = try makeEnvironment()
        let model = makeModel(environment)
        try model.savePlan(makePlan())
        XCTAssertTrue(model.isNormalPlaybackLooping)
        let last = try XCTUnwrap(model.playableVideo(pairID: 100, for: .english))
        XCTAssertEqual(try model.nextVideo(after: last)?.id, "20-chinese")
    }

    private func makePlan() -> ViewingPlan {
        ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [20, 5, 100, 200],
            updatedAt: .distantPast
        )
    }
}
