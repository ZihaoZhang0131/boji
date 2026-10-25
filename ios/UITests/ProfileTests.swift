import XCTest

@MainActor final class ProfileTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testProfilePersistsWithoutInventedTarget() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        showMineRoot(in: app); app.buttons["profile.link"].tap()
        app.buttons["profile.sex"].tap(); app.buttons["男性公式"].tap()
        enter("年龄（岁）", value: "28", in: app)
        enter("身高（cm）", value: "175", in: app)
        enter("体重（kg）", value: "70", in: app)
        reveal(app.buttons["profile.activity"], in: app); app.buttons["profile.activity"].tap(); app.buttons["较少活动 · 1.2"].tap()
        reveal(app.buttons["profile.save"], in: app); app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["profile.link"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["profile.link"].value as? String, "查看与修改")
        XCTAssertFalse(app.buttons["goal.link"].exists)
        app.terminate(); app.launch(); showMineRoot(in: app)
        app.buttons["profile.link"].tap()
        XCTAssertEqual(field("体重（kg）", in: app).value as? String, "70")
        let target = field("每日摄入目标（kcal，可留空）", in: app); reveal(target, in: app)
        XCTAssertEqual(target.value as? String, target.placeholderValue)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "profile-accessible-fields"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSmallScreenLargeTextNavigationHasAccessibleButtons() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let meal = app.buttons["meal.new"], workout = app.buttons["workout.new"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); XCTAssertTrue(meal.isHittable && workout.isHittable)
        let currentDate = app.staticTexts["records.date"].value as! String
        for button in [meal, workout, app.buttons["home.date." + currentDate]] { XCTAssertGreaterThanOrEqual(button.frame.height, 44); XCTAssertGreaterThanOrEqual(button.frame.width, 44) }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "small-screen-largest-text"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func field(_ label: String, in app: XCUIApplication) -> XCUIElement { app.textFields["profile.field." + label] }
    private func enter(_ label: String, value: String, in app: XCUIApplication) {
        let input = field(label, in: app); reveal(input, in: app); input.tap(); input.typeText(value)
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5)) }
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<16 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(element.isHittable)
    }
}
