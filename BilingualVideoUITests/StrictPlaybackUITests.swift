import XCTest

@MainActor
final class StrictPlaybackUITests: XCTestCase {
    func testHomeFollowsBothLandscapeOrientations() throws {
        continueAfterFailure = false
        let app = try launchFixture()
        XCTAssertTrue(app.buttons["today.strict.play"].waitForExistence(timeout: 5))
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let isLandscape = orientation.isLandscape
            let rotated = NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return isLandscape ? frame.width > frame.height : frame.height > frame.width
            }
            let result = XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 5
            )
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "home-orientation-\(orientation.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertEqual(result, .completed, "Home must rotate with the iPad, not remain portrait")
            XCTAssertTrue(app.buttons["today.strict.play"].isHittable)
        }
    }

    func testSingleEntryNoSeekingPauseAndResumeAfterRelaunch() throws {
        let app = try launchFixture()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["today.strict.resumeSummary"].exists)
        XCTAssertFalse(app.buttons["today.play.5.chinese"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "today.strict.play").count, 1)
        entry.tap()
        let pause = app.buttons["strict.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        waitForSeconds(4)
        XCTAssertFalse(pause.exists, "Transport controls automatically hide during playback")
        revealControls(app)
        XCTAssertEqual(app.sliders.count, 0)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'skip' OR label CONTAINS '快进' OR label CONTAINS '重播'")).count, 0)
        pause.tap()
        XCTAssertEqual(pause.label, "继续播放")
        let paused = seconds(in: app)
        XCTAssertGreaterThanOrEqual(paused, 1)
        waitForSeconds(1)
        XCTAssertEqual(seconds(in: app), paused, "Pause must hold the actual position")
        // A horizontal drag on the video must not seek it while paused.
        app.otherElements["strict.surface"].firstMatch.swipeRight()
        XCTAssertEqual(seconds(in: app), paused)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "strict-paused-no-seek-controls"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["strict.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "继续观看")
        assertReadOnlyResumeSummary(in: app, position: paused)
        app.terminate()
        app.launchArguments.append("--ui-test-preserve")
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "继续观看")
        assertReadOnlyResumeSummary(in: app, position: paused)
        entry.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(in: app), paused)
        XCTAssertTrue(app.staticTexts["strict.currentEpisode"].label.contains("第 1 / 2 集"))
        app.buttons["strict.close"].tap()
        increaseDailyGroupCount(in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "开始观看")
        entry.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertLessThan(seconds(in: app), paused)
        XCTAssertTrue(app.staticTexts["strict.currentEpisode"].label.contains("第 1 / 4 集"))
        app.buttons["strict.close"].tap()
    }

    func testWholeDayFinishesAndRemainsLockedAfterRelaunch() throws {
        let app = try launchFixture()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["strict.finished"].waitForExistence(timeout: 35))
        XCTAssertEqual(app.staticTexts["strict.finished"].label, "今天的视频已经播放完毕")
        XCTAssertFalse(app.buttons["strict.pause"].exists)
        app.buttons["strict.close"].tap()
        let finished = app.staticTexts.matching(identifier: "today.strict.finished")
            .matching(NSPredicate(format: "label == %@", "今天的视频已经播放完毕")).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 3))
        XCTAssertFalse(entry.exists)
        app.terminate()
        app.launchArguments.append("--ui-test-preserve")
        app.launch()
        XCTAssertTrue(finished.waitForExistence(timeout: 5))
        XCTAssertFalse(entry.exists)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "strict-day-completed-after-relaunch"
        image.lifetime = .keepAlways
        add(image)
        increaseDailyGroupCount(in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertFalse(finished.exists)
        XCTAssertEqual(entry.label, "开始观看")
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["strict.currentEpisode"].label.contains("第 1 / 4 集"))
        XCTAssertLessThanOrEqual(seconds(in: app), 2)
        app.buttons["strict.close"].tap()
    }

    func testBackgroundStopsAndReturnsToResumeEntry() throws {
        let app = try launchFixture()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        waitForSeconds(2)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "继续观看")
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(in: app), 1)
        app.buttons["strict.close"].tap()
    }

    func testSavingChangedTodayPlanResetsProgressButDiscardingDraftDoesNot() throws {
        let app = try launchFixture()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        waitForSeconds(2)
        revealControls(app)
        app.buttons["strict.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "继续观看")

        shiftPlanOneDayEarlier(in: app)
        app.buttons["schedule.editor.close"].tap()
        let discard = app.buttons["放弃更改并关闭"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "继续观看")

        shiftPlanOneDayEarlier(in: app)
        app.buttons["schedule.editor.save"].tap()
        let confirm = app.buttons["确认保存"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        let todayImpact = app.staticTexts["schedule.preview.todayImpact"]
        XCTAssertTrue(todayImpact.exists)
        XCTAssertEqual(todayImpact.label, "今天的观看内容会改变")
        XCTAssertTrue(app.staticTexts["保存后，严格模式的今日进度会重置，从第一个视频重新开始。"].exists)
        confirm.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "开始观看")
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["strict.currentEpisode"].label.contains("编号 20 · 中文"))
        XCTAssertLessThanOrEqual(seconds(in: app), 2)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "changed-today-plan-starts-new-first-episode"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["strict.close"].tap()
    }

    private func launchFixture() throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-strict-playback"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "strict-playback", withExtension: "mp4"))
        app.launchEnvironment["UI_TEST_VIDEO_BASE64"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
        return app
    }

    func testParentCanCancelOrConfirmManualResetAndRestartFromBeginning() throws {
        let app = try launchFixture()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        openViewingSettings(in: app)
        let reset = app.buttons["settings.resetTodayProgress"]
        XCTAssertFalse(reset.isEnabled, "No progress to reset yet")
        app.buttons["schedule.editor.close"].tap()
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        waitForSeconds(3)
        revealControls(app)
        app.buttons["strict.pause"].tap()
        let paused = seconds(in: app)
        XCTAssertGreaterThanOrEqual(paused, 2)
        app.buttons["strict.close"].tap()

        openViewingSettings(in: app)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        XCTAssertTrue(app.buttons["确认重置"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        app.buttons["schedule.editor.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "继续观看")
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(seconds(in: app), paused)
        app.buttons["strict.close"].tap()

        confirmManualReset(in: app)
        app.terminate()
        app.launchArguments.append("--ui-test-preserve")
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "开始观看")
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["strict.currentEpisode"].label.contains("第 1 / 2 集 · 编号 5 · 中文"))
        XCTAssertLessThan(seconds(in: app), paused)
        app.buttons["strict.close"].tap()
    }

    func testParentManualResetUnlocksCompletedDayWithoutChangingPlan() throws {
        let app = try launchFixture()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["strict.finished"].waitForExistence(timeout: 35))
        app.buttons["strict.close"].tap()
        XCTAssertFalse(entry.exists)
        confirmManualReset(in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "开始观看")
        XCTAssertFalse(app.staticTexts["today.strict.finished"].exists)
        entry.tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["strict.currentEpisode"].label.contains("第 1 / 2 集 · 编号 5 · 中文"))
        XCTAssertLessThanOrEqual(seconds(in: app), 2)
        app.buttons["strict.close"].tap()
    }

    private func openViewingSettings(in app: XCUIApplication) {
        app.buttons["ui-test.parent"].tap()
        let settings = app.staticTexts["观看设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let reset = app.buttons["settings.resetTodayProgress"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        for _ in 0..<3 where !reset.isHittable { app.swipeUp() }
    }

    private func confirmManualReset(in app: XCUIApplication) {
        openViewingSettings(in: app)
        let reset = app.buttons["settings.resetTodayProgress"]
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        let confirm = app.buttons["确认重置"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "parent-manual-reset-confirmation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        confirm.tap()
        XCTAssertTrue(app.alerts.staticTexts["今日进度已重置，可从第一集重新观看。"].waitForExistence(timeout: 3))
        app.alerts.buttons["知道了"].tap()
        XCTAssertFalse(reset.isEnabled)
        app.buttons["schedule.editor.close"].tap()
    }

    private func increaseDailyGroupCount(in app: XCUIApplication) {
        app.buttons["ui-test.parent"].tap()
        let settings = app.staticTexts["观看设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let stepper = app.steppers["settings.dailyGroupCount"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        stepper.buttons["settings.dailyGroupCount-Increment"].tap()
        app.buttons["schedule.editor.close"].tap()
    }

    private func shiftPlanOneDayEarlier(in app: XCUIApplication) {
        app.buttons["ui-test.parent"].tap()
        let editor = app.staticTexts["计划编辑"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let previous = app.buttons["schedule.shift.previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 3))
        for _ in 0..<3 where !previous.isHittable { app.swipeDown() }
        previous.tap()
    }

    private func revealControls(_ app: XCUIApplication) {
        if !app.buttons["strict.pause"].exists {
            app.otherElements["strict.surface"].firstMatch.tap()
        }
    }

    private func seconds(in app: XCUIApplication) -> Int {
        let label = app.staticTexts["strict.position"].label
        return Int(label.filter(\.isNumber)) ?? -1
    }

    private func assertReadOnlyResumeSummary(in app: XCUIApplication, position: Int) {
        let summary = app.descendants(matching: .any)["today.strict.resumeSummary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("接着看：编号 5 · 中文"))
        XCTAssertTrue(summary.label.contains("今天第 1 / 2 个视频"))
        XCTAssertTrue(summary.label.contains("已播放 \(position) 秒"))
        XCTAssertFalse(app.buttons["today.strict.resumeSummary"].exists, "The resume summary must not become another playback entry")
        XCTAssertEqual(app.buttons.matching(identifier: "today.strict.play").count, 1)
        XCTAssertEqual(app.sliders.count, 0)
    }

    private func waitForSeconds(_ seconds: TimeInterval) {
        let expectation = expectation(description: "Let real playback advance")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { expectation.fulfill() }
        wait(for: [expectation], timeout: seconds + 1)
    }
}
