import XCTest
import SwiftUI
import Observation
import BojiDomain
import BojiPersistence
import BojiPortability
import BojiEstimation
@testable import Boji

private actor BackupCredentials: ServiceCredentials {
    func token(for url: URL) -> String? { nil }
    func setToken(_ token: String?, for url: URL) {}
}
private actor BackupRemote: EstimationRemote {
    func policy(url: URL) async throws -> AIServicePolicy { throw URLError(.notConnectedToInternet) }
    func upload(data: Data, job: EstimateJob) async throws -> String { throw URLError(.notConnectedToInternet) }
    func submit(_ job: EstimateJob) async throws -> RemoteEstimate { throw URLError(.notConnectedToInternet) }
    func poll(_ job: EstimateJob) async throws -> RemoteEstimate { throw URLError(.notConnectedToInternet) }
    func cancel(_ job: EstimateJob) async throws {}
}
private final class BackupSettingsClock: AppClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ISO8601DateFormatter().date(from: "2026-10-25T04:00:00Z")!
    var now: Date { lock.withLock { instant } }
    var timeZone: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    func advance(_ seconds: TimeInterval) { lock.withLock { instant += seconds } }
}
@MainActor final class BackupSettingsTests: XCTestCase {
    private func workspace(_ root: URL, clock: any AppClock = SystemClock()) -> WorkspaceModel {
        WorkspaceModel(dependencies: .init(storageRoot: root, clock: clock, estimation: UnconfiguredEstimationService(), files: LocalFileAccess(), credentials: BackupCredentials(), remote: BackupRemote()))
    }
    func testFirstSelectionAutomaticUpdatesRestartStopManualAndReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("chosen"), clock = BackupSettingsClock()
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        let model = workspace(root.appendingPathComponent("store"), clock: clock)
        await model.load(); await model.connectBackup(chosen)
        XCTAssertNil(model.backupError); XCTAssertNotNil(model.snapshot?.backup.lastWrittenAt)
        XCTAssertEqual(model.snapshot?.backup.automaticEnabled, true)
        let written = model.snapshot?.backup.lastWrittenAt
        let repository = try await model.activeRepository()
        var meal = Meal(time: RecordTime(clock: clock)); meal.note = "隔离的自动备份测试"
        try await repository.saveMeal(meal, draftID: nil, operationID: UUID())
        await model.processBackup(); clock.advance(5); await model.processBackup()
        XCTAssertEqual(model.snapshot?.backup.lastWrittenAt, written)
        clock.advance(1); await model.processBackup()
        XCTAssertEqual(model.snapshot?.backup.lastPublishedRevision, model.snapshot?.dataset.revision)
        XCTAssertNotEqual(model.snapshot?.backup.lastWrittenAt, written)
        let restarted = workspace(root.appendingPathComponent("store"), clock: clock)
        await restarted.load(); XCTAssertEqual(restarted.snapshot?.backup.automaticEnabled, true)
        await restarted.setAutomaticBackup(false)
        let stoppedTime = restarted.snapshot?.backup.lastWrittenAt
        let stopped = workspace(root.appendingPathComponent("store"), clock: clock)
        await stopped.load(); XCTAssertEqual(stopped.snapshot?.backup.automaticEnabled, false)
        let stoppedRepository = try await stopped.activeRepository()
        try await stoppedRepository.commit(id: UUID()) { $0.meals[0].note = "停止后的本机记录" }
        clock.advance(60); await stopped.processBackup(); clock.advance(60); await stopped.processBackup()
        XCTAssertEqual(stopped.snapshot?.backup.lastWrittenAt, stoppedTime)
        await stopped.backupNow()
        XCTAssertEqual(stopped.snapshot?.backup.automaticEnabled, false)
        XCTAssertFalse(try XCTUnwrap(stopped.snapshot).backup.dirty)
        let manualTime = stopped.snapshot?.backup.lastWrittenAt
        clock.advance(60); await stopped.backupNow()
        XCTAssertEqual(stopped.snapshot?.backup.lastWrittenAt, manualTime)
        await stopped.setAutomaticBackup(true)
        XCTAssertEqual(stopped.snapshot?.backup.automaticEnabled, true)
        let replacement = root.appendingPathComponent("replacement")
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        await stopped.connectBackup(replacement)
        XCTAssertEqual(stopped.snapshot?.backup.directoryLabel, "replacement")
        XCTAssertEqual(stopped.snapshot?.backup.automaticEnabled, true)
        XCTAssertNotNil(stopped.snapshot?.backup.lastWrittenAt)
        XCTAssertNil(stopped.snapshot?.backup.lastError)
    }
    func testImportAndRestoreKeepCurrentStoppedChoiceAndDirectoryRatherThanPreviewOrOldGeneration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        let model = workspace(root.appendingPathComponent("store"))
        await model.load(); await model.connectBackup(chosen)
        let old = try await model.activeRepository()
        let source = try await LocalRepository.open(at: root.appendingPathComponent("source"))
        var meal = Meal(time: RecordTime(clock: SystemClock())); meal.note = "导入隔离数据"
        try await source.saveMeal(meal, draftID: nil, operationID: UUID())
        let package = try PackageReader().read(await PackageExporter().export(repository: source, to: root.appendingPathComponent("export")).url)
        let preview = try ImportPlanner.plan(package: package, local: await old.snapshot())
        await model.setAutomaticBackup(false)
        let beforeImport = try XCTUnwrap(model.snapshot).backup
        try await model.importPackage(preview, package: package)
        XCTAssertEqual(model.snapshot?.backup.automaticEnabled, false)
        XCTAssertEqual(model.snapshot?.backup.directoryBookmark, beforeImport.directoryBookmark)
        XCTAssertEqual(model.snapshot?.backup.lastWrittenAt, beforeImport.lastWrittenAt)
        XCTAssertTrue(try XCTUnwrap(model.snapshot).backup.dirty)
        let newDirectory = root.appendingPathComponent("after-import")
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        await model.connectBackup(newDirectory); await model.setAutomaticBackup(false)
        let beforeRestore = try XCTUnwrap(model.snapshot).backup
        await model.restorePreviousStore()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.snapshot?.backup.automaticEnabled, false)
        XCTAssertEqual(model.snapshot?.backup.directoryBookmark, beforeRestore.directoryBookmark)
        XCTAssertEqual(model.snapshot?.backup.pointerSHA256, beforeRestore.pointerSHA256)
        XCTAssertEqual(model.snapshot?.backup.lastWrittenAt, beforeRestore.lastWrittenAt)
        XCTAssertEqual(model.snapshot?.activeMeals.count, 0)
        await model.backupNow()
        XCTAssertNil(model.snapshot?.backup.lastError)
        XCTAssertFalse(try XCTUnwrap(model.snapshot).backup.dirty)
    }
    func testDirectorySelectionErrorSurvivesAutomaticChecksAndDemoNeverPublishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = workspace(root.appendingPathComponent("store"))
        await model.load(); await model.connectBackup(root.appendingPathComponent("does-not-exist"))
        let message = try XCTUnwrap(model.backupError)
        await model.processBackup()
        XCTAssertEqual(model.backupError, message)
        XCTAssertNil(model.snapshot?.backup.directoryBookmark)
        let chosen = root.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        await model.connectBackup(chosen)
        let saved = try XCTUnwrap(model.snapshot).backup
        await model.toggleDemo(); XCTAssertTrue(model.isDemo)
        await model.backupNow(); await model.processBackup()
        XCTAssertNil(model.snapshot?.backup.lastWrittenAt)
        await model.toggleDemo(); XCTAssertFalse(model.isDemo)
        XCTAssertEqual(model.snapshot?.backup.lastWrittenAt, saved.lastWrittenAt)
        XCTAssertEqual(model.snapshot?.backup.automaticEnabled, true)
        XCTAssertEqual(model.snapshot?.backup.directoryBookmark, saved.directoryBookmark)
    }
    func testPresentationNeverEquatesLocalWriteWithUploadAndKeepsStoppedHistory() {
        var state = BackupState()
        XCTAssertEqual(BackupPresentation.automaticStatus(state), "未设置")
        XCTAssertEqual(BackupPresentation.heading(state), "尚未开启备份")
        XCTAssertNil(BackupPresentation.activity(state))
        state.directoryBookmark = Data([1]); XCTAssertEqual(BackupPresentation.automaticStatus(state), "待启用")
        XCTAssertEqual(BackupPresentation.heading(state), "自动备份待启用")
        state.automaticEnabled = true; XCTAssertEqual(BackupPresentation.automaticStatus(state), "已开启")
        XCTAssertEqual(BackupPresentation.heading(state), "自动备份已开启")
        state.automaticEnabled = false; XCTAssertEqual(BackupPresentation.automaticStatus(state), "已停止")
        XCTAssertEqual(BackupPresentation.heading(state), "自动备份已停止")
        state.status = .uploadConfirmed
        XCTAssertNil(BackupPresentation.uploadStatus(state))
        state.lastWrittenAt = Date(); state.lastUploadStatus = .written
        XCTAssertEqual(BackupPresentation.uploadStatus(state), "已写入目录")
        state.lastUploadStatus = .pendingUpload
        XCTAssertEqual(BackupPresentation.uploadStatus(state), "等待系统上传")
        state.lastUploadStatus = .unknown
        XCTAssertEqual(BackupPresentation.uploadStatus(state), "上传状态未知")
        state.status = .dirty; state.lastUploadStatus = .uploadConfirmed
        XCTAssertEqual(BackupPresentation.uploadStatus(state), "系统已确认上传")
        state.status = .failed; state.lastError = "空间不足"
        XCTAssertEqual(BackupPresentation.uploadStatus(state), "系统已确认上传")
        XCTAssertNotNil(BackupPresentation.activity(state))
    }
    func testCompactTimeUsesDeviceTimeZoneAndCalendarDay() {
        let date = ISO8601DateFormatter().date(from: "2026-10-25T23:05:00Z")!
        XCTAssertEqual(BackupPresentation.lastWritten(date, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "2026/10/26 07:05")
        XCTAssertEqual(BackupPresentation.lastWritten(date, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026/10/25 16:05")
    }
    func testAutomaticChecksNeverToggleUserProgressEvenWhenPublishing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("chosen"), clock = BackupSettingsClock()
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        let model = workspace(root.appendingPathComponent("store"), clock: clock)
        await model.load(); await model.connectBackup(chosen)
        let repository = try await model.activeRepository()
        var meal = Meal(time: RecordTime(clock: clock)); meal.note = "后台检查使用的隔离记录"
        try await repository.saveMeal(meal, draftID: nil, operationID: UUID())
        let changed = expectation(description: "Routine checks leave user progress untouched")
        changed.isInverted = true
        withObservationTracking { _ = model.backupUserActionInProgress } onChange: { changed.fulfill() }
        await model.processBackup(); clock.advance(6); await model.processBackup()
        XCTAssertEqual(model.snapshot?.backup.lastPublishedRevision, model.snapshot?.dataset.revision)
        XCTAssertFalse(model.backupUserActionInProgress)
        await fulfillment(of: [changed], timeout: 0.05)
    }
    func testExplicitActionShowsProgressAndClearsItAfterSuccessAndFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = workspace(root); await model.load()
        let changed = expectation(description: "Explicit selection starts progress")
        withObservationTracking { _ = model.backupUserActionInProgress } onChange: { changed.fulfill() }
        await model.connectBackup(root.appendingPathComponent("missing"))
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertNotNil(model.backupError)
        XCTAssertFalse(model.backupUserActionInProgress)
        let chosen = root.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        await model.connectBackup(chosen); await model.setAutomaticBackup(false)
        let manual = expectation(description: "Manual backup starts progress while stopped")
        withObservationTracking { _ = model.backupUserActionInProgress } onChange: { manual.fulfill() }
        await model.backupNow()
        await fulfillment(of: [manual], timeout: 1)
        XCTAssertFalse(model.backupUserActionInProgress)
        XCTAssertNil(model.backupError)
        XCTAssertEqual(model.snapshot?.backup.automaticEnabled, false)
    }
    func testBackupRepresentativeScreensSmallDarkAndLargestType() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = workspace(root, clock: BackupSettingsClock()); await model.load()
        let repository = try await model.activeRepository()
        for scenario in ["unconfigured", "legacy", "enabled", "first", "pending", "confirmed", "unknown", "failed", "stopped", "long-directory"] {
            let token = model.snapshot?.backup.directoryBookmark
            try await repository.updateBackup(expectedBookmark: token) { value in
                value = BackupState()
                if scenario != "unconfigured" { value.directoryBookmark = Data([1]); value.directoryLabel = "薄记测试备份" }
                if scenario != "unconfigured" && scenario != "legacy" {
                    value.automaticEnabled = scenario != "stopped"
                    value.lastWrittenAt = BackupSettingsClock().now
                    value.lastUploadStatus = scenario == "pending" ? .pendingUpload : .written
                }
                if scenario == "first" { value.lastWrittenAt = nil; value.lastUploadStatus = nil; value.dirty = true }
                if scenario == "confirmed" { value.lastUploadStatus = .uploadConfirmed }
                if scenario == "unknown" { value.lastUploadStatus = .unknown }
                if scenario == "long-directory" { value.directoryLabel = "薄记测试备份 · 饮食训练和身体资料的完整历史归档目录" }
                if scenario == "failed" { value.status = .failed; value.lastError = "目录授权已失效，请重新选择目录。本机记录不受影响。" }
            }
            try await model.refresh()
            for (name, width, scheme, type): (String, CGFloat, ColorScheme, DynamicTypeSize) in [
                ("small", 320, .light, .large), ("small-dark", 320, .dark, .large),
                ("regular", 393, .light, .large), ("dark", 393, .dark, .large),
                ("largest", 320, .dark, .accessibility5)
            ] {
                let image = try await capture(NavigationStack { BackupView(workspace: model) }
                    .environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme), width: width, scheme: scheme)
                let shot = XCTAttachment(image: image); shot.name = "backup-\(scenario)-\(name)"; shot.lifetime = .keepAlways; add(shot)
                if scenario == "long-directory", name == "largest" {
                    let bottom = try await capture(NavigationStack { BackupView(workspace: model) }
                        .environment(\.dynamicTypeSize, type).environment(\.colorScheme, scheme), width: width, scheme: scheme, scrollToBottom: true)
                    let shot = XCTAttachment(image: bottom); shot.name = "backup-long-directory-largest-bottom"; shot.lifetime = .keepAlways; add(shot)
                }
            }
        }
    }
    private func capture<Content: View>(_ content: Content, width: CGFloat, scheme: ColorScheme, scrollToBottom: Bool = false) async throws -> UIImage {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let host = UIHostingController(rootView: content)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        func findScrollView(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScrollView($0) }.first
        }
        let scroll = try XCTUnwrap(findScrollView(host.view))
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1, "Content must wrap instead of scrolling horizontally")
        if scrollToBottom {
            XCTAssertGreaterThan(scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom, scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom), animated: false)
            try await Task.sleep(for: .milliseconds(100))
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
    }
}
