import XCTest

@MainActor final class EstimateDisplayTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUnknownAndManualFoodRatioThroughEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch()
        app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        note.tap(); note.typeText("米饭")
        reveal(app.buttons["meal.save"], in: app); app.buttons["meal.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("待估算"))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)

        reveal(app.buttons["meal.calories"], in: app); app.buttons["meal.calories"].tap()
        let grams = app.textFields["克数（g，可留空）"]
        grams.tap(); grams.typeText("100")
        let kcal = app.textFields["manual.calories"]
        reveal(kcal, in: app); kcal.tap(); kcal.typeText("200")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        app.buttons["meal.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("200 kcal"))
        XCTAssertFalse(app.buttons["估算与修正历史"].exists)
        XCTAssertFalse(app.buttons["记录信息"].exists)
        XCTAssertFalse(app.buttons["meal.manual"].exists)
        XCTAssertFalse(app.buttons["ai.request"].exists)
        let actions = ["meal.save", "meal.delete", "meal.close"].map { app.buttons[$0] }
        for button in actions {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertEqual(button.frame.minY, actions[0].frame.minY, accuracy: 1)
            XCTAssertEqual(button.frame.width, actions[0].frame.width, accuracy: 1)
        }

        reveal(app.buttons["meal.calories"], in: app); app.buttons["meal.calories"].tap()
        let revisedGrams = app.textFields["克数（g，可留空）"]
        revisedGrams.tap()
        revisedGrams.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "150")
        reveal(app.staticTexts["manual.total"], in: app)
        XCTAssertEqual(app.staticTexts["manual.total"].firstMatch.label, "整餐合计 300 kcal")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        app.buttons["meal.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("300 kcal"))
        XCTAssertFalse(app.buttons["估算与修正历史"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "direct-meal-editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
