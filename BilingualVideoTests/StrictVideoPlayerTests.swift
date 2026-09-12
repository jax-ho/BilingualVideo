import AVFoundation
import XCTest
@testable import BilingualVideo

@MainActor
final class StrictVideoPlayerTests: XCTestCase {
    func testRealPlayerRunsEntireQueueAndCompletionSurvivesRestart() async throws {
        let environment = try environment(sample: "short")
        let appModel = try model(environment)
        appModel.setDailyGroupCount(2)
        appModel.setNormalPlaybackLooping(true)
        let request = try XCTUnwrap(appModel.beginStrictPlayback())
        let player = StrictVideoPlayerModel(request: request, appModel: appModel)
        defer { player.close() }
        var order: [String] = []
        player.session.onVideoChanged = { order.append($0.id) }
        player.start()
        await waitUntil { player.isFinished || player.failure != nil }
        XCTAssertNil(player.failure)
        XCTAssertTrue(player.isFinished)
        XCTAssertEqual(order, ["1-chinese", "1-english", "2-chinese", "2-english"])
        XCTAssertEqual(player.session.player.rate, 0)
        appModel.reloadSavedPlan()
        XCTAssertNil(try appModel.beginStrictPlayback())
    }

    func testPauseCloseAndNewPlayerResumeActualPosition() async throws {
        let environment = try environment(sample: "strict-playback")
        let appModel = try model(environment)
        let first = StrictVideoPlayerModel(request: try XCTUnwrap(appModel.beginStrictPlayback()), appModel: appModel)
        first.start()
        await waitUntil { first.session.player.currentTime().seconds >= 1.2 }
        first.togglePause()
        let position = first.session.player.currentTime().seconds
        XCTAssertEqual(first.session.player.rate, 0)
        XCTAssertEqual(appModel.strictProgressToday?.position ?? -1, position, accuracy: 0.03)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(first.session.player.currentTime().seconds, position, accuracy: 0.01)
        first.close()
        appModel.reloadSavedPlan()
        let request = try XCTUnwrap(appModel.beginStrictPlayback())
        XCTAssertEqual(request.position, position, accuracy: 0.03)
        let second = StrictVideoPlayerModel(request: request, appModel: appModel)
        defer { second.close() }
        second.start()
        await waitUntil { second.isPlaying || second.failure != nil }
        XCTAssertNil(second.failure)
        second.togglePause()
        XCTAssertGreaterThanOrEqual(second.session.player.currentTime().seconds, position - 0.02)
        XCTAssertLessThan(second.session.player.currentTime().seconds, position + 0.5)
        XCTAssertEqual(second.request?.index, 0)
    }

    func testCorruptFileDoesNotCountOrSkipAndCloseDuringLoadDoesNotPlay() async throws {
        let environment = try environment(sample: "short")
        try environment.createFile("1.mp4", language: .chinese)
        let appModel = try model(environment)
        let request = try XCTUnwrap(appModel.beginStrictPlayback())
        let player = StrictVideoPlayerModel(request: request, appModel: appModel)
        player.start()
        await waitUntil { player.failure != nil }
        XCTAssertNotNil(player.failure)
        XCTAssertEqual(appModel.strictProgressToday?.index, 0)
        XCTAssertEqual(appModel.strictProgressToday?.hasStarted, false)
        player.close()

        let valid = try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "short", withExtension: "mp4")))
        try environment.createFile("1.mp4", language: .chinese, contents: valid)
        let closed = StrictVideoPlayerModel(request: request, appModel: appModel)
        closed.start()
        closed.close()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(closed.session.currentVideo)
        XCTAssertEqual(closed.session.player.rate, 0)
        XCTAssertEqual(appModel.strictProgressToday?.hasStarted, false)
    }

    func testMidnightStopsOldQueueWithoutCountingPlaybackOnNewDay() async throws {
        let environment = try environment(sample: "strict-playback")
        var now = testDate(2026, 9, 4)
        let appModel = try model(environment, now: { now })
        let player = StrictVideoPlayerModel(request: try XCTUnwrap(appModel.beginStrictPlayback()), appModel: appModel)
        defer { player.close() }
        player.start()
        await waitUntil { appModel.strictProgressToday?.hasStarted == true }
        now = testDate(2026, 9, 5)
        appModel.refreshToday()
        await waitUntil { player.shouldDismiss }
        XCTAssertTrue(player.shouldDismiss)
        XCTAssertEqual(player.session.player.rate, 0)
        XCTAssertEqual(appModel.savedPlan?.playbackTracking?.hasPlayed, false)
        XCTAssertEqual(try appModel.beginStrictPlayback()?.video.id, "2-chinese")
    }

    func testPersistenceFailurePausesRealPlaybackWithoutAdvancing() async throws {
        let environment = try environment(sample: "strict-playback")
        let appModel = try model(environment)
        let player = StrictVideoPlayerModel(request: try XCTUnwrap(appModel.beginStrictPlayback()), appModel: appModel)
        defer { player.close() }
        player.start()
        await waitUntil { appModel.strictProgressToday?.hasStarted == true }
        let support = environment.directories.applicationSupportURL
        let backup = environment.rootURL.appendingPathComponent("Support-backup")
        try FileManager.default.moveItem(at: support, to: backup)
        try Data([0]).write(to: support)
        await waitUntil { player.failure != nil }
        XCTAssertNotNil(player.failure)
        XCTAssertEqual(player.session.player.rate, 0)
        XCTAssertEqual(appModel.strictProgressToday?.index, 0)
        try FileManager.default.removeItem(at: support)
        try FileManager.default.moveItem(at: backup, to: support)
    }

    func testChangedTodayListStopsOldPlayerAndCannotOverwriteResetProgress() async throws {
        let environment = try environment(sample: "strict-playback")
        let appModel = try model(environment)
        let old = StrictVideoPlayerModel(request: try XCTUnwrap(appModel.beginStrictPlayback()), appModel: appModel)
        defer { old.close() }
        old.start()
        await waitUntil { old.session.player.currentTime().seconds >= 1.2 }
        // Keep the same first episode: the old ticket must still be rejected.
        appModel.setDailyGroupCount(1)
        let reset = try XCTUnwrap(appModel.beginStrictPlayback())
        await waitUntil { old.shouldDismiss }
        XCTAssertEqual(old.session.player.rate, 0)
        XCTAssertEqual(appModel.strictProgressToday?.position, 0)
        XCTAssertEqual(appModel.strictProgressToday?.hasStarted, false)
        XCTAssertEqual(appModel.strictProgressToday?.index, 0)
        XCTAssertEqual(appModel.savedPlan?.playbackTracking?.hasPlayed, true)
        let fresh = StrictVideoPlayerModel(request: reset, appModel: appModel)
        defer { fresh.close() }
        fresh.start()
        await waitUntil { fresh.isPlaying || fresh.failure != nil }
        XCTAssertNil(fresh.failure)
        fresh.togglePause()
        XCTAssertLessThan(fresh.session.player.currentTime().seconds, 0.5)
        XCTAssertEqual(fresh.request?.video.id, "1-chinese")
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for real player", file: file, line: line)
    }

    private func environment(sample: String) throws -> TemporaryAppEnvironment {
        let environment = try TemporaryAppEnvironment()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: sample, withExtension: "mp4"))
        let contents = try Data(contentsOf: url)
        for id in 1...2 {
            for language in VideoLanguage.allCases {
                try environment.createFile("\(id).mp4", language: language, contents: contents)
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
