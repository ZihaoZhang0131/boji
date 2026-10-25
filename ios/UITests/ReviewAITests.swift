import XCTest

@MainActor final class ReviewAITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testReviewEmptyCalendarAndTrend() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["回顾"].tap()
        XCTAssertFalse(app.buttons["review.previous"].isEnabled); XCTAssertFalse(app.buttons["review.next"].isEnabled)
        XCTAssertFalse(app.staticTexts["review.selectedDay"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.day.")).firstMatch.exists)
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.cell.meal."))
        XCTAssertGreaterThanOrEqual(cells.count, 85)
        XCTAssertGreaterThanOrEqual(app.buttons["趋势"].frame.height, 44)
        app.buttons["趋势"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons["7 天"].frame.height, 44)
        XCTAssertTrue(app.staticTexts["review.empty.intake"].exists); XCTAssertTrue(app.staticTexts["review.empty.training"].exists)
        app.buttons["30 天"].tap()
        XCTAssertFalse(app.buttons["review.previous"].isEnabled); XCTAssertFalse(app.buttons["review.next"].isEnabled)
    }
    func testReviewSavedRecordsAndRestart() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]; app.launch()
        let today = app.staticTexts["records.date"].value as! String
        saveMeal(app, kcal: "350")
        app.buttons["workout.new"].tap(); app.buttons["workout.addExercise"].tap(); app.buttons["俯卧撑"].tap()
        let reps = app.textFields["第 1 组次数"]; reps.tap(); reps.typeText("8")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["workout.save"].tap()
        app.tabBars.buttons["回顾"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["review.cell.meal." + today].firstMatch.label.contains("已记录"))
        XCTAssertTrue(app.descendants(matching: .any)["review.cell.workout." + today].firstMatch.label.contains("已记录"))
        XCTAssertFalse(app.staticTexts["day.intake"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch.exists)
        attach(app, name: "review-dual-calendar")
        app.buttons["趋势"].tap()
        let value = app.descendants(matching: .any)["review.value.intake." + today].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertTrue(value.label.contains("350 kcal"))
        app.buttons["30 天"].tap(); XCTAssertTrue(value.label.contains("350 kcal"))
        attach(app, name: "review-dual-trend")
        app.tabBars.buttons["记录"].tap(); XCTAssertEqual(app.staticTexts["records.date"].value as? String, today)
        app.terminate(); app.launch(); app.buttons["home.energy"].tap()
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertTrue(value.label.contains("350 kcal"))
    }
    func testReviewLargestText() {
        let app = XCUIApplication(), storeID = UUID().uuidString
        app.launchArguments = ["--ui-test-store", storeID, "--ui-test-offline"]; app.launch(); saveMeal(app, kcal: "1850")
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); app.tabBars.buttons["回顾"].tap()
        let cell = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.cell.meal.")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(cell.frame.minX, 0); XCTAssertLessThanOrEqual(cell.frame.maxX, app.frame.maxX)
        let previous = app.buttons["review.previous"]
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44); XCTAssertLessThanOrEqual(app.buttons["review.next"].frame.maxX, app.frame.maxX)
        attach(app, name: "review-dual-calendar-largest")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "回顾方式")).firstMatch.tap(); app.buttons["趋势"].tap()
        let chart = app.descendants(matching: .any)["review.chart.intake"].firstMatch
        reveal(chart, in: app); XCTAssertLessThanOrEqual(chart.frame.maxX, app.frame.maxX)
        attach(app, name: "review-dual-trend-largest")
    }
    private func saveMeal(_ app: XCUIApplication, kcal value: String) {
        app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        note.tap(); note.typeText("回顾测试餐")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["午餐"].tap(); app.buttons["meal.calories"].tap()
        let kcal = app.textFields["manual.calories"]
        XCTAssertTrue(kcal.waitForExistence(timeout: 5)); kcal.tap(); kcal.typeText(value)
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap(); app.buttons["meal.save"].tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 {
            if element.isHittable && element.frame.maxY < app.tabBars.firstMatch.frame.minY { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25)))
        }
        XCTAssertTrue(element.isHittable)
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testUnconfiguredAIAndAutomaticToggleDoNotAuthorizeSending() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]; app.launch()
        showMineRoot(in: app); app.buttons["ai.settings"].tap()
        XCTAssertTrue(app.textFields["ai.url"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["ai.url"].value as? String, "HTTPS 服务地址")
        let automatic = app.switches["保存带照片餐食后自动估算"]
        for _ in 0..<5 { if automatic.isHittable && automatic.frame.maxY < app.tabBars.firstMatch.frame.minY { break }; app.swipeUp() }
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: automatic)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["ai.authorized"].exists)
        app.terminate(); app.launch(); showMineRoot(in: app); app.buttons["ai.settings"].tap()
        for _ in 0..<5 { if automatic.isHittable && automatic.frame.maxY < app.tabBars.firstMatch.frame.minY { break }; app.swipeUp() }
        XCTAssertEqual(automatic.value as? String, "1"); XCTAssertFalse(app.staticTexts["ai.authorized"].exists)
    }
}
