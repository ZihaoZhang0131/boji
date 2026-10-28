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
        showMineRoot(in: app); app.buttons["ai.settings"].tap()
        XCTAssertTrue(app.staticTexts["千问识别 · 个人直连"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["ai.token"].exists)
        XCTAssertFalse(app.textFields["ai.url"].exists)
        XCTAssertTrue(app.staticTexts["未配置千问，照片和备注保存在本机，热量可人工填写。"].exists)
    }

    func testEmptyNavigationAndHistorySelection() {
        let app = isolatedApp()
        app.launch()
        let month = app.staticTexts["records.date"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        let currentDate = month.value as! String
        let dates = app.scrollViews["home.dates"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.date."))
        dates.element(boundBy: 14).tap()
        XCTAssertNotEqual(month.value as? String, currentDate)
        app.terminate(); app.launch()
        XCTAssertEqual(month.value as? String, currentDate)
        dates.element(boundBy: 14).tap()
        app.buttons["home.date." + currentDate].tap()
        XCTAssertEqual(month.value as? String, currentDate)
        app.tabBars.buttons["回顾"].tap()
        XCTAssertFalse(app.buttons["review.previous"].isEnabled)
        showMineRoot(in: app)
        XCTAssertEqual(app.buttons["profile.link"].value as? String, "待填写")
        XCTAssertFalse(app.buttons["goal.link"].exists)
    }

    func testMealDiscardRestartManualEditAndTrash() {
        let app = isolatedApp(); app.launch()
        app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        if !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("Afternoon latte")
        app.buttons["meal.close"].tap()
        app.terminate(); app.launch()
        app.buttons["meal.new"].tap()
        // SwiftUI may expose an empty value or the placeholder for an empty field.
        XCTAssertTrue(["", "吃了什么？"].contains(note.value as? String ?? "unavailable"))
        note.tap(); note.typeText("Afternoon latte")
        reveal(app.buttons["meal.save"], in: app)
        app.buttons["meal.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        reveal(app.buttons["meal.calories"], in: app); app.buttons["meal.calories"].tap()
        let calories = app.textFields["manual.calories"]
        calories.tap(); calories.typeText("200")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        app.buttons["meal.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("200 kcal"))
        if !note.isHittable { app.swipeUp() }
        note.tap(); note.typeText(" changed")
        app.buttons["meal.close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertEqual(note.value as? String, "Afternoon latte")
        note.tap(); note.typeText(" delete without saving")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        reveal(app.buttons["meal.delete"], in: app); app.buttons["meal.delete"].tap(); app.buttons["确认删除"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["records.empty"].firstMatch.waitForExistence(timeout: 5))
        showDataManagement(in: app)
        XCTAssertTrue(app.buttons["trash.link"].label.contains("1 项"))
        app.buttons["trash.link"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons["恢复"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["永久删除"].frame.height, 44)
        attach(app, named: "mine-trash-record")
        app.buttons["永久删除"].tap()
        XCTAssertTrue(app.alerts["永久删除这条记录？"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).count, 1)
        app.terminate(); app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("200 kcal"))
        app.buttons["meal.close"].tap()
        app.buttons["home.energy"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "review.value.intake.", "200 kcal")).firstMatch.exists)
        XCTAssertFalse(app.buttons["day.confirm"].exists)
        app.buttons["review.range"].tap(); app.buttons["review.range.apply"].tap()
        app.buttons["日历"].tap()
        XCTAssertFalse(app.staticTexts["day.intake"].exists)
        app.tabBars.buttons["记录"].tap()
        let savedMeal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        reveal(savedMeal, in: app); savedMeal.tap()
        XCTAssertEqual(note.value as? String, "Afternoon latte")
    }

    func testDemoCardsAndGroupedNavigation() {
        let app = isolatedApp()
        app.launchArguments += ["--ui-test-offline", "--ui-test-demo-controls"]
        app.launch()
        showMineRoot(in: app)
        reveal(app.buttons["demo.toggle"], in: app); app.buttons["demo.toggle"].tap()
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.staticTexts["demo.banner"].waitForExistence(timeout: 5))

        let meal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); meal.tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue((note.value as? String)?.hasPrefix("演示：") == true)
        app.buttons["meal.close"].tap()

        // The built-in demo starts with one meal; add a fictional workout to its memory-only space.
        app.buttons["workout.new"].tap()
        XCTAssertFalse(app.textFields["workout.name"].exists)
        app.buttons["俯卧撑"].tap()
        let reps = app.textFields["第 1 组次数"]
        reveal(reps, in: app); reps.tap(); reps.typeText("8")
        reveal(app.buttons["workout.save"], in: app); app.buttons["workout.save"].tap()
        let workout = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: 5)); workout.tap()
        XCTAssertTrue(app.textFields["第 1 组次数"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["第 1 组次数"].value as? String, "8")
        attach(app, named: "demo-workout-direct-editor")
        app.buttons["workout.close"].tap()
        attach(app, named: "demo-journal-cards")

        app.tabBars.buttons["回顾"].tap()
        XCTAssertTrue(app.navigationBars["回顾"].waitForExistence(timeout: 5))
        attach(app, named: "demo-review")
        showMineRoot(in: app)
        XCTAssertTrue(app.buttons["profile.link"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["goal.link"].exists)
        XCTAssertTrue(app.buttons["ai.settings"].exists)
        showDataManagement(in: app)
        XCTAssertTrue(app.buttons["import.link"].exists)
        XCTAssertTrue(app.buttons["backup.link"].exists)
        XCTAssertFalse(app.buttons["backup.link"].isEnabled)
        XCTAssertTrue(app.buttons["trash.link"].exists)
        XCTAssertFalse(app.buttons["export.link"].isEnabled)
        attach(app, named: "demo-data-management")
        showMineRoot(in: app)

        reveal(app.buttons["demo.toggle"], in: app); app.buttons["demo.toggle"].tap()
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["records.empty"].firstMatch.waitForExistence(timeout: 5))
    }

    func testMineMVPAndDataManagementNavigation() {
        let app = isolatedApp()
        app.launchArguments.append("--ui-test-offline")
        app.launch()
        showMineRoot(in: app)
        let functions = ["profile.link", "ai.settings", "data.management"].map { app.buttons[$0] }
        for function in functions {
            XCTAssertTrue(function.waitForExistence(timeout: 5))
            XCTAssertTrue(function.isHittable)
            XCTAssertGreaterThanOrEqual(function.frame.width, 44)
            XCTAssertGreaterThanOrEqual(function.frame.height, 44)
        }
        for id in ["goal.link", "backup.link", "demo.toggle", "export.link", "import.link"] {
            XCTAssertFalse(app.buttons[id].exists)
        }
        attach(app, named: "mine-minimal-mvp")
        app.buttons["profile.link"].tap()
        XCTAssertTrue(app.buttons["profile.sex"].waitForExistence(timeout: 5))
        showMineRoot(in: app)
        app.buttons["ai.settings"].tap()
        XCTAssertTrue(app.secureTextFields["ai.token"].waitForExistence(timeout: 5))
        showDataManagement(in: app)
        app.buttons["export.link"].tap()
        XCTAssertTrue(app.buttons["export.prepare"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["复制复盘提示词"].exists)
        showDataManagement(in: app)
        app.buttons["import.link"].tap()
        XCTAssertTrue(app.navigationBars["导入与恢复"].waitForExistence(timeout: 5))
        showDataManagement(in: app)
        app.buttons["trash.link"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["回顾"].tap()
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.cell.meal."))
        XCTAssertGreaterThanOrEqual(cells.count, 85)
        XCTAssertFalse(app.staticTexts["review.selectedDay"].exists)
        XCTAssertFalse(app.buttons["review.next"].isEnabled)
        attach(app, named: "review-monochrome-month")
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}

extension XCTestCase {
    @MainActor func showDataManagement(in app: XCUIApplication) {
        showMineRoot(in: app)
        app.buttons["data.management"].tap()
    }

    @MainActor func showMineRoot(in app: XCUIApplication) {
        app.tabBars.buttons["我的"].tap()
        let root = app.buttons["profile.link"]
        for _ in 0..<4 {
            if root.exists && root.isHittable { return }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists && back.isHittable else {
                XCTFail("无法从当前子页返回「我的」首页")
                return
            }
            back.tap()
        }
        XCTAssertTrue(root.isHittable)
    }

}
