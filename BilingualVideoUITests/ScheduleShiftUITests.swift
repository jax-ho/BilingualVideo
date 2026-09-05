import XCTest

@MainActor
final class ScheduleShiftUITests: XCTestCase {
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
        XCTAssertTrue(source.isHittable, "“编号 100”不可触摸")
        XCTAssertTrue(target.isHittable, "9 月 5 日的日历格不可触摸")

        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(source.value as? String, "已选择")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            waitForValue(of: datePicker, toEqual: "2026年9月3日"),
            "选择编号 100 并点 9 月 5 日后，开始日期没有整体前移到 9 月 3 日"
        )
        XCTAssertEqual(source.value as? String, "未选择")

        let result = app.staticTexts["schedule.shift.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 2))
        XCTAssertTrue(result.label.contains("其他视频组也前移 2 天"))
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
}
