import XCTest

@MainActor final class EstimateDisplayTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUnknownManualFoodRatioAndRevisionHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        app.launch()
        app.buttons["meal.new"].tap()
        let note = app.descendants(matching: .any)["meal.note"].firstMatch
        note.tap(); note.typeText("米饭")
        reveal(app.buttons["meal.save"], in: app); app.buttons["meal.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["meal.calories.unknown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)

        reveal(app.buttons["meal.manual"], in: app); app.buttons["meal.manual"].tap()
        let grams = app.textFields["克数（g，可留空）"]
        grams.tap(); grams.typeText("100")
        let kcal = app.textFields["manual.calories"]
        reveal(kcal, in: app); kcal.tap(); kcal.typeText("200")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        XCTAssertEqual(app.staticTexts["meal.calories.total"].firstMatch.label, "200 kcal")
        XCTAssertTrue(app.staticTexts["200 kcal · 人工确认"].exists)

        reveal(app.buttons["meal.manual"], in: app); app.buttons["meal.manual"].tap()
        let revisedGrams = app.textFields["克数（g，可留空）"]
        revisedGrams.tap()
        revisedGrams.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "150")
        XCTAssertEqual(app.staticTexts["manual.total"].firstMatch.label, "整餐合计 300 kcal")
        reveal(app.buttons["manual.save"], in: app); app.buttons["manual.save"].tap()
        XCTAssertEqual(app.staticTexts["meal.calories.total"].firstMatch.label, "300 kcal")
        XCTAssertTrue(app.staticTexts["300 kcal · 人工确认"].exists)
        for _ in 0..<8 { if app.staticTexts["200 kcal · 人工确认"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["200 kcal · 人工确认"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "estimate-revision-history"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
