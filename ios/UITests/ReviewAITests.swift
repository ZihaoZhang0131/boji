import XCTest

@MainActor final class ReviewAITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testEveryChartDayCanBeSelectedOnSmallScreen() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["回顾"].tap()
        for (range, count) in [("7 天", 7), ("30 天", 30)] {
            let picker = app.buttons[range]
            if !picker.isHittable { app.swipeDown() }; picker.tap()
            let chart = app.scrollViews["review.chart"]
            XCTAssertTrue(chart.waitForExistence(timeout: 5))
            if !chart.isHittable { app.swipeUp() }
            let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.day.")).allElementsBoundByIndex
            XCTAssertEqual(days.count, count)
            for day in days {
                for _ in 0..<35 {
                    if day.isHittable { break }
                    let left = day.frame.midX < chart.frame.midX
                    let start = chart.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.3 : 0.7, dy: 0.5))
                    let end = chart.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.7 : 0.3, dy: 0.5))
                    start.press(forDuration: 0.05, thenDragTo: end)
                }
                XCTAssertTrue(day.isHittable); XCTAssertGreaterThanOrEqual(day.frame.width, 44)
                day.tap()
                XCTAssertEqual(app.staticTexts["review.selectedDay"].label, String(day.identifier.dropFirst("review.day.".count)))
            }
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "small-screen-review"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testUnconfiguredAIAndAutomaticToggleDoNotAuthorizeSending() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]; app.launch()
        app.tabBars.buttons["我的"].tap(); app.buttons["ai.settings"].tap()
        XCTAssertTrue(app.textFields["ai.url"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["ai.url"].value as? String, "HTTPS 服务地址")
        let automatic = app.switches["保存带照片餐食后自动估算"]
        for _ in 0..<5 { if automatic.isHittable && automatic.frame.maxY < app.tabBars.firstMatch.frame.minY { break }; app.swipeUp() }
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: automatic)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["ai.authorized"].exists)
        app.terminate(); app.launch(); app.tabBars.buttons["我的"].tap(); app.buttons["ai.settings"].tap()
        for _ in 0..<5 { if automatic.isHittable && automatic.frame.maxY < app.tabBars.firstMatch.frame.minY { break }; app.swipeUp() }
        XCTAssertEqual(automatic.value as? String, "1"); XCTAssertFalse(app.staticTexts["ai.authorized"].exists)
    }
}
