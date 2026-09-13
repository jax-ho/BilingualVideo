import XCTest

@MainActor
final class InteractionClarityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testResourceInstructionsExplainFileLocationPairingAndNextStep() {
        let app = launchParentFixture()
        openDestination("settings.resources", in: app)
        let help = element("resources.importHelp", in: app)
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        help.tap()

        let path = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "进入")).firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 3))
        XCTAssertTrue(path.label.contains("我的 iPad"))
        XCTAssertTrue(path.label.contains("放牛班的春天"))
        let rule = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "中文放进")).firstMatch
        XCTAssertTrue(rule.label.contains("Chinese"))
        XCTAssertTrue(rule.label.contains("English"))
        XCTAssertTrue(rule.label.contains("相同的数字编号"))
        let example = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "例如：")).firstMatch
        XCTAssertTrue(example.label.contains("Chinese/1.mp4"))
        XCTAssertTrue(example.label.contains("English/1.mp4"))
        XCTAssertTrue(app.staticTexts["resources.pairingSummary"].label.contains("刷新视频不会改变观看计划"))

        app.buttons["resources.refresh"].tap()
        let nextStep = app.buttons["resources.openSchedule"]
        reveal(nextStep, in: app)
        attachScreen("resource-import-instructions")
        nextStep.tap()
        XCTAssertTrue(app.buttons["schedule.editor.save"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["schedule.editor.save"].isEnabled, "Opening the plan from resources must not alter it")
        XCTAssertEqual(app.staticTexts["schedule.draft.status"].label, "与当前计划一致")
    }

    func testPlanDraftSurvivesTabChangesWhileViewingSettingsSaveImmediately() {
        let app = launchParentFixture()
        let nextDay = app.buttons["schedule.shift.next"]
        reveal(nextDay, in: app)
        nextDay.tap()
        let save = app.buttons["schedule.editor.save"]
        XCTAssertTrue(save.isEnabled)

        openDestination("settings.viewing", in: app)
        let autoSave = app.staticTexts["settings.autoSave"]
        XCTAssertTrue(autoSave.waitForExistence(timeout: 3))
        XCTAssertEqual(autoSave.label, "更改立即生效")
        let normal = app.buttons["settings.mode.normal"]
        normal.tap()
        XCTAssertEqual(normal.value as? String, "已选择")
        let stepper = app.steppers["settings.dailyGroupCount"]
        reveal(stepper, in: app)
        stepper.buttons["settings.dailyGroupCount-Decrement"].tap()
        XCTAssertEqual(stepper.value as? String, "2 组")

        openDestination("settings.resources", in: app)
        app.buttons["resources.refresh"].tap()
        openDestination("settings.schedule", in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled, "Resource refresh and switching destinations must preserve the draft")
        let status = app.staticTexts["schedule.draft.status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "有未保存的更改")
        let firstDay = app.buttons["schedule.calendar.day.2026-09-06"].firstMatch
        reveal(firstDay, in: app)
        XCTAssertTrue(firstDay.label.contains("当天第一组为编号 5"), "The draft must retain the one-day postponement")

        app.buttons["schedule.editor.close"].tap()
        let discard = app.buttons["放弃更改并关闭"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.staticTexts["观看计划尚未保存。其他观看设置的更改已生效。"].exists)
        discard.tap()
        XCTAssertTrue(app.buttons["today.play.5.chinese"].waitForExistence(timeout: 3), "Discarding the plan must keep today's original schedule and the selected normal mode")
        reveal(app.buttons["today.play.20.english"], in: app)
        XCTAssertFalse(app.buttons["today.play.100.chinese"].exists, "The immediately saved daily count must not be discarded with the plan")
        attachScreen("discard-plan-keeps-viewing-settings")
    }

    func testPreviewPreservesTodayProgressWhenOnlyFutureOrderChanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-strict-playback"]
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "strict-playback", withExtension: "mp4"))
        app.launchEnvironment["UI_TEST_VIDEO_BASE64"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
        let entry = app.buttons["today.strict.play"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let pause = app.buttons["strict.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        let progressed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let position = Int(app.staticTexts["strict.position"].label.filter(\.isNumber)) ?? 0
                return position >= 1
            }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 3), .completed)
        if !pause.exists { app.otherElements["strict.surface"].firstMatch.tap() }
        pause.tap()
        app.buttons["strict.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        let previousSummary = element("today.strict.resumeSummary", in: app).label

        app.buttons["ui-test.parent"].tap()
        openDestination("settings.schedule", in: app)
        let sourceRow = app.cells.containing(.any, identifier: "schedule.order.pair.100").firstMatch
        let targetRow = app.cells.containing(.any, identifier: "schedule.order.pair.20").firstMatch
        reveal(sourceRow, in: app)
        XCTAssertTrue(targetRow.isHittable)
        let handles = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "重新排序", "Reorder")
        let sourceHandle = sourceRow.buttons.matching(handles).firstMatch
        let targetHandle = targetRow.buttons.matching(handles).firstMatch
        XCTAssertTrue(sourceHandle.isHittable)
        XCTAssertTrue(targetHandle.isHittable)
        sourceHandle.press(forDuration: 0.5, thenDragTo: targetHandle)

        let futureDay = app.buttons["schedule.calendar.day.2026-09-06"].firstMatch
        reveal(futureDay, in: app)
        XCTAssertTrue(futureDay.label.contains("当天第一组为编号 100"), "The drag must actually reorder tomorrow before checking the preview")
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-05"].firstMatch.label.contains("当天第一组为编号 5"))
        app.buttons["schedule.editor.save"].tap()
        let impact = app.staticTexts["schedule.preview.todayImpact"]
        XCTAssertTrue(impact.waitForExistence(timeout: 3))
        XCTAssertEqual(impact.label, "今天的观看内容不变")
        XCTAssertTrue(app.staticTexts["已记录的今日播放进度会保留。"].exists)
        XCTAssertFalse(app.staticTexts["保存后，严格模式的今日进度会重置，从第一个视频重新开始。"].exists)
        attachScreen("future-only-plan-preview-preserves-progress")
        app.buttons["确认保存"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertEqual(entry.label, "继续观看")
        XCTAssertEqual(element("today.strict.resumeSummary", in: app).label, previousSummary)
        app.terminate()
        app.launchArguments.append("--ui-test-preserve")
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "继续观看")
        XCTAssertEqual(element("today.strict.resumeSummary", in: app).label, previousSummary)
    }

    private func launchParentFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-schedule-editor", "--ui-test-viewing-settings"]
        app.launch()
        XCTAssertTrue(app.buttons["schedule.editor.close"].waitForExistence(timeout: 5))
        return app
    }

    private func openDestination(_ identifier: String, in app: XCUIApplication) {
        let destination = app.cells.containing(.any, identifier: identifier).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.isHittable)
        destination.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = false) {
        let window = app.windows.firstMatch
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            let isAbove = element.exists && element.frame.height > 0
                && element.frame.maxY < window.frame.minY + window.frame.height * 0.25
            let startY = (scrollingUp || isAbove) ? 0.35 : 0.80
            let endY = (scrollingUp || isAbove) ? 0.80 : 0.35
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: startY))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: endY)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "The control must be reachable: \(element.identifier)")
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
