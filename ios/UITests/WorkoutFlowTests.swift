import XCTest

@MainActor final class WorkoutFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testWorkoutSavesRestartsEditsCopiesAndRestores() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        app.buttons["workout.new"].tap()
        XCTAssertTrue(app.buttons["杠铃卧推"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["workout.name"].exists)
        XCTAssertFalse(app.textFields["实际时长（分钟，可留空）"].exists)
        XCTAssertFalse(app.navigationBars.buttons["放弃"].exists)
        app.buttons["杠铃卧推"].tap()
        let weight = app.textFields["第 1 组负重（kg）"], reps = app.textFields["第 1 组次数"]
        weight.tap(); weight.typeText("60"); reps.tap(); reps.typeText("10")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["杠铃卧推增加一组"].tap(); app.buttons["杠铃卧推增加一组"].tap()
        XCTAssertEqual(app.textFields["第 3 组次数"].value as? String, "10")
        app.buttons["杠铃卧推减少一组"].tap()
        XCTAssertFalse(app.textFields["第 3 组次数"].exists)
        attach(app, name: "workout-simple-cards")
        reveal(app.buttons["workout.addExercise"], in: app); app.buttons["workout.addExercise"].tap()
        reveal(app.buttons["俯卧撑"], in: app); app.buttons["俯卧撑"].tap()
        XCTAssertEqual(app.navigationBars["记训练"].exists, true)
        let bodyReps = app.textFields.matching(identifier: "第 1 组次数").element(boundBy: 1)
        reveal(bodyReps, in: app); bodyReps.tap(); bodyReps.typeText("8")
        app.buttons["workout.save"].tap()
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertEqual(weight.value as? String, "60")
        weight.tap(); weight.typeText("0"); app.buttons["workout.close"].tap(); row.tap()
        XCTAssertEqual(weight.value as? String, "60")
        let firstReps = app.textFields.matching(identifier: "第 1 组次数").firstMatch
        firstReps.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        firstReps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "12")
        app.buttons["workout.save"].tap(); row.tap()
        XCTAssertEqual(app.textFields.matching(identifier: "第 1 组次数").firstMatch.value as? String, "12")
        reveal(app.buttons["workout.details"], in: app); app.buttons["workout.details"].tap()
        reveal(app.buttons["复制为本次训练"], in: app); app.buttons["复制为本次训练"].tap()
        XCTAssertTrue(app.navigationBars["记训练"].waitForExistence(timeout: 5))
        app.buttons["workout.close"].tap(); row.tap()
        reveal(app.buttons["workout.details"], in: app); app.buttons["workout.details"].tap()
        reveal(app.buttons["移到回收站"], in: app); app.buttons["移到回收站"].tap(); app.buttons["确认删除"].tap()
        XCTAssertTrue(app.buttons["workout.new"].waitForExistence(timeout: 5))
        showDataManagement(in: app); app.buttons["trash.link"].tap(); app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
    func testWorkoutCardLayout() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        app.buttons["workout.new"].tap(); app.buttons["杠铃卧推"].tap()
        let weight = app.textFields["第 1 组负重（kg）"], reps = app.textFields["第 1 组次数"]
        weight.tap(); weight.typeText("60"); reps.tap(); reps.typeText("10")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["杠铃卧推增加一组"].tap()
        for label in ["杠铃卧推增加一组", "杠铃卧推减少一组", "删除杠铃卧推", "workout.save", "workout.close"] {
            XCTAssertGreaterThanOrEqual(app.buttons[label].frame.width, 44)
            XCTAssertGreaterThanOrEqual(app.buttons[label].frame.height, 44)
        }
        attach(app, name: "workout-simple-cards")
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 {
            if element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.3)))
        }
        XCTAssertTrue(element.isHittable)
    }
}
