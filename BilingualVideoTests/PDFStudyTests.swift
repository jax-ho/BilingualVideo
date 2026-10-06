import XCTest
@testable import BilingualVideo

@MainActor
final class PDFStudyTests: XCTestCase {
    func testNumericPDFScanSortsAndRejectsAmbiguousAndUnsupportedFiles() throws {
        let environment = try TemporaryAppEnvironment()
        for file in ["100.PDF", "20.pdf", "005.pdf", "5.pdf", "abc.pdf", "１.pdf", "note.txt"] {
            try Data([0]).write(to: environment.directories.razURL.appendingPathComponent(file))
        }
        let result = PDFLibraryScanner(directories: environment.directories).scan()
        XCTAssertEqual(result.books.map(\.id), [20, 100])
        XCTAssertEqual(result.issues.filter { $0.kind == .duplicateIdentifier }.count, 1)
        XCTAssertEqual(result.issues.filter { $0.kind == .invalidIdentifier }.count, 2)
        XCTAssertEqual(result.issues.filter { $0.kind == .unsupportedItem }.count, 1)
        XCTAssertFalse(result.isValidForGeneration)
    }

    func testPDFPlansAndSettingsPersistWithoutChangingVideoPlanOrProgress() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        let video = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(video, seconds: 12, hasPlayed: true)
        let videoBytes = try Data(contentsOf: environment.directories.scheduleURL)
        XCTAssertEqual(model.dailyPDFCount, 3)
        XCTAssertEqual(model.learningOrder, .videosFirst)
        model.setDailyPDFCount(2)
        model.setLearningOrder(.pdfsFirst)
        var pdfPlan = try XCTUnwrap(model.savedPDFPlan)
        pdfPlan.orderedPairIDs = [20, 5, 100]
        try model.savePDFPlan(pdfPlan)
        XCTAssertEqual(model.todayPDFIDs, [20, 5])
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), videoBytes)
        let restarted = makeModel(environment, now: { now })
        XCTAssertEqual(restarted.dailyPDFCount, 2)
        XCTAssertEqual(restarted.learningOrder, .pdfsFirst)
        XCTAssertEqual(restarted.todayPDFIDs, [20, 5])
        XCTAssertEqual(restarted.strictProgressToday?.position, 12)
    }

    func testLastPageNeedsExplicitCompletionAndResumesAfterRestart() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        model.setDailyPDFCount(2)
        let first = try XCTUnwrap(model.beginPDFReading())
        XCTAssertThrowsError(try model.finishPDFReading(first))
        try model.savePDFPage(first, pageIndex: 1, pageCount: 3)
        XCTAssertThrowsError(try model.finishPDFReading(first))
        try model.savePDFPage(first, pageIndex: 2, pageCount: 3)
        XCTAssertEqual(model.pdfProgressToday?.index, 0)
        XCTAssertFalse(try XCTUnwrap(model.pdfProgressToday).isFinished)
        let restarted = makeModel(environment, now: { now })
        let resumed = try XCTUnwrap(restarted.beginPDFReading())
        XCTAssertEqual(resumed.pageIndex, 2)
        let second = try XCTUnwrap(restarted.finishPDFReading(resumed))
        XCTAssertEqual(second.book.id, 20)
        XCTAssertEqual(second.pageIndex, 0)
        XCTAssertThrowsError(try restarted.finishPDFReading(resumed))
        try restarted.savePDFPage(second, pageIndex: 0, pageCount: 1)
        XCTAssertNil(try restarted.finishPDFReading(second))
        XCTAssertNil(try makeModel(environment, now: { now }).beginPDFReading())
    }

    func testPDFWindowChangeInvalidatesOldCallbacksButSameWindowPreservesProgress() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        let request = try XCTUnwrap(model.beginPDFReading())
        try model.savePDFPage(request, pageIndex: 2, pageCount: 3)
        model.setDailyPDFCount(4) // End of plan: actual list stays the same.
        XCTAssertTrue(model.isCurrentPDFRequest(request))
        try model.savePDFPlan(XCTUnwrap(model.savedPDFPlan))
        XCTAssertTrue(model.isCurrentPDFRequest(request))
        model.setDailyPDFCount(1)
        XCTAssertNil(model.pdfProgressToday)
        XCTAssertThrowsError(try model.savePDFPage(request, pageIndex: 2, pageCount: 3))
        let replacement = try XCTUnwrap(model.beginPDFReading())
        XCTAssertNotEqual(replacement.sessionID, request.sessionID)
        XCTAssertEqual(replacement.pageIndex, 0)
        XCTAssertEqual(model.savedPDFPlan?.playbackTracking?.hasPlayed, true)
    }

    func testMissingPDFDoesNotResetOrSubstituteAndRecoversWhenRestored() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        model.setDailyPDFCount(1)
        let request = try XCTUnwrap(model.beginPDFReading())
        try model.savePDFPage(request, pageIndex: 1, pageCount: 3)
        let url = environment.directories.razURL.appendingPathComponent("5.pdf")
        try FileManager.default.removeItem(at: url)
        model.refreshToday()
        XCTAssertEqual(model.todayPDFIDs, [5])
        XCTAssertEqual(model.pdfProgressToday?.pageIndex, 1)
        XCTAssertThrowsError(try model.beginPDFReading())
        try Data([0]).write(to: url)
        XCTAssertEqual(try model.beginPDFReading()?.pageIndex, 1)
    }

    func testReadingAndVideoDaysAdvanceIndependentlyAndExpireAcrossMidnight() throws {
        let environment = try TemporaryAppEnvironment()
        var now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        let request = try XCTUnwrap(model.beginPDFReading())
        // Merely requesting a PDF is not actual reading.
        XCTAssertEqual(model.savedPDFPlan?.playbackTracking?.hasPlayed, false)
        try model.savePDFPage(request, pageIndex: 0, pageCount: 3)
        now = testDate(2026, 10, 5)
        model.refreshToday()
        XCTAssertEqual(model.todayPDFIDs, [20, 100])
        XCTAssertEqual(model.todayStates.map(\.id), [5, 20, 100])
        XCTAssertThrowsError(try model.savePDFPage(request, pageIndex: 1, pageCount: 3))
        XCTAssertEqual(try model.beginPDFReading()?.book.id, 20)
        XCTAssertEqual(try model.beginPDFReading()?.pageIndex, 0)
        let snapshot = model.savedPDFPlan
        model.refreshToday()
        XCTAssertEqual(model.savedPDFPlan, snapshot)
    }

    func testOrderResumesNextUnfinishedActivityAndResetKeepsVideoProgress() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        model.setDailyPDFCount(1)
        XCTAssertEqual(model.nextStudyContent, .video)
        model.setLearningOrder(.pdfsFirst)
        XCTAssertEqual(model.nextStudyContent, .pdf)
        let request = try XCTUnwrap(model.beginPDFReading())
        try model.savePDFPage(request, pageIndex: 0, pageCount: 1)
        XCTAssertNil(try model.finishPDFReading(request))
        XCTAssertEqual(model.nextStudyContent, .video)
        let video = try XCTUnwrap(model.beginStrictPlayback())
        try model.saveStrictProgress(video, seconds: 4, hasPlayed: true)
        try model.resetTodayPDFProgress()
        XCTAssertEqual(model.nextStudyContent, .pdf)
        XCTAssertEqual(model.strictProgressToday?.position, 4)
        XCTAssertFalse(model.isCurrentPDFRequest(request))
    }

    func testFailedProgressWriteKeepsCurrentPDFAndSettings() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        let request = try XCTUnwrap(model.beginPDFReading())
        try model.savePDFPage(request, pageIndex: 2, pageCount: 3)
        let snapshot = model.savedPDFPlan
        let directory = environment.directories.applicationSupportURL
        try FileManager.default.removeItem(at: directory)
        try Data([0]).write(to: directory)
        XCTAssertThrowsError(try model.finishPDFReading(request))
        XCTAssertEqual(model.savedPDFPlan, snapshot)
        model.setDailyPDFCount(1)
        XCTAssertEqual(model.dailyPDFCount, 3)
        XCTAssertEqual(model.savedPDFPlan, snapshot)
    }

    func testNormalVideoCompletionHandsOffWithoutLoopingOrResettingPDF() throws {
        let environment = try TemporaryAppEnvironment()
        let now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        model.setPlaybackMode(.normal)
        model.setDailyGroupCount(1)
        let pdfBytes = try Data(contentsOf: environment.directories.pdfScheduleURL)
        let day = model.scheduleService.day(containing: now)
        let chinese = try XCTUnwrap(model.nextStudyVideo())
        try model.recordNormalEpisodeCompletion(chinese, on: day)
        let english = try XCTUnwrap(model.nextStudyVideo())
        XCTAssertEqual(english.language, .english)
        try model.recordNormalEpisodeCompletion(english, on: day)
        XCTAssertNil(try model.nextStudyVideo())
        XCTAssertEqual(model.nextStudyContent, .pdf)
        XCTAssertEqual(try Data(contentsOf: environment.directories.pdfScheduleURL), pdfBytes)
        let restarted = makeModel(environment, now: { now })
        XCTAssertEqual(restarted.nextStudyContent, .pdf)
    }

    func testFailedDailySettlementDoesNotSkipUnfinishedActivities() throws {
        let environment = try TemporaryAppEnvironment()
        var now = testDate(2026, 10, 3)
        let model = try preparedModel(environment, now: { now })
        now = testDate(2026, 10, 5)
        let directory = environment.directories.applicationSupportURL
        try FileManager.default.removeItem(at: directory)
        try Data([0]).write(to: directory)
        model.refreshToday()
        XCTAssertFalse(model.videosFinishedToday)
        XCTAssertEqual(model.nextStudyContent, .video)
        XCTAssertThrowsError(try model.beginStrictPlayback())
        model.setLearningOrder(.pdfsFirst)
        XCTAssertEqual(model.nextStudyContent, .pdf)
        XCTAssertThrowsError(try model.beginPDFReading())
    }

    private func makeModel(_ environment: TemporaryAppEnvironment, now: @escaping () -> Date) -> AppModel {
        AppModel(directories: environment.directories, scheduleService: ScheduleService(calendar: testCalendar()),
                 preferences: environment.preferences, now: now)
    }

    private func preparedModel(_ environment: TemporaryAppEnvironment, now: @escaping () -> Date) throws -> AppModel {
        for id in [5, 20, 100] {
            try Data([0]).write(to: environment.directories.razURL.appendingPathComponent("\(id).pdf"))
            for language in VideoLanguage.allCases { try environment.createFile("\(id).mp4", language: language) }
        }
        let model = makeModel(environment, now: now)
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: now())))
        try model.savePDFPlan(XCTUnwrap(model.makePDFCandidate(startDate: now())))
        return model
    }
}
