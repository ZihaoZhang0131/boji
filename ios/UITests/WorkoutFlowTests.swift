import XCTest

@MainActor final class WorkoutFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testWorkoutRestartsFinishesEditsCopiesAndRestores() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["我的"].tap(); app.buttons["profile.link"].tap()
        app.buttons["profile.sex"].tap(); app.buttons["男性公式"].tap()
        for (label, value) in [("年龄（岁）", "28"), ("身高（cm）", "175"), ("体重（kg）", "70")] {
            let field = app.textFields["profile.field." + label]
            reveal(field, in: app); field.tap(); field.typeText(value)
            if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        }
        reveal(app.buttons["profile.activity"], in: app); app.buttons["profile.activity"].tap(); app.buttons["较少活动 · 1.2"].tap()
        reveal(app.buttons["profile.save"], in: app); app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["profile.link"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap()
        app.buttons["workout.new"].tap()
        app.textFields["workout.name"].tap(); app.textFields["workout.name"].typeText("Pull day")
        reveal(app.buttons["常用动作"], in: app); app.buttons["常用动作"].tap(); app.buttons["引体向上（自重）"].tap()
        let reps = app.textFields["第 1 组次数"]; reveal(reps, in: app); reps.tap(); reps.typeText("8")
        reveal(app.buttons["确认这组完成"], in: app); app.buttons["确认这组完成"].tap()
        app.buttons["收起"].tap(); app.terminate(); app.launch()
        app.buttons["workout.new"].tap()
        XCTAssertEqual(app.textFields["workout.name"].value as? String, "Pull day")
        let minutes = app.textFields["实际时长（分钟，可留空）"]
        reveal(minutes, in: app); minutes.tap(); minutes.typeText("30")
        reveal(app.buttons["workout.finish"], in: app); app.buttons["workout.finish"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let firstEnergy = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " kcal")).firstMatch
        XCTAssertTrue(firstEnergy.waitForExistence(timeout: 5))
        let originalKcal = firstEnergy.label
        app.buttons["完成"].tap()
        app.tabBars.buttons["我的"].tap(); app.buttons["profile.link"].tap()
        let weight = app.textFields["profile.field.体重（kg）"]
        reveal(weight, in: app); weight.tap(); weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "80")
        reveal(app.buttons["profile.save"], in: app); app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["profile.link"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap(); row.tap()
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " kcal")).firstMatch.label, originalKcal)
        reveal(app.buttons["编辑训练"], in: app); app.buttons["编辑训练"].tap()
        let name = app.textFields["workout.name"]; name.tap(); name.typeText(" revised")
        reveal(app.buttons["workout.finish"], in: app); app.buttons["workout.finish"].tap()
        XCTAssertTrue(app.staticTexts["Pull day revised"].waitForExistence(timeout: 5))
        reveal(app.buttons["复制为本次训练"], in: app); app.buttons["复制为本次训练"].tap()
        XCTAssertTrue(app.staticTexts["已确认 0 组 · 结束前均为草稿"].exists)
        reveal(app.buttons["放弃训练草稿"], in: app); app.buttons["放弃训练草稿"].tap(); app.buttons["确认放弃"].tap()
        reveal(app.buttons["移到回收站"], in: app); app.buttons["移到回收站"].tap(); app.buttons["确认删除"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["workout.new"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.92)).tap()
        XCTAssertTrue(app.buttons["回收站"].waitForExistence(timeout: 5))
        app.buttons["回收站"].tap(); app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).count, 1)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
