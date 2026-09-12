import XCTest
@testable import BilingualVideo

@MainActor
final class AutomaticDelayTests: XCTestCase {
    func testUnplayedDayAndLongAbsenceKeepSameWindowWithoutRepeatedDelay() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
        model.setPlaybackMode(.normal)
        // Looking up a card is not actual playback.
        XCTAssertNotNil(model.playableVideo(pairID: 1, for: .chinese))
        now = testDate(2026, 9, 9)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
        XCTAssertEqual(days(model), [9, 10, 11, 12, 13])
        let bytes = try Data(contentsOf: environment.directories.scheduleURL)
        model.refreshToday()
        model.activate()
        model.deactivate()
        let restarted = makeModel(environment, now: { now })
        XCTAssertEqual(restarted.savedPlan, model.savedPlan)
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), bytes)
    }

    func testOnePlaybackAdvancesOnlyOneGroupAndKeepsPastDates() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        model.recordPlayback(at: now)
        let bytes = try Data(contentsOf: environment.directories.scheduleURL)
        model.recordPlayback(at: now)
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), bytes)
        now = testDate(2026, 9, 8)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.map(\.id), [2, 3, 4])
        XCTAssertEqual(days(model), [4, 8, 9, 10, 11])
        XCTAssertEqual(model.savedPlan?.startDay, LocalDay(year: 2026, month: 9, day: 4))
        model.recordPlayback(at: now)
        now = testDate(2026, 9, 9)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.map(\.id), [3, 4, 5])
        XCTAssertEqual(days(model), [4, 8, 9, 10, 11])
    }

    func testTwoSeparateMissesPreserveBothWatchedDatesAndManualShiftGaps() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        model.recordPlayback(at: now)
        now = testDate(2026, 9, 6)
        model.recordPlayback(at: now)
        now = testDate(2026, 9, 8)
        model.refreshToday()
        XCTAssertEqual(days(model), [4, 6, 8, 9, 10])
        let plan = try XCTUnwrap(model.savedPlan)
        let shifted = model.scheduleService.shifting(
            plan, movingPairID: 3, to: LocalDay(year: 2026, month: 9, day: 11)
        )
        XCTAssertEqual(model.scheduleService.preview(shifted).map { $0.day.day }, [7, 9, 11, 12, 13])
        XCTAssertNil(model.scheduleService.pairID(in: plan, on: testDate(2026, 9, 5)))
        XCTAssertEqual(model.scheduleService.pairID(in: plan, on: testDate(2026, 9, 8)), 3)
    }

    func testLegacyPlanStartsTrackingTodayWithoutRetroactiveMisses() throws {
        let environment = try makeEnvironment()
        try ScheduleStore(fileURL: environment.directories.scheduleURL).save(makePlan())
        var now = testDate(2026, 9, 6)
        let model = makeModel(environment, now: { now })
        XCTAssertEqual(days(model), [4, 5, 6, 7, 8])
        XCTAssertEqual(model.todayStates.map(\.id), [3, 4, 5])
        XCTAssertEqual(model.savedPlan?.playbackTracking?.day, LocalDay(year: 2026, month: 9, day: 6))
        now = testDate(2026, 9, 7)
        model.refreshToday()
        XCTAssertEqual(days(model), [4, 5, 7, 8, 9])
        XCTAssertEqual(model.todayStates.map(\.id), [3, 4, 5])
    }

    func testDaysBeforeFutureStartDoNotCountAsMissedDays() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        var plan = makePlan()
        plan.startDay = LocalDay(year: 2026, month: 9, day: 10)
        try model.savePlan(plan)
        now = testDate(2026, 9, 8)
        model.refreshToday()
        XCTAssertTrue(model.todayStates.isEmpty)
        XCTAssertEqual(days(model), [10, 11, 12, 13, 14])
        now = testDate(2026, 9, 12)
        model.refreshToday()
        XCTAssertEqual(days(model), [12, 13, 14, 15, 16])
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
    }

    func testCompletedOrAlreadyExpiredPlansAreNotRevived() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 8)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        model.recordPlayback(at: now)
        now = testDate(2026, 9, 20)
        model.refreshToday()
        XCTAssertTrue(model.todayStates.isEmpty)
        XCTAssertEqual(days(model), [4, 5, 6, 7, 8])
        try model.savePlan(makePlan())
        now = testDate(2026, 9, 21)
        model.refreshToday()
        XCTAssertTrue(model.todayStates.isEmpty)
        XCTAssertEqual(days(model), [4, 5, 6, 7, 8])
    }

    func testClockMovingBackDoesNotUndoSettlementOrErasePlayback() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        now = testDate(2026, 9, 6)
        model.recordPlayback(at: now)
        let saved = model.savedPlan
        now = testDate(2026, 9, 5)
        model.refreshToday()
        model.recordPlayback(at: now)
        XCTAssertEqual(model.savedPlan, saved)
        now = testDate(2026, 9, 7)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.map(\.id), [2, 3, 4])
    }

    func testSettlementAcrossDSTLeapDayAndYearUsesCalendarDays() {
        for (calendar, start, end) in [
            (testCalendar(timeZoneIdentifier: "America/Los_Angeles"), LocalDay(year: 2026, month: 3, day: 7), LocalDay(year: 2026, month: 3, day: 9)),
            (testCalendar(), LocalDay(year: 2028, month: 2, day: 28), LocalDay(year: 2028, month: 3, day: 1)),
            (testCalendar(), LocalDay(year: 2026, month: 12, day: 31), LocalDay(year: 2027, month: 1, day: 2))
        ] {
            let service = ScheduleService(calendar: calendar)
            var plan = makePlan()
            plan.startDay = start
            plan.playbackTracking = PlanPlaybackTracking(day: start, hasPlayed: false)
            let shifted = service.settlingUnplayedDays(in: plan, at: end.date(in: calendar)!)
            XCTAssertEqual(shifted.startDay, end)
            XCTAssertEqual(service.pairIDs(in: shifted, on: end.date(in: calendar)!, dailyGroupCount: 3), [1, 2, 3])
        }
    }

    func testMissingResourcesStillDelayWithoutSkippingOrChangingOrder() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        try environment.removeFile("1.mp4", language: .english)
        now = testDate(2026, 9, 7)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.first, .scheduledResourceUnavailable(pairID: 1))
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
        XCTAssertEqual(model.savedPlan?.orderedPairIDs, [1, 2, 3, 4, 5])
    }

    func testPlaybackPersistsAcrossRestartAndPlanEditingDoesNotClearIt() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        let oldDraft = try XCTUnwrap(model.savedPlan)
        model.recordPlayback(at: now)
        var edited = oldDraft
        edited.orderedPairIDs.swapAt(1, 2)
        try model.savePlan(edited)
        XCTAssertEqual(model.savedPlan?.playbackTracking?.hasPlayed, true)
        now = testDate(2026, 9, 5)
        let restarted = makeModel(environment, now: { now })
        XCTAssertEqual(restarted.todayStates.map(\.id), [3, 2, 4])
        XCTAssertEqual(days(restarted), [4, 5, 6, 7, 8])
    }

    func testStaleEditedDraftCannotOverwriteAutomaticDelay() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        var draft = try XCTUnwrap(model.savedPlan)
        draft.orderedPairIDs.swapAt(1, 2)
        now = testDate(2026, 9, 6)
        XCTAssertThrowsError(try model.savePlan(draft))
        XCTAssertEqual(days(model), [6, 7, 8, 9, 10])
        XCTAssertEqual(model.savedPlan?.orderedPairIDs, [1, 2, 3, 4, 5])
    }

    func testFailedPersistencePreservesCheckpointAndRetryDoesNotDoubleDelay() throws {
        let environment = try makeEnvironment()
        var now = testDate(2026, 9, 4)
        let model = makeModel(environment, now: { now })
        try model.savePlan(makePlan())
        let before = model.savedPlan
        let support = environment.directories.applicationSupportURL
        let backup = environment.rootURL.appendingPathComponent("Support-backup")
        try FileManager.default.moveItem(at: support, to: backup)
        try Data([0]).write(to: support)
        now = testDate(2026, 9, 7)
        model.refreshToday()
        XCTAssertEqual(model.savedPlan, before)
        XCTAssertTrue(model.todayStates.isEmpty)
        model.recordPlayback(at: now)
        XCTAssertEqual(model.savedPlan, before)
        XCTAssertNotNil(model.errorMessage)
        try FileManager.default.removeItem(at: support)
        try FileManager.default.moveItem(at: backup, to: support)
        model.refreshToday()
        XCTAssertEqual(days(model), [7, 8, 9, 10, 11])
        XCTAssertEqual(model.todayStates.map(\.id), [1, 2, 3])
    }

    private func makeEnvironment() throws -> TemporaryAppEnvironment {
        let environment = try TemporaryAppEnvironment()
        for id in 1...5 {
            for language in VideoLanguage.allCases {
                try environment.createFile("\(id).mp4", language: language)
            }
        }
        return environment
    }

    private func makeModel(_ environment: TemporaryAppEnvironment, now: @escaping () -> Date) -> AppModel {
        AppModel(directories: environment.directories,
                 scheduleService: ScheduleService(calendar: testCalendar()),
                 preferences: environment.preferences, now: now)
    }

    private func makePlan() -> ViewingPlan {
        ViewingPlan(startDay: LocalDay(year: 2026, month: 9, day: 4),
                    orderedPairIDs: [1, 2, 3, 4, 5], updatedAt: .distantPast)
    }

    private func days(_ model: AppModel) -> [Int] {
        model.savedPlan.map { model.scheduleService.preview($0).map { $0.day.day } } ?? []
    }
}
