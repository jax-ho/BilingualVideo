import UIKit
import XCTest

@MainActor
final class PlaybackOrientationUITests: XCTestCase {
    func testLandscapeCalendarShiftSurvivesPortraitRotationAndSaves() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-schedule-editor"]
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()
        XCTAssertTrue(app.buttons["schedule.editor.close"].waitForExistence(timeout: 5))
        assertWindowOrientation(in: app, landscape: true)

        let source = app.buttons["schedule.shift.pair.100"]
        scrollDetailToReveal(source, in: app)
        source.tap()
        XCTAssertEqual(source.value as? String, "已选择")

        // The selected group and target day do not need to fit on screen together.
        let target = app.buttons["schedule.calendar.day.2026-09-05"].firstMatch
        scrollDetailToReveal(target, in: app)
        XCTAssertTrue(target.label.contains("编号 5"))
        target.tap()
        XCTAssertTrue(target.label.contains("编号 100"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-03"].firstMatch.label.contains("编号 5"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-04"].firstMatch.label.contains("编号 20"))
        let landscapeScreenshot = XCTAttachment(screenshot: app.screenshot())
        landscapeScreenshot.name = "calendar-shift-landscape"
        landscapeScreenshot.lifetime = .keepAlways
        add(landscapeScreenshot)

        XCUIDevice.shared.orientation = .portrait
        assertWindowOrientation(in: app, landscape: false)
        scrollDetailToReveal(target, in: app)
        XCTAssertTrue(target.label.contains("编号 100"), "Rotation must preserve the unsaved calendar adjustment")
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-03"].firstMatch.label.contains("编号 5"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-04"].firstMatch.label.contains("编号 20"))
        let portraitScreenshot = XCTAttachment(screenshot: app.screenshot())
        portraitScreenshot.name = "calendar-shift-retained-after-portrait-rotation"
        portraitScreenshot.lifetime = .keepAlways
        add(portraitScreenshot)

        let save = app.buttons["schedule.editor.save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.tap()
        let confirm = app.buttons["确认保存"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["计划编辑已关闭"].waitForExistence(timeout: 3))
    }

    func testParentViewingSettingsColdLaunchInLandscapeAndRemainUsableAfterPortraitRotation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-schedule-editor", "--ui-test-viewing-settings"]
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()

        let settings = app.staticTexts["观看设置"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        assertWindowOrientation(in: app, landscape: true)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let stepper = app.steppers["settings.dailyGroupCount"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        XCTAssertEqual(stepper.value as? String, "3 组")
        let increment = stepper.buttons["settings.dailyGroupCount-Increment"]
        XCTAssertTrue(increment.isHittable)
        increment.tap()
        XCTAssertEqual(stepper.value as? String, "4 组")
        XCTAssertEqual(app.state, .runningForeground)
        let landscapeScreenshot = XCTAttachment(screenshot: app.screenshot())
        landscapeScreenshot.name = "parent-viewing-settings-landscape-cold-launch"
        landscapeScreenshot.lifetime = .keepAlways
        add(landscapeScreenshot)

        XCUIDevice.shared.orientation = .portrait
        assertWindowOrientation(in: app, landscape: false)
        XCTAssertEqual(stepper.value as? String, "4 组", "Rotation must retain the selected setting")
        let decrement = stepper.buttons["settings.dailyGroupCount-Decrement"]
        XCTAssertTrue(decrement.isHittable)
        decrement.tap()
        XCTAssertEqual(stepper.value as? String, "3 组")
        XCTAssertEqual(app.state, .runningForeground)
        let portraitScreenshot = XCTAttachment(screenshot: app.screenshot())
        portraitScreenshot.name = "parent-viewing-settings-after-portrait-rotation"
        portraitScreenshot.lifetime = .keepAlways
        add(portraitScreenshot)
        app.buttons["schedule.editor.close"].tap()
        XCTAssertTrue(app.buttons["today.strict.play"].waitForExistence(timeout: 3))
    }

    func testStrictPlayerRotatesBothWaysWithoutLosingPausedPositionAndResumesAfterClosing() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try launchFixture()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        assertWindowOrientation(in: app, landscape: false)
        let portraitFrame = app.windows.firstMatch.frame
        entry.tap()
        let pause = app.buttons["strict.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        waitForSeconds(2)
        revealControls(in: app)
        pause.tap()
        XCTAssertEqual(pause.label, "继续播放")
        let pausedPosition = seconds(in: app)
        XCTAssertGreaterThanOrEqual(pausedPosition, 1)
        let episode = app.staticTexts["strict.currentEpisode"].label

        let orientations: [(UIDeviceOrientation, String)] = [
            (.landscapeLeft, "landscape-left"),
            (.landscapeRight, "landscape-right"),
            (.portrait, "portrait")
        ]
        for (orientation, name) in orientations {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation.isLandscape
            assertWindowOrientation(in: app, landscape: landscape)
            let frame = app.windows.firstMatch.frame
            XCTAssertEqual(frame.width, landscape ? portraitFrame.height : portraitFrame.width, accuracy: 1)
            XCTAssertEqual(frame.height, landscape ? portraitFrame.width : portraitFrame.height, accuracy: 1)
            XCTAssertTrue(pause.isHittable, "Pause/resume must remain reachable after rotation")
            XCTAssertTrue(app.buttons["strict.close"].isHittable)
            XCTAssertEqual(pause.label, "继续播放", "Rotation must not restart a paused player")
            XCTAssertEqual(seconds(in: app), pausedPosition)
            XCTAssertEqual(app.staticTexts["strict.currentEpisode"].label, episode)
            XCTAssertEqual(app.sliders.count, 0, "Rotation must not expose seeking in strict mode")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "strict-paused-\(name)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        app.buttons["strict.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "继续观看")
        entry.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertEqual(pause.label, "继续播放")
        XCTAssertGreaterThanOrEqual(seconds(in: app), pausedPosition, "Closing after rotation must save progress")
        XCTAssertLessThanOrEqual(seconds(in: app), pausedPosition + 3, "Reopening must resume, not skip forward")
        XCTAssertEqual(app.staticTexts["strict.currentEpisode"].label, episode)
        app.buttons["strict.close"].tap()
    }

    private func launchFixture() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-strict-playback"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "strict-playback", withExtension: "mp4"))
        app.launchEnvironment["UI_TEST_VIDEO_BASE64"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
        return app
    }

    private func scrollDetailToReveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            // Stay in the right-hand detail column; app.swipeUp() can hit the sidebar.
            let elementIsAboveViewport = element.exists && element.frame.height > 0
                && element.frame.maxY < window.frame.minY + window.frame.height * 0.25
            let startY = elementIsAboveViewport ? 0.35 : 0.80
            let endY = elementIsAboveViewport ? 0.80 : 0.35
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: startY))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: endY)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "The calendar control must be reachable by scrolling the detail column: \(element.identifier)")
    }

    private func assertWindowOrientation(in app: XCUIApplication, landscape: Bool) {
        let predicate = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            guard frame.width > 0, frame.height > 0 else { return false }
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        if result != .completed {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "orientation-failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(
            result, .completed,
            "The actual app window must become \(landscape ? "landscape" : "portrait"), not just the simulator shell: \(app.windows.firstMatch.frame)"
        )
    }

    private func revealControls(in app: XCUIApplication) {
        if !app.buttons["strict.pause"].exists {
            app.otherElements["strict.surface"].firstMatch.tap()
        }
    }

    private func seconds(in app: XCUIApplication) -> Int {
        Int(app.staticTexts["strict.position"].label.filter(\.isNumber)) ?? -1
    }

    private func waitForSeconds(_ seconds: TimeInterval) {
        let expectation = expectation(description: "Let real playback advance")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { expectation.fulfill() }
        wait(for: [expectation], timeout: seconds + 1)
    }
}
