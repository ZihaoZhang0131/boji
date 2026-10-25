import XCTest

@MainActor final class OfflineIntegrationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEmptyStoreProfileMealWorkoutRestartAndReviewWithNetworkForcedOffline() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["records.empty"].firstMatch.waitForExistence(timeout: 10))

        showMineRoot(in: app); app.buttons["profile.link"].tap()
        app.buttons["profile.sex"].tap(); app.buttons["男性公式"].tap()
        for (label, value) in [("年龄（岁）", "28"), ("身高（cm）", "175"), ("体重（kg）", "70")] {
            let field = app.textFields["profile.field." + label]
            reveal(field, in: app); field.tap(); field.typeText(value)
            if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        }
        reveal(app.buttons["profile.activity"], in: app); app.buttons["profile.activity"].tap(); app.buttons["较少活动 · 1.2"].tap()
        reveal(app.buttons["profile.save"], in: app); app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["profile.link"].waitForExistence(timeout: 5))

        app.tabBars.buttons["记录"].tap(); app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        note.tap(); note.typeText("Offline integration meal")
        reveal(app.buttons["meal.save"], in: app); app.buttons["meal.save"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).count, 1)

        app.buttons["workout.new"].tap()
        let name = app.textFields["workout.name"]
        name.tap(); name.typeText("Offline integration workout")
        reveal(app.buttons["workout.addExercise"], in: app); app.buttons["workout.addExercise"].tap(); app.buttons["引体向上"].tap()
        let reps = app.textFields["第 1 组次数"]
        reveal(reps, in: app); reps.tap(); reps.typeText("8")
        reveal(app.buttons["workout.save"], in: app); app.buttons["workout.save"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).count, 1)

        app.terminate(); app.launch()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).count, 1)
        showMineRoot(in: app)
        XCTAssertEqual(app.buttons["profile.link"].value as? String, "查看与修改")
        app.tabBars.buttons["回顾"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["review.empty"].firstMatch.exists)
        let savedMeal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        reveal(savedMeal, in: app); savedMeal.tap()
        XCTAssertTrue(app.staticTexts["Offline integration meal"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        let savedWorkout = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.row.")).firstMatch
        reveal(savedWorkout, in: app); savedWorkout.tap()
        XCTAssertEqual(app.textFields["workout.name"].value as? String, "Offline integration workout")
        app.buttons["workout.close"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "forced-offline-restart-review"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<16 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
