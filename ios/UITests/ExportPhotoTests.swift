import XCTest

@MainActor final class ExportPhotoTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testGeneratePackageAndOpenSystemExportPicker() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString]; app.launch()
        showDataManagement(in: app); app.buttons["export.link"].tap()
        app.buttons["export.prepare"].tap(); app.buttons["确认生成"].tap()
        XCTAssertTrue(app.staticTexts["export.ready"].waitForExistence(timeout: 15))
        reveal(app.buttons["export.save"], in: app); app.buttons["export.save"].tap()
        let cancel = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "取消")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 60)); cancel.tap()
        XCTAssertTrue(app.buttons["export.save"].waitForExistence(timeout: 5))
    }
    func testOfflineMultiPhotoSaveManualEditDeleteAndRestore() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-store", UUID().uuidString,"--ui-test-offline"]; app.launch()
        app.buttons["meal.new"].tap(); app.buttons["meal.album"].tap()
        XCTAssertTrue(app.staticTexts["选择最多9张照片。"].waitForExistence(timeout: 60))
        // PhotosUI's remote accessibility grid invalidates cell snapshots on iOS 26.
        // The simulator fixture keeps its first two photos in the first visible grid row.
        Thread.sleep(forTimeInterval: 5)
        let screen = app.windows.firstMatch
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.70)).tap()
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.70)).tap()
        screen.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.17)).tap()
        XCTAssertTrue(app.buttons["移除第 2 张照片"].waitForExistence(timeout: 15))
        reveal(app.buttons["meal.save"],in:app);app.buttons["meal.save"].tap()
        app.terminate(); app.launch()
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","meal.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
        reveal(app.buttons["meal.calories"], in: app); app.buttons["meal.calories"].tap()
        XCTAssertTrue(app.textFields["manual.calories"].waitForExistence(timeout: 5))
        app.textFields["manual.calories"].tap();app.textFields["manual.calories"].typeText("420")
        reveal(app.buttons["manual.save"],in:app);app.buttons["manual.save"].tap()
        app.buttons["meal.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("420 kcal"))
        let note = app.descendants(matching:.any)["meal.note"].firstMatch;reveal(note,in:app);note.tap();note.typeText("Offline photo fixture")
        reveal(app.buttons["meal.save"],in:app);app.buttons["meal.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons["meal.calories"].label.contains("待估算"))
        reveal(app.buttons["meal.delete"],in:app);app.buttons["meal.delete"].tap();app.buttons["确认删除"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["meal.new"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        showDataManagement(in: app)
        XCTAssertTrue(app.buttons["trash.link"].waitForExistence(timeout: 5))
        app.buttons["trash.link"].tap();app.buttons["恢复"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout:5))
        app.tabBars.buttons["记录"].tap();XCTAssertEqual(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","meal.row.")).count,1)
        app.terminate();app.launch();row.tap()
        XCTAssertTrue(note.waitForExistence(timeout:5));XCTAssertEqual(note.value as? String,"Offline photo fixture")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="offline-photos-restored";shot.lifetime = .keepAlways;add(shot)
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        func visible() -> Bool {
            guard element.isHittable else { return false }
            // A partially visible metadata row can report hittable beneath the fixed actions.
            if element.identifier == "meal.calories" {
                return element.frame.maxY <= app.buttons["meal.save"].frame.minY - 12
            }
            return true
        }
        for _ in 0..<12 {
            if visible() { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.20)))
        }
        XCTAssertTrue(visible())
    }
}
