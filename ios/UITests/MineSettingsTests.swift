import XCTest

@MainActor final class MineSettingsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testSettingsNavigationAndScreenshots() { checkScreens(largest: false) }
    func testSettingsLargestTextAndScreenshots() { checkScreens(largest: true) }
    func testBackupDirectoryPickerCancelAndNavigation() { checkBackup(largest: false) }
    func testBackupLargestTextActionsAndNavigation() { checkBackup(largest: true) }
    func testBackupMoreMenuLegacyEnableStopAndManual() { checkBackupMenu(largest: false) }
    func testBackupMoreMenuLargestText() { checkBackupMenu(largest: true) }
    private func checkBackup(largest: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); showDataManagement(in: app)
        check(app.buttons["backup.link"], in: app); app.buttons["backup.link"].tap()
        XCTAssertTrue(app.navigationBars["iCloud 备份"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["backup.status"].label, "尚未开启备份")
        XCTAssertFalse(app.staticTexts["backup.upload"].exists)
        XCTAssertFalse(app.staticTexts["backup.lastWritten"].exists)
        XCTAssertFalse(app.buttons["backup.more"].exists)
        XCTAssertFalse(app.buttons["在 Mac 上读取"].exists)
        attach(app, name: "backup-unconfigured", largest: largest)
        reveal(app.buttons["backup.choose"], in: app); check(app.buttons["backup.choose"], in: app)
        attach(app, name: "backup-actions", largest: largest)
        app.buttons["backup.choose"].tap()
        // Wait for the asynchronous Files controller, rather than dragging its blank loading sheet.
        let pickerReady = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "取消")).firstMatch
        XCTAssertTrue(pickerReady.waitForExistence(timeout: 30))
        attach(app, name: "backup-picker", largest: largest)
        // The remote Files view may expose an invisible placeholder named Cancel.
        // Dismiss the system sheet from its top edge, without choosing a directory.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["backup.choose"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["backup.now"].exists)
        // The system back control remains available, including after a cancelled picker.
        app.navigationBars["iCloud 备份"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["backup.link"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); showDataManagement(in: app); app.buttons["backup.link"].tap()
        XCTAssertEqual(app.staticTexts["backup.status"].label, "尚未开启备份")
    }
    private func checkBackupMenu(largest: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline", "--ui-test-backup-legacy"]
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); showDataManagement(in: app); app.buttons["backup.link"].tap()
        XCTAssertEqual(app.staticTexts["backup.status"].label, "自动备份待启用")
        XCTAssertEqual(app.staticTexts["backup.lastWritten"].label, "尚无备份")
        XCTAssertFalse(app.staticTexts["backup.upload"].exists)
        check(app.buttons["backup.enable"], in: app)
        checkToolbarMenuHitArea(in: app)
        app.buttons["backup.more"].tap()
        XCTAssertTrue(app.buttons["立即备份"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["更换目录"].isHittable)
        XCTAssertFalse(app.buttons["停止自动备份"].exists)
        attach(app, name: "backup-menu-legacy", largest: largest)
        tapMenuAction(app.buttons["立即备份"], edge: -21.5)
        let written = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "最近备份"), object: app.staticTexts["backup.lastWritten"])
        XCTAssertEqual(XCTWaiter.wait(for: [written], timeout: 15), .completed)
        XCTAssertTrue(["已写入目录", "上传状态未知"].contains(app.staticTexts["backup.upload"].label))
        XCTAssertEqual(app.staticTexts["backup.status"].label, "自动备份待启用")
        let firstWrite = app.staticTexts["backup.lastWritten"].label
        app.buttons["backup.more"].tap()
        tapMenuAction(app.buttons["立即备份"], edge: 21.5)
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: app.buttons["backup.enable"])
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 10), .completed)
        XCTAssertEqual(app.staticTexts["backup.lastWritten"].label, firstWrite)
        app.buttons["backup.enable"].tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "自动备份已开启"), object: app.staticTexts["backup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        attach(app, name: "backup-enabled", largest: largest)
        XCTAssertFalse(app.buttons["在 Mac 上读取"].exists)
        let help = app.buttons["backup.help"]
        reveal(help, in: app); check(help, in: app)
        let foregroundExplanation = app.staticTexts["App 在前台时自动备份，离开后未完成的工作会在下次打开时继续。"]
        XCTAssertFalse(foregroundExplanation.exists)
        help.tap()
        XCTAssertTrue(foregroundExplanation.waitForExistence(timeout: 5))
        attach(app, name: "backup-help", largest: largest)
        help.tap()
        // Return to the status group after checking the scrollable disclosure.
        for _ in 0..<5 {
            if app.staticTexts["backup.status"].isHittable { break }
            app.swipeDown()
        }
        app.buttons["backup.more"].tap()
        XCTAssertTrue(app.buttons["停止自动备份"].waitForExistence(timeout: 5))
        attach(app, name: "backup-menu-enabled", largest: largest)
        tapMenuAction(app.buttons["停止自动备份"], edge: 21.5)
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "自动备份已停止"), object: app.staticTexts["backup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed)
        let lastTime = app.staticTexts["backup.lastWritten"].label
        reveal(app.buttons["backup.now"], in: app); check(app.buttons["backup.now"], in: app)
        app.buttons["backup.now"].tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["backup.now"])
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertEqual(app.staticTexts["backup.lastWritten"].label, lastTime)
        XCTAssertEqual(app.staticTexts["backup.status"].label, "自动备份已停止")
        app.buttons["backup.more"].tap(); tapMenuAction(app.buttons["更换目录"], edge: 21.5)
        let pickerReady = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "取消")).firstMatch
        XCTAssertTrue(pickerReady.waitForExistence(timeout: 30))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["backup.more"])
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
        XCTAssertEqual(app.staticTexts["backup.lastWritten"].label, lastTime)
        XCTAssertEqual(app.staticTexts["backup.status"].label, "自动备份已停止")
        attach(app, name: "backup-stopped", largest: largest)
        app.buttons["backup.more"].tap()
        XCTAssertTrue(app.buttons["启用自动备份"].waitForExistence(timeout: 5))
        attach(app, name: "backup-menu-stopped", largest: largest)
        tapMenuAction(app.buttons["启用自动备份"], edge: -21.5)
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "自动备份已开启"), object: app.staticTexts["backup.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 10), .completed)
        app.navigationBars["iCloud 备份"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["backup.link"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); showDataManagement(in: app); app.buttons["backup.link"].tap()
        XCTAssertEqual(app.staticTexts["backup.status"].label, "自动备份已开启")
    }
    private func checkScreens(largest: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString, "--ui-test-offline"]
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); showMineRoot(in: app)
        XCTAssertEqual(app.buttons["profile.link"].value as? String, "待填写")
        XCTAssertEqual(app.buttons["ai.settings"].value as? String, "未配置")
        for id in ["profile.link", "ai.settings", "data.management"] { check(app.buttons[id], in: app) }
        attach(app, name: "home", largest: largest)
        app.buttons["profile.link"].tap(); check(app.buttons["profile.save"], in: app)
        attach(app, name: "profile", largest: largest)
        app.buttons["profile.save"].tap(); XCTAssertTrue(app.staticTexts["profile.error"].waitForExistence(timeout: 5))
        attach(app, name: "profile-error", largest: largest)
        showMineRoot(in: app); app.buttons["ai.settings"].tap()
        XCTAssertTrue(app.secureTextFields["ai.token"].waitForExistence(timeout: 5)); check(app.secureTextFields["ai.token"], in: app)
        attach(app, name: "ai", largest: largest)
        showDataManagement(in: app); attach(app, name: "data", largest: largest)
        reveal(app.buttons["export.link"], in: app); app.buttons["export.link"].tap(); check(app.buttons["export.prepare"], in: app)
        attach(app, name: "export", largest: largest)
        app.buttons["export.prepare"].tap(); app.buttons["确认生成"].tap()
        XCTAssertTrue(app.staticTexts["export.ready"].waitForExistence(timeout: 15))
        reveal(app.buttons["export.save"], in: app); check(app.buttons["export.save"], in: app)
        attach(app, name: "export-ready", largest: largest)
        showDataManagement(in: app); reveal(app.buttons["import.link"], in: app); app.buttons["import.link"].tap()
        XCTAssertTrue(app.buttons["import.select"].waitForExistence(timeout: 5)); check(app.buttons["import.select"], in: app)
        attach(app, name: "import", largest: largest)
        let recovery = app.buttons["恢复旧版本"]
        reveal(recovery, in: app); check(recovery, in: app); recovery.tap()
        let restore = app.buttons["恢复上次导入或升级前资料"]
        reveal(restore, in: app); restore.tap()
        XCTAssertTrue(app.buttons["确认恢复"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["确认恢复"].waitForNonExistence(timeout: 5))
        showDataManagement(in: app); reveal(app.buttons["trash.link"], in: app); app.buttons["trash.link"].tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5)); attach(app, name: "trash", largest: largest)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { if element.isHittable && element.frame.maxY < app.tabBars.firstMatch.frame.minY { return }; app.swipeUp() }
    }
    private func checkToolbarMenuHitArea(in app: XCUIApplication) {
        let menu = app.buttons["backup.more"]
        check(menu, in: app)
        // Tap just inside both edges of the required 44pt target.
        for offset: CGFloat in [-21.5, 21.5] {
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: offset)).tap()
            XCTAssertTrue(app.buttons["更换目录"].waitForExistence(timeout: 5))
            // The system menu deliberately hides underlying elements from accessibility hit testing.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.85)).tap()
            XCTAssertTrue(app.buttons["更换目录"].waitForNonExistence(timeout: 5))
        }
    }
    private func tapMenuAction(_ element: XCUIElement, edge: CGFloat) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        // Exercise both the measurable row and its edge, not just the center of its label.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: edge)).tap()
    }
    private func check(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.minX, 0)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
    }
    private func attach(_ app: XCUIApplication, name: String, largest: Bool) {
        // A hittable control can arrive before the navigation transition settles.
        Thread.sleep(forTimeInterval: 0.5)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "mine-" + name + (largest ? "-largest" : "-small")
        shot.lifetime = .keepAlways; add(shot)
    }
}
