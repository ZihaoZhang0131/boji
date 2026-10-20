import XCTest

@MainActor final class ExportPhotoTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testGeneratePackageAndOpenSystemExportPicker() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["我的"].tap(); app.buttons["export.link"].tap()
        app.buttons["export.prepare"].tap(); app.buttons["确认生成"].tap()
        XCTAssertTrue(app.staticTexts["export.ready"].waitForExistence(timeout: 15))
        reveal(app.buttons["export.save"], in: app); app.buttons["export.save"].tap()
        let cancel = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "取消")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 60)); cancel.tap()
        XCTAssertTrue(app.buttons["export.save"].waitForExistence(timeout: 5))
    }
    func testOfflineMultiPhotoDraftManualEditDeleteAndRestore() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString,"--ui-test-offline"]; app.launch()
        app.buttons["meal.new"].tap(); app.buttons["从相册选择"].tap()
        XCTAssertTrue(app.staticTexts["选择最多9张照片。"].waitForExistence(timeout: 60))
        // PhotosUI's remote accessibility grid invalidates cell snapshots on iOS 26.
        // The simulator fixture keeps its first two photos in the first visible grid row.
        Thread.sleep(forTimeInterval: 5)
        let screen = app.windows.firstMatch
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.70)).tap()
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.70)).tap()
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.17)).tap()
        XCTAssertTrue(app.staticTexts["照片 · 2/9"].waitForExistence(timeout: 15))
        app.buttons["收起"].tap(); app.terminate(); app.launch(); app.buttons["meal.new"].tap()
        XCTAssertTrue(app.staticTexts["照片 · 2/9"].waitForExistence(timeout: 5))
        reveal(app.buttons["meal.save"],in:app);app.buttons["meal.save"].tap()
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","meal.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
        reveal(app.buttons["meal.manual"],in:app);app.buttons["meal.manual"].tap()
        app.textFields["manual.calories"].tap();app.textFields["manual.calories"].typeText("420")
        reveal(app.buttons["manual.save"],in:app);app.buttons["manual.save"].tap()
        XCTAssertTrue(app.staticTexts["meal.calories.total"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["meal.calories.total"].firstMatch.label,"420 kcal")
        reveal(app.buttons["meal.edit"],in:app);app.buttons["meal.edit"].tap()
        let note = app.descendants(matching:.any)["meal.note"].firstMatch;reveal(note,in:app);note.tap();note.typeText("Offline photo fixture")
        reveal(app.buttons["meal.save"],in:app);app.buttons["meal.save"].tap()
        for _ in 0..<8 { if app.staticTexts["meal.calories.unknown"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["meal.calories.unknown"].exists)
        reveal(app.buttons["移到回收站"],in:app);app.buttons["移到回收站"].tap();app.buttons["确认删除"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["meal.new"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.92)).tap()
        XCTAssertTrue(app.buttons["回收站"].waitForExistence(timeout: 5))
        app.buttons["回收站"].tap();app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout:5))
        app.tabBars.buttons["记录"].tap();XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","meal.row.")).count,1)
        app.terminate();app.launch();row.tap()
        XCTAssertTrue(app.staticTexts["meal.detail.note"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["meal.detail.note"].label,"Offline photo fixture")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="offline-photos-restored";shot.lifetime = .keepAlways;add(shot)
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        for _ in 0..<12 { if element.isHittable { return };app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
