import XCTest

@MainActor final class HomeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testDateStripStaysInPlaceAndSummaryOpensTrend() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch()
        let month = app.staticTexts["records.date"]
        XCTAssertTrue(month.waitForExistence(timeout: 10))
        let today = month.value as! String
        XCTAssertNotNil(month.label.range(of: #"^\d{4}年\d{1,2}月\d{1,2}日，周[一二三四五六日]$"#, options: .regularExpression))
        XCTAssertFalse(app.navigationBars["薄记"].exists)
        let strip = app.scrollViews["home.dates"]
        let dates = strip.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.date."))
        XCTAssertEqual(dates.count, 31)
        let selected = app.buttons["home.date." + today]
        XCTAssertTrue(selected.isSelected); XCTAssertTrue(selected.isHittable)
        XCTAssertEqual(selected.frame.midX, strip.frame.midX, accuracy: 2)
        XCTAssertEqual(selected.frame.width, selected.frame.height, accuracy: 1)
        // SwiftUI exposes the single-label circle as one accessible button.
        XCTAssertTrue(selected.label.hasPrefix(today))
        XCTAssertFalse(strip.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "周")).firstMatch.exists)
        let centerX = selected.frame.midX
        let yesterday = dates.element(boundBy: 14)
        let previousDate = String(yesterday.identifier.dropFirst("home.date.".count))
        yesterday.tap()
        XCTAssertEqual(month.value as? String, previousDate)
        XCTAssertEqual(selected.frame.midX, centerX, accuracy: 2)
        XCTAssertTrue(yesterday.isSelected)
        XCTAssertEqual(app.staticTexts["home.intake"].label, "—")
        selected.tap()
        attach(app, name: "home-date-strip-empty")
        app.buttons["home.energy"].tap()
        XCTAssertTrue(app.buttons["7 天"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["趋势"].isSelected)
        app.tabBars.buttons["记录"].tap()
        XCTAssertEqual(month.value as? String, today)
        XCTAssertEqual(dates.count, 31)
        app.terminate(); app.launch()
        XCTAssertEqual(month.value as? String, today)
    }
    func testWorkoutSaveOrDiscardHasNoRecoveryOrConflict() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch()
        let date = app.staticTexts["records.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        let today = date.value as! String
        app.buttons["workout.new"].tap()
        let name = app.textFields["workout.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("上肢训练")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["workout.close"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row."))
        XCTAssertEqual(rows.count, 0)
        XCTAssertEqual(app.staticTexts["home.burn"].label, "—")
        let dates = app.scrollViews["home.dates"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.date."))
        dates.element(boundBy: 14).tap(); app.buttons["home.date." + today].tap()
        app.terminate(); app.launch(); app.buttons["workout.new"].tap()
        XCTAssertEqual(name.value as? String, "训练名称（可选）")
        XCTAssertFalse(app.buttons["返回未保存的输入"].exists)
        name.tap(); name.typeText("上肢训练")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        enterBodyweightSetAndSave(app)
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(row.label.contains("进行中")); XCTAssertFalse(row.label.contains("编辑中"))
        attach(app, name: "home-saved-workout-row")
        row.tap(); name.tap(); name.typeText("修改")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["workout.close"].tap()
        XCTAssertEqual(rows.count, 1); XCTAssertFalse(row.label.contains("编辑中"))
        row.tap(); XCTAssertEqual(name.value as? String, "上肢训练")
        name.tap(); name.typeText("修改")
        reveal(app.buttons["workout.save"], in: app); app.buttons["workout.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 1)
        app.terminate(); app.launch(); row.tap()
        XCTAssertEqual(name.value as? String, "上肢训练修改")
        app.buttons["workout.close"].tap(); app.buttons["workout.new"].tap()
        name.tap(); name.typeText("未保存即重启")
        app.terminate(); app.launch(); app.buttons["workout.new"].tap()
        XCTAssertEqual(name.value as? String, "训练名称（可选）")
        XCTAssertEqual(app.buttons["workout.close"].label, "放弃")
        attach(app, name: "workout-save-or-discard")
        app.buttons["workout.close"].tap(); row.tap()
        XCTAssertEqual(name.value as? String, "上肢训练修改")
    }
    func testLargestTextExpandsRecordRow() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch()
        XCTAssertTrue(app.buttons["workout.new"].waitForExistence(timeout: 10))
        app.buttons["workout.new"].tap()
        let name = app.textFields["workout.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("核心训练")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        enterBodyweightSetAndSave(app)
        attach(app, name: "home-regular-text-row")
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["records.date"].waitForExistence(timeout: 10))
        let today = app.staticTexts["records.date"].value as! String
        let date = app.buttons["home.date." + today]
        XCTAssertGreaterThanOrEqual(date.frame.width, 44)
        XCTAssertGreaterThanOrEqual(date.frame.height, 44)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        // At the largest size the fixed actions cover the screen's default swipe origin.
        // Drag inside the visible content, above those actions.
        for _ in 0..<12 {
            if row.exists && row.isHittable && row.frame.maxY < app.buttons["meal.new"].frame.minY - 12 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.48))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.20)))
        }
        XCTAssertTrue(row.isHittable)
        XCTAssertGreaterThan(row.frame.height, 76)
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        XCTAssertLessThan(row.frame.maxY, app.buttons["meal.new"].frame.minY)
        XCTAssertTrue(row.label.contains("核心训练"))
        attach(app, name: "home-largest-text-row")
        row.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
    }
    func testMinimalEditorsSaveAndDiscard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch(); app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["更多信息"].exists); XCTAssertFalse(app.staticTexts["meal.draftStatus"].exists)
        note.tap(); note.typeText("米饭和鸡肉")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["午餐"].tap()
        app.buttons["meal.calories"].tap()
        let kcal = app.textFields["manual.calories"]
        XCTAssertTrue(kcal.waitForExistence(timeout: 5)); kcal.tap(); kcal.typeText("350")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        XCTAssertTrue(app.buttons["meal.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("350"))
        attach(app, name: "minimal-new-meal")
        app.buttons["meal.save"].tap()
        let meal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); meal.tap()
        XCTAssertEqual(note.value as? String, "米饭和鸡肉")
        attach(app, name: "minimal-edit-meal")
        note.tap(); note.typeText("不保存")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["meal.close"].tap()
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); meal.tap()
        XCTAssertEqual(note.value as? String, "米饭和鸡肉")
        app.buttons["meal.close"].tap()
        app.buttons["workout.new"].tap()
        let name = app.textFields["workout.name"]
        name.tap(); name.typeText("上肢训练")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["workout.addExercise"].tap(); app.buttons["俯卧撑"].tap()
        let reps = app.textFields["第 1 组次数"]
        XCTAssertTrue(reps.waitForExistence(timeout: 5)); reps.tap(); reps.typeText("8")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        XCTAssertFalse(app.buttons["更多操作"].exists)
        attach(app, name: "minimal-new-workout")
        app.buttons["workout.save"].tap()
        let workout = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: 5)); workout.tap()
        attach(app, name: "minimal-edit-workout")
        XCTAssertEqual(reps.value as? String, "8")
        reps.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        reps.typeText(XCUIKeyboardKey.delete.rawValue + "9")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["workout.save"].tap(); workout.tap()
        XCTAssertEqual(reps.value as? String, "9")
    }

    func testMinimalEditorsLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal.save"].isHittable)
        XCTAssertGreaterThanOrEqual(note.frame.minX, 0)
        XCTAssertLessThanOrEqual(note.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(app.buttons["meal.save"].frame.minX, 0)
        XCTAssertLessThanOrEqual(app.buttons["meal.save"].frame.maxX, app.frame.maxX)
        attach(app, name: "minimal-meal-largest")
        let calories = app.buttons["meal.calories"]
        reveal(calories, in: app)
        XCTAssertGreaterThanOrEqual(calories.frame.minX, 0)
        XCTAssertLessThanOrEqual(calories.frame.maxX, app.frame.maxX)
        attach(app, name: "minimal-meal-metadata-largest")
        for _ in 0..<8 { if note.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(note.isHittable); note.tap(); note.typeText("米饭与鸡蛋，大字号饮食详情")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["meal.save"].tap()
        let meal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(app.buttons["meal.new"].waitForExistence(timeout: 5))
        reveal(meal, in: app); meal.tap()
        let actions = ["meal.save", "meal.delete", "meal.close"].map { app.buttons[$0] }
        for button in actions {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.minX, 0)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
            XCTAssertEqual(button.frame.minY, actions[0].frame.minY, accuracy: 1)
            XCTAssertEqual(button.frame.width, actions[0].frame.width, accuracy: 1)
        }
        attach(app, name: "direct-meal-editor-largest")
        app.buttons["meal.close"].tap(); app.buttons["workout.new"].tap()
        reveal(app.buttons["workout.addExercise"], in: app); app.buttons["workout.addExercise"].tap(); app.buttons["俯卧撑"].tap()
        let reps = app.textFields["第 1 组次数"]
        reveal(reps, in: app)
        for _ in 0..<8 {
            if reps.frame.maxY < app.buttons["workout.save"].frame.minY { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.20)))
        }
        XCTAssertLessThanOrEqual(reps.frame.maxX, app.frame.maxX)
        XCTAssertLessThan(reps.frame.maxY, app.buttons["workout.save"].frame.minY)
        XCTAssertTrue(app.buttons["workout.save"].isHittable)
        attach(app, name: "minimal-workout-largest")
        let energy = app.staticTexts["workout.energy.preview"]
        reveal(energy, in: app)
        XCTAssertGreaterThanOrEqual(energy.frame.minX, 0)
        XCTAssertLessThanOrEqual(energy.frame.maxX, app.frame.maxX)
        attach(app, name: "minimal-workout-metadata-largest")
    }

    private func enterBodyweightSetAndSave(_ app: XCUIApplication) {
        reveal(app.buttons["workout.addExercise"], in: app); app.buttons["workout.addExercise"].tap(); app.buttons["俯卧撑"].tap()
        let reps = app.textFields["第 1 组次数"]
        reveal(reps, in: app); reps.tap(); reps.typeText("8")
        XCTAssertFalse(app.buttons["确认这组完成"].exists)
        reveal(app.buttons["workout.save"], in: app)
        XCTAssertEqual(app.buttons["workout.save"].label, "保存")
        app.buttons["workout.save"].tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<10 {
            if element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.20)))
        }
        XCTAssertTrue(element.isHittable)
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
