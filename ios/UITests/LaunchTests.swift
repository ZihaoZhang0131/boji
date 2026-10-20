import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func isolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString]
        return app
    }
    func testAppLaunches() {
        let app = isolatedApp()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["records.empty"].firstMatch.waitForExistence(timeout: 10))
    }

    func testPersonalAISettingsUseDirectQwenWithoutServerAddress() {
        let app = isolatedApp(); app.launch()
        app.tabBars.buttons["我的"].tap()
        app.buttons["ai.settings"].tap()
        XCTAssertTrue(app.staticTexts["千问识别 · 个人直连"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["ai.token"].exists)
        XCTAssertFalse(app.textFields["ai.url"].exists)
        XCTAssertTrue(app.staticTexts["未配置千问，照片和备注保存在本机，热量可人工填写。"].exists)
    }

    func testEmptyNavigationAndHistorySelection() {
        let app = isolatedApp()
        app.launch()
        let currentDate = app.buttons["records.date"].value as? String
        XCTAssertNotNil(currentDate)
        app.buttons["前一天"].tap()
        XCTAssertNotEqual(app.buttons["records.date"].value as? String, currentDate)
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["records.date"].value as? String, currentDate)
        app.buttons["前一天"].tap()
        app.buttons["records.today"].tap()
        XCTAssertEqual(app.buttons["records.date"].value as? String, currentDate)
        app.tabBars.buttons["回顾"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["review.empty"].firstMatch.exists)
        app.tabBars.buttons["我的"].tap()
        XCTAssertEqual(app.buttons["profile.link"].value as? String, "待填写")
        XCTAssertEqual(app.buttons["goal.link"].value as? String, "未设置")
    }

    func testMealDraftRestartManualEditAndTrash() {
        let app = isolatedApp(); app.launch()
        app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        if !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("Afternoon latte")
        app.buttons["收起"].tap()
        app.terminate(); app.launch()
        app.buttons["meal.new"].tap()
        XCTAssertEqual(note.value as? String, "Afternoon latte")
        reveal(app.buttons["meal.save"], in: app)
        app.buttons["meal.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["meal.detail.note"].waitForExistence(timeout: 5))
        app.buttons["meal.manual"].tap()
        let calories = app.textFields["manual.calories"]
        calories.tap(); calories.typeText("200")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        XCTAssertTrue(app.staticTexts["meal.calories.total"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meal.calories.total"].firstMatch.label, "200 kcal")
        reveal(app.buttons["meal.edit"], in: app); app.buttons["meal.edit"].tap()
        if !note.isHittable { app.swipeUp() }
        note.tap(); note.typeText(" changed")
        reveal(app.buttons["放弃修改"], in: app); app.buttons["放弃修改"].tap(); app.buttons["确认放弃"].tap()
        for _ in 0..<5 { if app.staticTexts["meal.detail.note"].exists { break }; app.swipeDown() }
        XCTAssertEqual(app.staticTexts["meal.detail.note"].label, "Afternoon latte")
        reveal(app.buttons["移到回收站"], in: app); app.buttons["移到回收站"].tap(); app.buttons["确认删除"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["records.empty"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap(); app.buttons["回收站"].tap(); app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).count, 1)
        app.terminate(); app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertEqual(app.staticTexts["meal.calories.total"].firstMatch.label, "200 kcal")
        app.buttons["完成"].tap()
        app.buttons["当天汇总"].tap()
        reveal(app.staticTexts["day.intake"], in: app)
        XCTAssertEqual(app.staticTexts["day.intake"].label, "已记录摄入 200 kcal")
        reveal(app.buttons["day.confirm"], in: app); app.buttons["day.confirm"].tap(); app.buttons["确认已记全"].tap()
        app.tabBars.buttons["回顾"].tap()
        XCTAssertTrue(app.staticTexts["日均摄入：200 kcal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["仅使用 1 个完整统计日"].exists)
        app.buttons["30 天"].tap()
        XCTAssertTrue(app.staticTexts["仅使用 1 个完整统计日"].exists)
        app.buttons["饮食"].tap()
        app.textFields["review.search"].tap(); app.textFields["review.search"].typeText("latte")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Afternoon latte")).firstMatch.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
