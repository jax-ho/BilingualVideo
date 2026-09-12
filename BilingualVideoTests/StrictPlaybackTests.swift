import XCTest
@testable import BilingualVideo

@MainActor
final class StrictPlaybackTests: XCTestCase {
    func testSingleEntryResumesPersistedEpisodeAndRejectsNormalSelection() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(first.video.id, "1-chinese")
        XCTAssertFalse(try XCTUnwrap(model.savedPlan?.playbackTracking).hasPlayed)
        XCTAssertNil(model.playableVideo(pairID: 2, for: .english))
        XCTAssertNil(try model.nextVideo(after: first.video))
        try model.saveStrictProgress(first, seconds: 15.75, hasPlayed: true)
        let restarted = AppModel(directories: environment.directories,
                                 scheduleService: ScheduleService(calendar: testCalendar()),
                                 preferences: environment.preferences, now: { testDate(2026, 9, 4) })
        XCTAssertEqual(restarted.playbackMode, .strict)
        let resumed = try XCTUnwrap(restarted.beginStrictPlayback())
        XCTAssertEqual(resumed.video, first.video)
        XCTAssertEqual(resumed.position, 15.75)
        XCTAssertTrue(try XCTUnwrap(restarted.savedPlan?.playbackTracking).hasPlayed)
    }

    func testOnlyNaturalCompletionAdvancesInPageOrderAndNeverLoops() throws {
        let environment = try environment()
        let model = try model(environment)
        model.setNormalPlaybackLooping(true)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(first, seconds: 999, hasPlayed: true)
        XCTAssertEqual(try model.beginStrictPlayback()?.index, 0, "Position alone cannot complete an episode")
        var request: StrictPlaybackRequest? = first
        var order: [String] = []
        while let current = request {
            order.append(current.video.id)
            request = try model.finishStrictEpisode(current)
        }
        XCTAssertEqual(order, ["1-chinese", "1-english", "2-chinese", "2-english", "3-chinese", "3-english"])
        XCTAssertTrue(try XCTUnwrap(model.strictProgressToday).isFinished)
        XCTAssertNil(try model.beginStrictPlayback())
        XCTAssertThrowsError(try model.finishStrictEpisode(first))
        model.reloadSavedPlan()
        XCTAssertNil(try model.beginStrictPlayback(), "Restart/reload must not unlock completed content")
    }

    func testCompletionSurvivesModeChangesAndSavingTheSamePlan() throws {
        let environment = try environment()
        let model = try model(environment)
        model.setDailyGroupCount(1)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        let last = try XCTUnwrap(model.finishStrictEpisode(first))
        XCTAssertNil(try model.finishStrictEpisode(last))
        model.setPlaybackMode(.normal)
        XCTAssertNotNil(model.playableVideo(pairID: 1, for: .chinese))
        model.setDailyGroupCount(1)
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: testDate(2026, 9, 4))))
        model.setPlaybackMode(.strict)
        XCTAssertNil(try model.beginStrictPlayback())
        XCTAssertEqual(model.todayStates.map(\.id), [1])
    }

    func testChangedGroupCountResetsTodayAndOldTicketCannotAffectNewDay() throws {
        let environment = try environment()
        var now = testDate(2026, 9, 4)
        let model = try model(environment, now: { now })
        let old = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(old, seconds: 2, hasPlayed: true)
        model.setDailyGroupCount(1)
        XCTAssertEqual(model.todayStates.map(\.id), [1])
        let reset = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(reset.position, 0)
        XCTAssertEqual(reset.index, 0)
        XCTAssertThrowsError(try model.saveStrictProgress(old, seconds: 3, hasPlayed: true))
        XCTAssertThrowsError(try model.finishStrictEpisode(old))
        now = testDate(2026, 9, 5)
        model.refreshToday()
        let nextDay = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(nextDay.video.id, "2-chinese")
        XCTAssertEqual(nextDay.position, 0)
        XCTAssertEqual(nextDay.episodeCount, 2)
        XCTAssertThrowsError(try model.saveStrictProgress(old, seconds: 3, hasPlayed: true))
        XCTAssertThrowsError(try model.finishStrictEpisode(old))
        XCTAssertFalse(try XCTUnwrap(model.savedPlan?.playbackTracking).hasPlayed)
    }

    func testChangedTodayOrderResetsPositionAndSurvivesRestart() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        let english = try XCTUnwrap(model.finishStrictEpisode(first))
        try model.saveStrictProgress(english, seconds: 12.5, hasPlayed: true)
        var edited = try XCTUnwrap(model.savedPlan)
        edited.orderedPairIDs = [2, 1, 3, 4]
        try model.savePlan(edited)
        model.reloadSavedPlan()
        let reset = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(reset.video.id, "2-chinese")
        XCTAssertEqual(reset.position, 0)
        XCTAssertEqual(reset.index, 0)
        XCTAssertFalse(try XCTUnwrap(model.strictProgressToday).hasStarted)
        XCTAssertEqual(model.savedPlan?.playbackTracking?.hasPlayed, true,
                       "Resetting progress must not erase the day's actual playback history")
    }

    func testManualResetPersistsAndRejectsOldCallbacksWithoutChangingScheduleOrSettings() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        let english = try XCTUnwrap(model.finishStrictEpisode(first))
        try model.saveStrictProgress(english, seconds: 12.5, hasPlayed: true)
        let original = try XCTUnwrap(model.savedPlan)
        // Parents can also clear dormant strict progress while using normal mode.
        model.setPlaybackMode(.normal)
        XCTAssertTrue(model.canResetTodayPlaybackProgress)
        try model.resetTodayPlaybackProgress()
        XCTAssertFalse(model.canResetTodayPlaybackProgress)
        XCTAssertNil(model.strictProgressToday)
        var expected = original
        expected.strictPlayback = nil
        XCTAssertEqual(model.savedPlan, expected)
        XCTAssertEqual(try model.scheduleStore.load(), expected)
        XCTAssertEqual(model.playbackMode, .normal)
        XCTAssertEqual(model.dailyGroupCount, 3)
        XCTAssertTrue(model.isNormalPlaybackLooping)

        let restarted = AppModel(directories: environment.directories,
                                 scheduleService: ScheduleService(calendar: testCalendar()),
                                 preferences: environment.preferences, now: { testDate(2026, 9, 4) })
        XCTAssertNil(restarted.strictProgressToday)
        restarted.setPlaybackMode(.strict)
        let reset = try XCTUnwrap(restarted.beginStrictPlayback())
        XCTAssertEqual(reset.video, first.video)
        XCTAssertEqual(reset.index, 0)
        XCTAssertEqual(reset.position, 0)
        XCTAssertNotEqual(reset.sessionID, first.sessionID)
        XCTAssertThrowsError(try restarted.saveStrictProgress(first, seconds: 20, hasPlayed: true))
        XCTAssertThrowsError(try restarted.finishStrictEpisode(english))
        XCTAssertEqual(restarted.strictProgressToday?.position, 0)
    }

    func testManualResetUnlocksCompletedDayAndKeepsAutomaticDelayHistory() throws {
        let environment = try environment()
        var now = testDate(2026, 9, 4)
        let model = try model(environment, now: { now })
        model.setDailyGroupCount(1)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        _ = try model.finishStrictEpisode(XCTUnwrap(model.finishStrictEpisode(first)))
        XCTAssertTrue(try XCTUnwrap(model.strictProgressToday).isFinished)
        XCTAssertTrue(model.canResetTodayPlaybackProgress)
        try model.resetTodayPlaybackProgress()
        model.reloadSavedPlan()
        let reset = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(reset.video.id, "1-chinese")
        XCTAssertEqual(reset.position, 0)
        XCTAssertFalse(try XCTUnwrap(model.strictProgressToday).isFinished)
        XCTAssertEqual(model.savedPlan?.playbackTracking?.hasPlayed, true)
        // No playback after reset: today's original playback must still count.
        now = testDate(2026, 9, 5)
        model.refreshToday()
        XCTAssertEqual(try model.beginStrictPlayback()?.video.id, "2-chinese")
    }

    func testManualResetWithoutTodayProgressIsNoOp() throws {
        let environment = try environment()
        var now = testDate(2026, 9, 4)
        let model = try model(environment, now: { now })
        XCTAssertFalse(model.canResetTodayPlaybackProgress)
        let original = model.savedPlan
        try model.resetTodayPlaybackProgress()
        XCTAssertEqual(model.savedPlan, original)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertFalse(model.canResetTodayPlaybackProgress, "Preparing a player is not playback")
        let prepared = model.savedPlan
        try model.resetTodayPlaybackProgress()
        XCTAssertEqual(model.savedPlan, prepared)
        try model.saveStrictProgress(first, seconds: 2, hasPlayed: true)
        now = testDate(2026, 9, 5)
        model.refreshToday()
        XCTAssertFalse(model.canResetTodayPlaybackProgress)
        let nextDay = model.savedPlan
        try model.resetTodayPlaybackProgress()
        XCTAssertEqual(model.savedPlan, nextDay, "Do not erase another day's progress")
    }

    func testManualResetSaveFailureKeepsProgressAndCanRetry() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(first, seconds: 8, hasPlayed: true)
        let original = model.savedPlan
        let support = environment.directories.applicationSupportURL
        let backup = environment.rootURL.appendingPathComponent("Support-backup")
        try FileManager.default.moveItem(at: support, to: backup)
        try Data([0]).write(to: support)
        XCTAssertThrowsError(try model.resetTodayPlaybackProgress())
        XCTAssertEqual(model.savedPlan, original)
        XCTAssertTrue(model.canResetTodayPlaybackProgress)
        XCTAssertTrue(model.isCurrentStrictRequest(first))
        try FileManager.default.removeItem(at: support)
        try FileManager.default.moveItem(at: backup, to: support)
        XCTAssertEqual(try model.scheduleStore.load(), original)
        try model.resetTodayPlaybackProgress()
        XCTAssertNil(model.strictProgressToday)
        XCTAssertNil(try model.scheduleStore.load()?.strictPlayback)
    }

    func testChangedTodayPlanUnlocksCompletedDayButFutureOnlyChangeDoesNot() throws {
        let environment = try environment()
        let model = try model(environment)
        model.setDailyGroupCount(1)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        _ = try model.finishStrictEpisode(XCTUnwrap(model.finishStrictEpisode(first)))
        var edited = try XCTUnwrap(model.savedPlan)
        edited.orderedPairIDs = [1, 3, 2, 4]
        try model.savePlan(edited)
        XCTAssertNil(try model.beginStrictPlayback(), "Only future episodes changed")
        edited.orderedPairIDs = [2, 1, 3, 4]
        try model.savePlan(edited)
        let reset = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(reset.video.id, "2-chinese")
        XCTAssertEqual(reset.position, 0)
    }

    func testFutureOnlyChangeAndEquivalentGroupCountKeepPartialProgress() throws {
        let environment = try environment()
        let model = try model(environment)
        model.setDailyGroupCount(2)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(first, seconds: 7, hasPlayed: true)
        var edited = try XCTUnwrap(model.savedPlan)
        edited.orderedPairIDs = [1, 2, 4, 3]
        try model.savePlan(edited)
        XCTAssertEqual(try model.beginStrictPlayback()?.position, 7)
        model.setDailyGroupCount(2)
        XCTAssertEqual(try model.beginStrictPlayback()?.position, 7)
        model.setDailyGroupCount(4)
        let reset = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(reset.position, 0)
        try model.saveStrictProgress(reset, seconds: 5, hasPlayed: true)
        model.setDailyGroupCount(8)
        XCTAssertEqual(try model.beginStrictPlayback()?.position, 5,
                       "The actual list still contains the same four groups")
    }

    func testMovingPlanAwayAndBackCannotRestoreOldProgressOrOldCallbacks() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(first, seconds: 3, hasPlayed: true)
        let original = try XCTUnwrap(model.savedPlan)
        try model.savePlan(model.scheduleService.shifting(original, byDays: 1))
        XCTAssertTrue(model.todayStates.isEmpty)
        XCTAssertNil(try model.beginStrictPlayback())
        try model.savePlan(original)
        let reset = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(reset.video, first.video)
        XCTAssertEqual(reset.position, 0)
        XCTAssertThrowsError(try model.saveStrictProgress(first, seconds: 4, hasPlayed: true))
        XCTAssertThrowsError(try model.finishStrictEpisode(first))
    }

    func testOpeningWithoutPlaybackStillPostponesAndPlayedDaysDoNot() throws {
        let environment = try environment()
        var now = testDate(2026, 9, 4)
        let model = try model(environment, now: { now })
        XCTAssertNotNil(try model.beginStrictPlayback())
        now = testDate(2026, 9, 8)
        model.refreshToday()
        let delayed = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(delayed.video.id, "1-chinese")
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
        try model.saveStrictProgress(delayed, seconds: 0.01, hasPlayed: true)
        now = testDate(2026, 9, 9)
        model.refreshToday()
        XCTAssertEqual(try model.beginStrictPlayback()?.video.id, "2-chinese")
    }

    func testMissingNextResourceDoesNotSkipOrReplayCompletedEpisode() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        try environment.removeFile("1.mp4", language: .english)
        XCTAssertThrowsError(try model.finishStrictEpisode(first))
        XCTAssertEqual(model.strictProgressToday?.index, 1)
        XCTAssertThrowsError(try model.beginStrictPlayback())
        try environment.createFile("1.mp4", language: .english)
        XCTAssertEqual(try model.beginStrictPlayback()?.video.id, "1-english")
        XCTAssertThrowsError(try model.finishStrictEpisode(first), "Duplicate old end events cannot advance twice")
    }

    func testSaveFailureDoesNotAdvanceProgressAndCanRetry() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        let original = model.savedPlan
        let support = environment.directories.applicationSupportURL
        let backup = environment.rootURL.appendingPathComponent("Support-backup")
        try FileManager.default.moveItem(at: support, to: backup)
        try Data([0]).write(to: support)
        var edited = try XCTUnwrap(original)
        edited.orderedPairIDs = [2, 1, 3, 4]
        XCTAssertThrowsError(try model.savePlan(edited))
        model.setDailyGroupCount(1)
        XCTAssertEqual(model.dailyGroupCount, 3)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertThrowsError(try model.saveStrictProgress(first, seconds: 2, hasPlayed: true))
        XCTAssertThrowsError(try model.finishStrictEpisode(first))
        XCTAssertEqual(model.savedPlan, original)
        try FileManager.default.removeItem(at: support)
        try FileManager.default.moveItem(at: backup, to: support)
        XCTAssertEqual(try model.finishStrictEpisode(first)?.video.id, "1-english")
    }

    func testLegacyCheckpointWithoutSessionIDStillResumes() throws {
        let environment = try environment()
        let model = try model(environment)
        let first = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(first, seconds: 4, hasPlayed: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: environment.directories.scheduleURL)
        ) as? [String: Any])
        var progress = try XCTUnwrap(json["strictPlayback"] as? [String: Any])
        progress.removeValue(forKey: "sessionID")
        json["strictPlayback"] = progress
        try JSONSerialization.data(withJSONObject: json).write(to: environment.directories.scheduleURL)
        model.reloadSavedPlan()
        let resumed = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertEqual(resumed.position, 4)
        XCTAssertNil(resumed.sessionID)
        try model.saveStrictProgress(resumed, seconds: 5)
        XCTAssertEqual(try model.beginStrictPlayback()?.position, 5)
    }

    func testClockRollbackCannotResetQueueAndInvalidPositionsAreRejected() throws {
        let environment = try environment()
        var now = testDate(2026, 9, 4)
        let model = try model(environment, now: { now })
        let first = try XCTUnwrap(model.beginStrictPlayback())
        XCTAssertThrowsError(try model.saveStrictProgress(first, seconds: .nan))
        XCTAssertThrowsError(try model.saveStrictProgress(first, seconds: -1))
        XCTAssertThrowsError(try model.saveStrictProgress(first, seconds: .infinity))
        try model.saveStrictProgress(first, seconds: 3, hasPlayed: true)
        try model.saveStrictProgress(first, seconds: 2)
        XCTAssertEqual(model.strictProgressToday?.position, 3)
        now = testDate(2026, 9, 3)
        XCTAssertThrowsError(try model.beginStrictPlayback())
        now = testDate(2026, 9, 4)
        XCTAssertEqual(try model.beginStrictPlayback()?.position, 3)
    }

    func testCorruptStrictCheckpointIsNotOverwritten() throws {
        let environment = try environment()
        let model = try model(environment)
        _ = try model.beginStrictPlayback()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: environment.directories.scheduleURL)
        ) as? [String: Any])
        var progress = try XCTUnwrap(json["strictPlayback"] as? [String: Any])
        progress["index"] = 999
        json["strictPlayback"] = progress
        let corrupt = try JSONSerialization.data(withJSONObject: json)
        try corrupt.write(to: environment.directories.scheduleURL)
        model.reloadSavedPlan()
        XCTAssertNil(model.savedPlan)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(try model.beginStrictPlayback())
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), corrupt)
    }

    func testEmptyAndFuturePlansHaveNoStrictEntry() throws {
        let environment = try environment()
        let model = try model(environment)
        var plan = try XCTUnwrap(model.makeCandidate(startDate: testDate(2026, 9, 10)))
        try model.savePlan(plan)
        XCTAssertNil(try model.beginStrictPlayback())
        plan.orderedPairIDs = []
        try model.savePlan(plan)
        XCTAssertNil(try model.beginStrictPlayback())
    }

    private func environment() throws -> TemporaryAppEnvironment {
        let environment = try TemporaryAppEnvironment()
        for pairID in 1...4 {
            for language in VideoLanguage.allCases {
                try environment.createFile("\(pairID).mp4", language: language)
            }
        }
        return environment
    }

    private func model(_ environment: TemporaryAppEnvironment,
                       now: @escaping () -> Date = { testDate(2026, 9, 4) }) throws -> AppModel {
        let model = AppModel(directories: environment.directories,
                             scheduleService: ScheduleService(calendar: testCalendar()),
                             preferences: environment.preferences, now: now)
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: now())))
        model.setPlaybackMode(.strict)
        return model
    }
}
