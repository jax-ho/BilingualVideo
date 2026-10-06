import XCTest

@MainActor
final class PDFStudyUITests: XCTestCase {
    func testPDFSwipesResumeLastPageExplicitFinishAndNextBook() throws {
        continueAfterFailure = false
        let app = try launchFixture(extra: ["--ui-test-pdf-only"])
        let entry = app.buttons["today.study.start"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        waitForPage(1, in: app)
        XCTAssertFalse(app.buttons["pdf.finish"].exists)
        screenshot("pdf-portrait-first-page")
        app.buttons["pdf.page.0"].tap()
        XCTAssertTrue(app.staticTexts["正在朗读，再点一下可以重听"].waitForExistence(timeout: 45))
        app.buttons["pdf.page.0"].swipeLeft()
        waitForPage(2, in: app)
        XCTAssertFalse(app.buttons["pdf.finish"].exists)
        app.buttons["pdf.page.1"].swipeLeft()
        waitForPage(3, in: app)
        XCTAssertTrue(app.buttons["pdf.finish"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["pdf.finish"].isHittable)
        screenshot("pdf-landscape-final-page")
        app.buttons["pdf.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["today.study.finished"].exists)
        app.terminate()
        app.launchArguments.append("--ui-test-preserve")
        app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        waitForPage(3, in: app)
        XCTAssertTrue(app.buttons["pdf.finish"].isHittable)
        app.buttons["pdf.finish"].tap()
        waitForPage(1, in: app)
        XCTAssertTrue(app.staticTexts["RAZ · 编号 20"].exists)
        XCTAssertFalse(app.buttons["pdf.finish"].exists)
        app.buttons["pdf.page.0"].swipeLeft()
        waitForPage(2, in: app)
        app.buttons["pdf.page.1"].swipeLeft()
        waitForPage(3, in: app)
        app.buttons["pdf.finish"].tap()
        XCTAssertTrue(app.staticTexts["study.finished"].waitForExistence(timeout: 5))
        app.buttons["study.close"].tap()
        XCTAssertTrue(app.staticTexts["today.study.finished"].waitForExistence(timeout: 5))
        XCTAssertFalse(entry.exists)
        XCUIDevice.shared.orientation = .portrait
    }

    func testStrictVideoAutomaticallyHandsOffToPDF() throws {
        let app = try launchFixture(extra: ["--ui-test-video-first"])
        app.buttons["today.study.start"].tap()
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["pdf.pageNumber"].exists)
        waitForPage(1, in: app, timeout: 40)
        XCTAssertFalse(app.buttons["strict.pause"].exists)
        screenshot("video-handoff-to-pdf")
        app.buttons["pdf.close"].tap()
        XCTAssertTrue(app.buttons["today.study.start"].waitForExistence(timeout: 5))
        app.buttons["today.study.start"].tap()
        waitForPage(1, in: app)
        XCTAssertFalse(app.buttons["strict.pause"].exists)
        app.buttons["pdf.close"].tap()
    }

    func testNormalVideoAutomaticallyHandsOffToPDF() throws {
        let app = try launchFixture(extra: ["--ui-test-video-first", "--ui-test-normal-study"])
        app.buttons["today.study.start"].tap()
        waitForPage(1, in: app, timeout: 45)
        screenshot("normal-video-handoff-to-pdf")
        app.buttons["pdf.close"].tap()
    }

    func testPDFFirstAutomaticallyHandsOffToStrictVideo() throws {
        let app = try launchFixture(extra: [])
        app.buttons["today.study.start"].tap()
        for _ in 0..<2 {
            waitForPage(1, in: app)
            app.buttons["pdf.page.0"].swipeLeft()
            waitForPage(2, in: app)
            app.buttons["pdf.page.1"].swipeLeft()
            waitForPage(3, in: app)
            app.buttons["pdf.finish"].tap()
        }
        XCTAssertTrue(app.buttons["strict.pause"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["pdf.pageNumber"].exists)
        app.buttons["strict.close"].tap()
    }

    func testPDFPlanEditorAndDailySettingsUseSeparateDraft() throws {
        let app = try launchFixture(extra: ["--ui-test-pdf-only"])
        app.buttons["ui-test.parent"].tap()
        app.staticTexts["PDF 计划"].tap()
        let previous = app.buttons["schedule.shift.previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        previous.tap()
        app.buttons["schedule.editor.save"].tap()
        XCTAssertTrue(app.staticTexts["保存后，今日 PDF 进度会重置，从第一份重新开始。"].waitForExistence(timeout: 5))
        app.buttons["返回修改"].tap()
        app.staticTexts["学习设置"].tap()
        let count = app.steppers["settings.dailyPDFCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        for _ in 0..<5 where !count.isHittable { app.swipeUp() }
        count.buttons["settings.dailyPDFCount-Increment"].tap()
        XCTAssertTrue(count.label.contains("3 份 PDF"))
        app.buttons["schedule.editor.close"].tap()
        XCTAssertTrue(app.buttons["放弃更改并关闭"].waitForExistence(timeout: 5))
        app.buttons["放弃更改并关闭"].tap()
        XCTAssertTrue(app.buttons["today.study.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天共 0 组视频 · 3 份 PDF"].exists)
    }

    private func launchFixture(extra: [String]) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-pdf-study"] + extra
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "strict-playback", withExtension: "mp4"))
        app.launchEnvironment["UI_TEST_VIDEO_BASE64"] = try Data(contentsOf: url).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["today.study.start"].waitForExistence(timeout: 5))
        return app
    }

    private func waitForPage(_ number: Int, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let page = app.staticTexts["pdf.pageNumber"]
        let matches = NSPredicate { _, _ in page.exists && page.label == "第 \(number) / 3 页" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)], timeout: timeout), .completed)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
