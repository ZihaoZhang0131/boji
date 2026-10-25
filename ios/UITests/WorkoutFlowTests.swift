import XCTest

@MainActor final class WorkoutFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testWorkoutSavesRestartsEditsCopiesAndRestores() {
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
        reveal(app.buttons["workout.addExercise"], in: app); app.buttons["workout.addExercise"].tap(); app.buttons["引体向上"].tap()
        let reps = app.textFields["第 1 组次数"]; reveal(reps, in: app); reps.tap(); reps.typeText("8")
        let minutes = app.textFields["实际时长（分钟，可留空）"]
        reveal(minutes, in: app); minutes.tap(); minutes.typeText("30")
        reveal(app.buttons["workout.save"], in: app); app.buttons["workout.save"].tap()
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.textFields["workout.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["workout.name"].value as? String, "Pull day")
        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "workout-card-direct-editor"; editorScreenshot.lifetime = .keepAlways; add(editorScreenshot)
        let firstEnergy = app.staticTexts["workout.energy.preview"]
        reveal(firstEnergy, in: app)
        let originalKcal = firstEnergy.label
        XCTAssertTrue(originalKcal.hasSuffix(" kcal"))
        app.buttons["workout.close"].tap()
        app.tabBars.buttons["我的"].tap(); app.buttons["profile.link"].tap()
        let weight = app.textFields["profile.field.体重（kg）"]
        reveal(weight, in: app); weight.tap(); weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "80")
        reveal(app.buttons["profile.save"], in: app); app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["profile.link"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap(); row.tap()
        reveal(firstEnergy, in: app)
        XCTAssertEqual(firstEnergy.label, originalKcal)
        let name = app.textFields["workout.name"]
        revealAbove(name, in: app); name.tap(); name.typeText(" revised")
        reveal(app.buttons["workout.save"], in: app); app.buttons["workout.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).count, 1)
        row.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Pull day revised")
        name.tap(); name.typeText(" pending")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["workout.details"].tap()
        reveal(app.buttons["复制为本次训练"], in: app); app.buttons["复制为本次训练"].tap()
        let copiedName = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Pull day revised"), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [copiedName], timeout: 5), .completed)
        XCTAssertEqual(name.value as? String, "Pull day revised")
        XCTAssertFalse(app.buttons["确认这组完成"].exists)
        app.buttons["workout.close"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        app.buttons["workout.details"].tap()
        reveal(app.buttons["移到回收站"], in: app); app.buttons["移到回收站"].tap(); app.buttons["确认删除"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["workout.new"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        showDataManagement(in: app)
        XCTAssertTrue(app.buttons["trash.link"].waitForExistence(timeout: 5))
        app.buttons["trash.link"].tap(); app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.tabBars.buttons["记录"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).count, 1)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func revealAbove(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeDown() }
        XCTAssertTrue(element.isHittable)
    }
}
