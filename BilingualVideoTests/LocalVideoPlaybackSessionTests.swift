@preconcurrency import AVFoundation
import XCTest
@testable import BilingualVideo

@MainActor
final class LocalVideoPlaybackSessionTests: XCTestCase {
    func testPreparingDoesNotCountAsPlaybackButActualPlayingDoes() async throws {
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let video = try makeVideos()[0]
        let premature = expectation(description: "Preparing is not playback")
        premature.isInverted = true
        session.onPlayback = { _, _ in premature.fulfill() }
        try await session.prepare(video: video)
        await fulfillment(of: [premature], timeout: 0.3)
        let started = expectation(description: "Actual playback is recorded before completion")
        var didReport = false
        session.onPlayback = { played, _ in
            XCTAssertEqual(played, video)
            if !didReport {
                didReport = true
                started.fulfill()
            }
        }
        session.play()
        await fulfillment(of: [started], timeout: 3)
        session.pause()
        XCTAssertLessThan(session.player.currentTime().seconds, 0.4)
    }

    func testCorruptLoadNeverCountsAsPlayback() async throws {
        let environment = try TemporaryAppEnvironment()
        try environment.createFile("bad.mp4", language: .chinese)
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let reported = expectation(description: "Failed loading is not playback")
        reported.isInverted = true
        session.onPlayback = { _, _ in reported.fulfill() }
        do {
            try await session.prepare(video: PlayableVideo(
                pairID: 1, language: .chinese,
                url: environment.directories.folderURL(for: .chinese).appendingPathComponent("bad.mp4")
            ))
            XCTFail("Corrupt video should fail")
        } catch { }
        session.play()
        await fulfillment(of: [reported], timeout: 0.3)
    }

    func testContinuousPlaybackRecordsNewDayWithoutRestartingVideo() async throws {
        let environment = try TemporaryAppEnvironment()
        let sample = try Data(contentsOf: makeVideos()[0].url)
        for id in 1...3 {
            for language in VideoLanguage.allCases {
                try environment.createFile("\(id).mp4", language: language, contents: sample)
            }
        }
        var now = testDate(2026, 9, 4)
        let model = AppModel(directories: environment.directories,
                             scheduleService: ScheduleService(calendar: testCalendar()),
                             preferences: environment.preferences, now: { now })
        model.setPlaybackMode(.normal)
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: now)))
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let firstDay = expectation(description: "First playing day")
        let secondDay = expectation(description: "Same video keeps playing into next day")
        var reportedFirst = false
        var reportedSecond = false
        session.onPlayback = { _, _ in
            model.recordPlayback(at: now)
            if !reportedFirst {
                reportedFirst = true
                firstDay.fulfill()
            }
        }
        let video = try XCTUnwrap(model.playableVideo(pairID: 1, for: .chinese))
        try await session.prepare(video: video)
        session.play()
        await fulfillment(of: [firstDay], timeout: 3)
        now = testDate(2026, 9, 5)
        // Ignore extra callbacks from the first day until the test clock advances.
        session.onPlayback = { _, _ in
            model.recordPlayback(at: now)
            if !reportedSecond {
                reportedSecond = true
                secondDay.fulfill()
            }
        }
        await fulfillment(of: [secondDay], timeout: 3)
        XCTAssertEqual(session.currentVideo, video)
        XCTAssertEqual(model.savedPlan?.playbackTracking, PlanPlaybackTracking(
            day: LocalDay(year: 2026, month: 9, day: 5), hasPlayed: true
        ))
        session.stop()
        now = testDate(2026, 9, 6)
        model.refreshToday()
        XCTAssertEqual(model.todayStates.map(\.id), [3])
    }

    func testRealPlaybackFollowsBilingualCardsAndStopsAfterLastEnglish() async throws {
        try await verifyRealBilingualPlayback(looping: false)
    }

    func testRealPlaybackFromEnglishLoopsBackToFirstChinese() async throws {
        try await verifyRealBilingualPlayback(looping: true)
    }

    private func verifyRealBilingualPlayback(looping: Bool) async throws {
        let environment = try TemporaryAppEnvironment()
        let sample = try Data(contentsOf: makeVideos()[0].url)
        for pairID in [20, 100] {
            for language in VideoLanguage.allCases {
                try environment.createFile("\(pairID).mp4", language: language, contents: sample)
            }
        }
        let model = AppModel(
            directories: environment.directories,
            scheduleService: ScheduleService(calendar: testCalendar()),
            preferences: environment.preferences,
            now: { testDate(2026, 9, 4) }
        )
        try model.savePlan(XCTUnwrap(model.makeCandidate(startDate: testDate(2026, 9, 4))))
        model.setNormalPlaybackLooping(looping)
        model.setPlaybackMode(.normal)
        let session = LocalVideoPlaybackSession()
        defer {
            session.stop()
            session.onVideoChanged = nil
        }
        let finished = expectation(description: "Actual bilingual playback sequence")
        var played: [String] = []
        session.onFailure = { XCTFail($0) }
        session.onVideoChanged = { video in
            played.append(video.id)
            if looping && played.count == 4 {
                session.allowsAutomaticAdvance = false
                finished.fulfill()
            }
        }
        session.nextVideo = { video in
            let next = try model.nextVideo(after: video)
            if next == nil { finished.fulfill() }
            return next
        }
        let first = try XCTUnwrap(model.playableVideo(pairID: 20, for: looping ? .english : .chinese))
        try await session.prepare(video: first)
        session.play()
        await fulfillment(of: [finished], timeout: 8)
        XCTAssertEqual(played, looping
            ? ["20-english", "100-chinese", "100-english", "20-chinese"]
            : ["20-chinese", "20-english", "100-chinese", "100-english"])
        XCTAssertEqual(session.player.rate, 0)
    }

    func testRealEndNotificationsAdvanceAndStopAtLastVideo() async throws {
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let videos = try makeVideos()
        var played: [Int] = []
        let finished = expectation(description: "Final video actually reached its end")
        session.onFailure = { XCTFail($0) }
        session.onVideoChanged = { played.append($0.pairID) }
        session.nextVideo = { current in
            if current.pairID == 3 {
                finished.fulfill()
                return nil
            }
            return videos[current.pairID]
        }
        try await session.prepare(video: videos[0])
        session.play()
        await fulfillment(of: [finished], timeout: 8)
        XCTAssertEqual(played, [1, 2, 3])
        XCTAssertEqual(session.currentVideo, videos[2])
        XCTAssertEqual(session.player.rate, 0)
        XCTAssertGreaterThanOrEqual(session.player.currentTime().seconds, 0.35)
    }

    func testLoopFromMiddleReturnsToFirstVideoWithoutReplacingPlayer() async throws {
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let player = session.player
        let videos = try makeVideos()
        var played: [Int] = []
        let looped = expectation(description: "Middle to last to first")
        session.onFailure = { XCTFail($0) }
        session.onVideoChanged = { video in
            played.append(video.pairID)
            if played.count == 3 {
                session.allowsAutomaticAdvance = false
                looped.fulfill()
            }
        }
        session.nextVideo = { videos[$0.pairID % videos.count] }
        try await session.prepare(video: videos[1])
        session.play()
        await fulfillment(of: [looped], timeout: 8)
        XCTAssertEqual(played, [2, 3, 1])
        XCTAssertTrue(session.player === player)
        XCTAssertEqual(session.player.rate, 0, "Backgrounding during a transition must not start audio")
        session.onVideoChanged = nil
    }

    func testSingleVideoLoopCreatesAPlayableItemAgain() async throws {
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let video = try makeVideos()[0]
        let replayed = expectation(description: "Single video loop")
        session.onFailure = { XCTFail($0) }
        session.nextVideo = { $0 }
        try await session.prepare(video: video)
        let originalItem = session.player.currentItem
        session.onVideoChanged = { _ in
            session.allowsAutomaticAdvance = false
            replayed.fulfill()
        }
        session.play()
        await fulfillment(of: [replayed], timeout: 5)
        XCTAssertEqual(session.currentVideo, video)
        XCTAssertFalse(session.player.currentItem === originalItem)
        session.onVideoChanged = nil
    }

    func testCorruptNextVideoReportsFailureWithoutSkipping() async throws {
        let environment = try TemporaryAppEnvironment()
        try environment.createFile("99.mp4", language: .chinese)
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let first = try makeVideos()[0]
        let corrupt = PlayableVideo(
            pairID: 99, language: .chinese,
            url: environment.directories.folderURL(for: .chinese).appendingPathComponent("99.mp4")
        )
        var played: [Int] = []
        var advanceCount = 0
        let failed = expectation(description: "Corrupt next video fails")
        session.onFailure = { _ in failed.fulfill() }
        session.onVideoChanged = { played.append($0.pairID) }
        session.nextVideo = { _ in
            advanceCount += 1
            return corrupt
        }
        try await session.prepare(video: first)
        session.play()
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(played, [1])
        XCTAssertEqual(advanceCount, 1)
        XCTAssertEqual(session.player.rate, 0)
    }

    func testStoppedOrInactiveSessionCannotAdvanceFromEndNotification() async throws {
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let video = try makeVideos()[0]
        let advanced = expectation(description: "Must not advance")
        advanced.isInverted = true
        session.nextVideo = { _ in
            advanced.fulfill()
            return video
        }
        try await session.prepare(video: video)
        let oldItem = try XCTUnwrap(session.player.currentItem)
        session.allowsAutomaticAdvance = false
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        await fulfillment(of: [advanced], timeout: 0.2)
        session.stop()
        session.allowsAutomaticAdvance = true
        let advancedAfterStop = expectation(description: "Stopped session must not advance")
        advancedAfterStop.isInverted = true
        session.nextVideo = { _ in
            advancedAfterStop.fulfill()
            return video
        }
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        await fulfillment(of: [advancedAfterStop], timeout: 0.2)
        XCTAssertNil(session.player.currentItem)
        XCTAssertNil(session.currentVideo)
    }

    func testCancellationCannotReplaceANewerItem() async throws {
        let session = LocalVideoPlaybackSession()
        defer { session.stop() }
        let videos = try makeVideos()
        let canceledLoad = Task {
            try await session.prepare(video: videos[0])
        }
        canceledLoad.cancel()
        try await session.prepare(video: videos[1])
        do {
            try await canceledLoad.value
            XCTFail("Canceled load must not succeed")
        } catch is CancellationError {
            // A canceled old load must leave the new item intact.
        }
        XCTAssertEqual(session.currentVideo, videos[1])
        XCTAssertNotNil(session.player.currentItem)
    }

    private func makeVideos() throws -> [PlayableVideo] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "short", withExtension: "mp4"))
        return [1, 2, 3].map { PlayableVideo(pairID: $0, language: .chinese, url: url) }
    }
}
