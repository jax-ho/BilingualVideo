import UIKit
import XCTest

@MainActor
final class VisualAcceptanceUITests: XCTestCase {
    private var originalAppearance = XCUIDevice.shared.appearance

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        originalAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .light
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIApplication().terminate()
        XCUIDevice.shared.appearance = originalAppearance
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testChildHomeRotatesAndModeChangesKeepClearPlaybackEntries() {
        let app = launchFixture()
        let entry = app.buttons["today.strict.play"]
        assertReachable(entry, in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "today.strict.play").count, 1)
        attachScreen("visual-child-strict-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        assertOrientation(in: app, landscape: true)
        assertReachable(entry, in: app)
        attachScreen("visual-child-strict-landscape")

        app.buttons["ui-test.parent"].tap()
        openDestination("settings.viewing", in: app)
        let normalMode = app.buttons["settings.mode.normal"]
        reveal(normalMode, in: app)
        normalMode.tap()
        XCTAssertEqual(normalMode.value as? String, "已选择")
        app.buttons["schedule.editor.close"].tap()

        let chinese = app.buttons["today.play.5.chinese"]
        let english = app.buttons["today.play.5.english"]
        assertReachable(chinese, in: app)
        assertReachable(english, in: app)
        XCTAssertEqual(chinese.frame.width, english.frame.width, accuracy: 1, "Both languages must receive equal touch area")
        XCTAssertEqual(chinese.frame.height, english.frame.height, accuracy: 1)
        XCTAssertEqual(chinese.frame.minY, english.frame.minY, accuracy: 1, "At landscape width the two languages stay side by side")
        XCTAssertFalse(entry.exists)

        app.buttons["ui-test.parent"].tap()
        openDestination("settings.viewing", in: app)
        let strictMode = app.buttons["settings.mode.strict"]
        reveal(strictMode, in: app)
        strictMode.tap()
        XCTAssertEqual(strictMode.value as? String, "已选择")
        app.buttons["schedule.editor.close"].tap()
        assertReachable(entry, in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "today.strict.play").count, 1)
        XCTAssertFalse(chinese.exists)
        XCTAssertFalse(english.exists)
    }

    func testDarkParentSettingsAndCalendarRemainUsable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchFixture()
        XCUIDevice.shared.appearance = .dark
        XCTAssertEqual(XCUIDevice.shared.appearance, .dark)
        assertDarkCanvasIsRendered()
        assertOrientation(in: app, landscape: true)
        assertReachable(app.buttons["today.strict.play"], in: app)
        app.buttons["ui-test.parent"].tap()
        openDestination("settings.viewing", in: app)
        XCTAssertTrue(app.staticTexts["settings.autoSave"].waitForExistence(timeout: 3))
        let count = app.steppers["settings.dailyGroupCount"]
        reveal(count, in: app)
        count.buttons["settings.dailyGroupCount-Increment"].tap()
        XCTAssertEqual(count.value as? String, "2 组")

        openDestination("settings.resources", in: app)
        let scheduleEntry = app.buttons["resources.openSchedule"]
        reveal(scheduleEntry, in: app)
        assertReachable(scheduleEntry, in: app)
        scheduleEntry.tap()
        let selectedPair = app.buttons["schedule.shift.pair.20"]
        reveal(selectedPair, in: app)
        selectedPair.tap()
        XCTAssertEqual(selectedPair.value as? String, "已选择")
        let targetDay = app.buttons["schedule.calendar.day.2026-09-07"].firstMatch
        reveal(targetDay, in: app)
        targetDay.tap()
        XCTAssertTrue(targetDay.label.contains("当天第一组为编号 20"))
        XCTAssertTrue(app.buttons["schedule.editor.save"].isEnabled)
        assertDarkCanvasIsRendered()
        attachScreen("visual-parent-dark-calendar")
        app.buttons["schedule.editor.save"].tap()
        let confirm = app.buttons["确认保存"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["放映还没开始"].waitForExistence(timeout: 3))
    }

    func testAccessibilityTextActuallyScalesAndParentControlsRemainReachable() {
        let app = launchFixture()
        let heading = app.staticTexts["今天的放映"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        let standardHeadingHeight = heading.frame.height
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(heading.frame.height, standardHeadingHeight * 1.25, "The launch override must really enlarge text before accepting accessibility screenshots")
        let entry = app.buttons["today.strict.play"]
        reveal(entry, in: app)
        assertReachable(entry, in: app)
        XCTAssertEqual(app.buttons.matching(identifier: "today.strict.play").count, 1)

        app.buttons["ui-test.parent"].tap()
        openDestination("settings.viewing", in: app)
        let count = app.steppers["settings.dailyGroupCount"]
        let increment = count.buttons["settings.dailyGroupCount-Increment"]
        reveal(increment, in: app)
        XCTAssertTrue(count.exists)
        XCTAssertTrue(increment.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(increment.frame))
        increment.tap()
        XCTAssertEqual(count.value as? String, "2 组")
        let reset = app.buttons["settings.resetTodayProgress"]
        reveal(reset, in: app)
        XCTAssertTrue(reset.isHittable, "Even when disabled, the reset action and its state must be reachable without clipped content")
        XCTAssertFalse(reset.isEnabled, "Changing typography must not invent playback progress")
        attachScreen("visual-parent-accessibility-text")
        app.buttons["schedule.editor.close"].tap()
        reveal(entry, in: app)
        assertReachable(entry, in: app)
    }

    func testEmptyLibraryExplainsNextStepWithoutOfferingBrokenPlayback() {
        let app = launchFixture(extraArguments: ["--ui-test-empty-library"])
        let emptyTitle = app.staticTexts["准备好视频，就可以开始了"]
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.strict.play"].exists)
        XCTAssertFalse(app.buttons["today.play.5.chinese"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "添加视频，再安排观看计划")).firstMatch.exists)
        attachScreen("visual-child-empty-library")

        app.buttons["ui-test.parent"].tap()
        let instructions = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "进入")).firstMatch
        XCTAssertTrue(instructions.waitForExistence(timeout: 3), "An empty library should expand import guidance automatically")
        reveal(instructions, in: app)
        XCTAssertTrue(instructions.label.contains("我的 iPad"))
        XCTAssertTrue(instructions.label.contains("放牛班的春天"))
        let example = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "例如：")).firstMatch
        reveal(example, in: app)
        XCTAssertTrue(example.label.contains("Chinese/1.mp4"))
        XCTAssertTrue(example.label.contains("English/1.mp4"))
        XCTAssertFalse(app.buttons["resources.openSchedule"].exists, "With no videos, the next action is preparing files rather than an unusable plan")
        XCTAssertTrue(app.buttons["resources.refresh"].isHittable)
        attachScreen("visual-parent-empty-library-guidance")
    }

    func testParentPasswordGateRemainsReachableWithLargeTextAndFocus() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-strict-playback", "--ui-test-parent-gate",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        assertOrientation(in: app, landscape: true)
        let parentEntry = app.buttons["家长入口"]
        XCTAssertTrue(parentEntry.waitForExistence(timeout: 5))
        parentEntry.tap()
        let password = app.secureTextFields["parent.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        reveal(password, in: app)
        password.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        let cancel = app.buttons["parent.cancel"]
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(cancel.frame))
        XCTAssertLessThanOrEqual(cancel.frame.maxY, keyboard.frame.minY)
        XCTAssertTrue(keyboard.exists)
        // A connected hardware keyboard can leave a keyboard AX object without
        // drawing software keys. This image proves focus/layout, not key visibility.
        attachScreen("visual-parent-password-focused-accessibility-landscape")
        // Deliberately leave the password empty: this checks layout without
        // creating, verifying, changing, or logging any real parent credential.
        // Scrolling is allowed to dismiss the keyboard naturally; the entire
        // confirmation control must then be visible, not just its upper edge.
        let submit = app.buttons["parent.submit"]
        reveal(submit, in: app)
        XCTAssertTrue(submit.isHittable)
        XCTAssertTrue(visibleContentFrame(in: app).contains(submit.frame))
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(cancel.isHittable)
        attachScreen("visual-parent-submit-accessibility-landscape")
        cancel.tap()
        XCTAssertTrue(app.buttons["today.strict.play"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.secureTextFields["parent.password"].exists)
    }

    private func launchFixture(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-strict-playback"] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["ui-test.parent"].waitForExistence(timeout: 5))
        return app
    }

    private func openDestination(_ identifier: String, in app: XCUIApplication) {
        let destination = app.cells.containing(.any, identifier: identifier).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.isHittable)
        destination.tap()
    }

    private func assertReachable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame), "The complete primary action should fit within the iPad window")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<12 {
            let visibleFrame = visibleContentFrame(in: app)
            if element.exists, element.isHittable, visibleFrame.contains(element.frame) { return }
            let isAbove = element.exists && element.frame.height > 0
                && element.frame.minY < visibleFrame.minY
            let startY = isAbove ? 0.35 : 0.80
            let endY = isAbove ? 0.80 : 0.35
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let startOffset = visibleFrame.minY - window.frame.minY + visibleFrame.height * startY
            let endOffset = visibleFrame.minY - window.frame.minY + visibleFrame.height * endY
            origin.withOffset(CGVector(dx: window.frame.width * 0.86, dy: startOffset))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: window.frame.width * 0.86, dy: endOffset)))
        }
        XCTAssertTrue(element.exists && element.isHittable && visibleContentFrame(in: app).contains(element.frame), "The entire control must be reachable by scrolling: \(element.identifier)")
    }

    private func visibleContentFrame(in app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let navigationBottom = app.navigationBars.allElementsBoundByIndex
            .map(\.frame).filter { $0.intersects(window) }.map(\.maxY).max() ?? window.minY
        let top = max(window.minY, navigationBottom)
        let keyboard = app.keyboards.firstMatch
        let bottom = keyboard.exists ? min(window.maxY, keyboard.frame.minY) : window.maxY
        return CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top))
    }

    private func assertOrientation(in app: XCUIApplication, landscape: Bool) {
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertDarkCanvasIsRendered() {
        var ratio = 0.0
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            ratio = self.darkCanvasRatio(in: XCUIScreen.main.screenshot().image)
            return ratio > 0.20
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 5), .completed,
                       "Changing the device flag is not enough: the actual dark canvas must be rendered; ratio=\(ratio)")
    }

    private func darkCanvasRatio(in image: UIImage) -> Double {
        guard let source = image.cgImage else { return 0 }
        // Uniform whole-image sampling does not depend on screenshot rotation.
        // Render into explicit sRGB RGBA so component order/gamut are unambiguous.
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        var matches = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if abs(red - 23) <= 8, abs(green - 31) <= 8, abs(blue - 27) <= 8 {
                matches += 1
            }
        }
        return Double(matches) / Double(side * side)
    }
}
