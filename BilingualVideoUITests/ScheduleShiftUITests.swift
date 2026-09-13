import XCTest

@MainActor
final class ScheduleShiftUITests: XCTestCase {
    func testCalendarShowsAutomaticDelayAndManualShiftUsesActualDates() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-schedule-editor", "--ui-test-auto-delay"]
        app.launch()
        let day5 = app.buttons["schedule.calendar.day.2026-09-05"].firstMatch
        XCTAssertTrue(day5.waitForExistence(timeout: 5))
        XCTAssertTrue(day5.label.contains("编号 5"), "Played history keeps its date")
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-06"].firstMatch.label.contains("无计划"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-07"].firstMatch.label.contains("编号 20"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-08"].firstMatch.label.contains("编号 100"))
        app.buttons["schedule.shift.pair.20"].tap()
        app.buttons["schedule.calendar.day.2026-09-09"].firstMatch.tap()
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-07"].firstMatch.label.contains("编号 5"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-09"].firstMatch.label.contains("编号 20"))
        XCTAssertTrue(app.buttons["schedule.calendar.day.2026-09-10"].firstMatch.label.contains("编号 100"))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "automatic-delay-calendar"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testViewingSettingChangesHomeGroupsImmediately() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-schedule-editor", "--ui-test-viewing-settings", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let settings = app.staticTexts["观看设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let strictMode = app.buttons["settings.mode.strict"]
        let normalMode = app.buttons["settings.mode.normal"]
        XCTAssertTrue(strictMode.waitForExistence(timeout: 3))
        XCTAssertTrue(normalMode.exists)
        XCTAssertEqual(strictMode.value as? String, "已选择")
        XCTAssertEqual(normalMode.value as? String, "未选择")
        XCTAssertFalse(app.switches["settings.normalPlaybackLooping"].exists)
        normalMode.tap()
        XCTAssertEqual(normalMode.value as? String, "已选择")
        XCTAssertEqual(strictMode.value as? String, "未选择")
        let looping = app.switches["settings.normalPlaybackLooping"]
        XCTAssertTrue(looping.exists)
        XCTAssertEqual(looping.value as? String, "1")
        looping.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(looping.value as? String, "0")
        looping.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(looping.value as? String, "1")
        let stepper = app.steppers["settings.dailyGroupCount"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        XCTAssertEqual(stepper.value as? String, "3 组")
        stepper.buttons["settings.dailyGroupCount-Decrement"].tap()
        stepper.buttons["settings.dailyGroupCount-Decrement"].tap()
        XCTAssertEqual(stepper.value as? String, "1 组")
        stepper.buttons["settings.dailyGroupCount-Decrement"].tap()
        XCTAssertEqual(stepper.value as? String, "1 组")
        stepper.buttons["settings.dailyGroupCount-Increment"].tap()
        XCTAssertEqual(stepper.value as? String, "2 组")
        let settingsImage = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        settingsImage.name = "viewing-settings"
        settingsImage.lifetime = .keepAlways
        add(settingsImage)
        app.buttons["schedule.editor.close"].tap()
        XCTAssertTrue(app.buttons["today.play.5.chinese"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["today.play.5.english"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["today.play.20.chinese"].exists)
        XCTAssertTrue(app.buttons["today.play.20.english"].exists)
        app.swipeUp()
        XCTAssertFalse(app.buttons["today.play.100.chinese"].exists)
        XCTAssertFalse(app.buttons["today.play.100.english"].exists)
        let homeImage = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        homeImage.name = "daily-groups-home"
        homeImage.lifetime = .keepAlways
        add(homeImage)
    }

    func testScheduleEditorUsesOneCloseAndSaveFlow() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-schedule-editor")
        app.launch()

        XCTAssertTrue(
            app.buttons["schedule.editor.close"].waitForExistence(timeout: 5),
            "计划编辑页应直接提供“关闭”"
        )
        XCTAssertTrue(
            app.buttons["schedule.editor.save"].exists,
            "计划编辑页应直接提供“保存”"
        )
        XCTAssertFalse(app.buttons["完成"].exists, "不应再用“完成”重复表达关闭编辑页")
        XCTAssertFalse(app.buttons["编辑"].exists, "进入计划编辑页后不应再要求点一次“编辑”")

        let reorderHandle = app.buttons
            .matching(
                NSPredicate(
                    format: "label CONTAINS %@ OR label CONTAINS %@",
                    "重新排序",
                    "Reorder"
                )
            )
            .firstMatch
        XCTAssertTrue(
            reorderHandle.waitForExistence(timeout: 2),
            "进入计划编辑页后应立即显示拖动排序把手"
        )

        for _ in 0..<2 {
            app.swipeUp()
        }
        XCTAssertFalse(app.buttons["预览并保存计划"].exists)
        XCTAssertFalse(app.buttons["放弃未保存更改"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "schedule-editor-simplified-bottom"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testClosingUnchangedEditorExitsImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-schedule-editor")
        app.launch()

        let closeButton = app.buttons["schedule.editor.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        XCTAssertTrue(
            app.staticTexts["计划编辑已关闭"].waitForExistence(timeout: 2),
            "没有未保存更改时，“关闭”应直接退出"
        )
    }

    func testClosingChangedEditorOffersAChoiceToDiscardOrKeepEditing() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-schedule-editor")
        app.launch()

        let nextButton = app.buttons["schedule.shift.next"]
        scrollPlanEditorToTop(in: app, until: nextButton)
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        let closeButton = app.buttons["schedule.editor.close"]
        closeButton.tap()

        let keepEditingButton = app.buttons["继续编辑"]
        let discardButton = app.buttons["放弃更改并关闭"]
        XCTAssertTrue(keepEditingButton.waitForExistence(timeout: 2))
        XCTAssertTrue(discardButton.exists)

        keepEditingButton.tap()
        XCTAssertTrue(app.buttons["schedule.editor.save"].waitForExistence(timeout: 2))

        closeButton.tap()
        XCTAssertTrue(discardButton.waitForExistence(timeout: 2))
        discardButton.tap()
        XCTAssertTrue(app.staticTexts["计划编辑已关闭"].waitForExistence(timeout: 2))
    }

    func testSavingFromPreviewClosesEditor() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-schedule-editor")
        app.launch()

        let nextButton = app.buttons["schedule.shift.next"]
        scrollPlanEditorToTop(in: app, until: nextButton)
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()

        let saveButton = app.buttons["schedule.editor.save"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let confirmSaveButton = app.buttons["确认保存"]
        XCTAssertTrue(confirmSaveButton.waitForExistence(timeout: 2))
        confirmSaveButton.tap()

        XCTAssertTrue(
            app.staticTexts["计划编辑已关闭"].waitForExistence(timeout: 3),
            "确认保存后应自动关闭计划编辑页"
        )
    }

    func testSelectingPairAndCalendarDateMovesWholePlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-schedule-editor")
        app.launch()

        let datePicker = app.buttons
            .matching(NSPredicate(format: "label == %@", "日期选择器"))
            .firstMatch
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
        XCTAssertEqual(datePicker.value as? String, "2026年9月5日")

        let source = app.buttons["schedule.shift.pair.100"]
        guard source.waitForExistence(timeout: 2) else {
            XCTFail("缺少可点选的“编号 100”按钮")
            return
        }
        let target = app.buttons
            .matching(identifier: "schedule.calendar.day.2026-09-05")
            .firstMatch
        guard target.waitForExistence(timeout: 2) else {
            XCTFail("缺少可点选的 9 月 5 日日历格")
            return
        }
        scrollDetailToReveal(source, in: app)
        XCTAssertTrue(source.isHittable, "“编号 100”不可触摸")
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(source.value as? String, "已选择")

        // The group picker and month grid need not fit on the screen together.
        // Keep coordinate taps to verify the physical hit targets after scrolling.
        scrollDetailToReveal(target, in: app)
        XCTAssertTrue(target.isHittable, "9 月 5 日的日历格不可触摸")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(source.value as? String, "未选择")

        let result = app.staticTexts["schedule.shift.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 2))
        XCTAssertTrue(result.label.contains("其他视频组也前移 2 天"))

        let lastDay = app.buttons["schedule.calendar.day.2026-09-30"].firstMatch
        scrollDetailToReveal(lastDay, in: app)
        let firstDay = app.buttons["schedule.calendar.day.2026-09-01"].firstMatch
        XCTAssertTrue(firstDay.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(firstDay.frame))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(lastDay.frame))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "calendar-selection-whole-plan-shift"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Bring the start-date section back before resolving the first native
        // date picker; the calendar's jump-date control has the same system label.
        scrollDetailToReveal(app.buttons["schedule.shift.previous"], in: app, scrollingUp: true)
        XCTAssertTrue(
            waitForValue(of: datePicker, toEqual: "2026年9月3日"),
            "选择编号 100 并点 9 月 5 日后，开始日期没有整体前移到 9 月 3 日"
        )
    }

    func testVisibleDayShiftButtonsRespondToPhysicalTaps() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-schedule-editor")
        app.launch()

        let previousButton = app.buttons["schedule.shift.previous"]
        let nextButton = app.buttons["schedule.shift.next"]
        scrollPlanEditorToTop(in: app, until: previousButton)
        XCTAssertTrue(previousButton.waitForExistence(timeout: 5), "请先让 App 停留在计划编辑页面")
        XCTAssertTrue(nextButton.exists)

        let datePicker = app.buttons
            .matching(NSPredicate(format: "label == %@", "日期选择器"))
            .firstMatch
        XCTAssertTrue(datePicker.exists)

        let baseline = try XCTUnwrap(datePicker.value as? String)

        previousButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(of: datePicker, toDifferFrom: baseline), "点按“前移一天”后日期没有变化")

        let previousDate = try XCTUnwrap(datePicker.value as? String)
        nextButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(of: datePicker, toEqual: baseline), "点按“后移一天”未能恢复原日期")

        nextButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(of: datePicker, toDifferFrom: baseline), "点按“后移一天”后日期没有变化")

        previousButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(of: datePicker, toEqual: baseline), "点按“前移一天”未能恢复原日期；中间日期：\(previousDate)")
    }

    private func waitForValue(of element: XCUIElement, toDifferFrom value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", value),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    private func waitForValue(of element: XCUIElement, toEqual value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    private func scrollPlanEditorToTop(in app: XCUIApplication, until element: XCUIElement) {
        for _ in 0..<5 where !element.exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.28))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.82))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func scrollDetailToReveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = false) {
        let window = app.windows.firstMatch
        for _ in 0..<8 {
            let frame = window.frame
            let navigationBottom = app.navigationBars.allElementsBoundByIndex
                .map(\.frame).filter { $0.intersects(frame) }.map(\.maxY).max() ?? frame.minY
            let viewport = CGRect(x: frame.minX, y: navigationBottom, width: frame.width,
                                  height: max(0, frame.maxY - navigationBottom))
            if element.exists, element.isHittable, viewport.contains(element.frame) { return }
            let isAbove = element.exists && element.frame.height > 0 && element.frame.minY < viewport.minY
            let startY = scrollingUp || isAbove ? 0.35 : 0.80
            let endY = scrollingUp || isAbove ? 0.80 : 0.35
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: startY))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: endY)))
        }
        XCTFail("The control must be fully reachable in the right-hand detail column: \(element.identifier)")
    }
}
