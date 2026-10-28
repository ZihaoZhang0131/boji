import XCTest
import SwiftUI
import BojiDomain
import BojiPersistence
import BojiEstimation
@testable import Boji

private actor MineCredentials: ServiceCredentials {
    var values: [URL: String] = [:]
    func token(for url: URL) -> String? { values[url] }
    func setToken(_ token: String?, for url: URL) { values[url] = token }
}
private actor MineRemote: EstimationRemote {
    var rejectPolicy = false
    func failPolicyRequest() { rejectPolicy = true }
    static var fixture: AIServicePolicy {
        .init(available: true, version: "fixture-v1", provider: "测试供应商", model: "隔离模型", sentData: ["饮食照片", "备注"], providerRetention: "仅供测试", rawRetentionHours: 0, metadataRetentionDays: 0, feePayer: "测试不会产生费用", dailyAttempts: 5)
    }
    func policy(url: URL) async throws -> AIServicePolicy {
        if rejectPolicy { throw URLError(.notConnectedToInternet) }
        return Self.fixture
    }
    func upload(data: Data, job: EstimateJob) async throws -> String { throw URLError(.unsupportedURL) }
    func submit(_ job: EstimateJob) async throws -> RemoteEstimate { throw URLError(.unsupportedURL) }
    func poll(_ job: EstimateJob) async throws -> RemoteEstimate { throw URLError(.unsupportedURL) }
    func cancel(_ job: EstimateJob) async throws {}
}
@MainActor final class MinePresentationTests: XCTestCase {
    private struct Clock: AppClock {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T04:00:00Z")!
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }
    func testProfileStatusUsesEffectiveTodayAndHandlesLoadingFailure() {
        let clock = Clock(), today = LocalDay(clock.now, timeZone: clock.timeZone)
        var state = DatasetSnapshot()
        XCTAssertEqual(MinePresentation.profileStatus(nil, today: today), "载入中")
        XCTAssertEqual(MinePresentation.profileStatus(nil, today: today, loadingFailed: true), "暂不可用")
        XCTAssertEqual(MinePresentation.profileStatus(state, today: today), "待填写")
        state.profiles = [.init(effectiveDay: today.adding(days: 1), sequence: 1, profile: .init(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2), createdAt: clock.now)]
        XCTAssertEqual(MinePresentation.profileStatus(state, today: today), "待填写")
        state.profiles[0].effectiveDay = today.adding(days: -1)
        XCTAssertEqual(MinePresentation.profileStatus(state, today: today), "已填写")
    }
    func testAIStatusDoesNotTreatAutomaticOrOldConsentAsAuthorization() {
        XCTAssertEqual(MinePresentation.aiStatus(nil, loadingFailed: true), "暂不可用")
        var settings = AISettings(); settings.automatic = true
        XCTAssertEqual(MinePresentation.aiStatus(settings), "未配置")
        settings.serviceURL = URL(string: "https://fixture.invalid")!
        XCTAssertEqual(MinePresentation.aiStatus(settings), "暂不可用")
        settings.cachedPolicy = MineRemote.fixture
        XCTAssertEqual(MinePresentation.aiStatus(settings), "待授权")
        settings.acceptedPolicy = "old-policy"
        XCTAssertEqual(MinePresentation.aiStatus(settings), "待授权")
        settings.acceptedPolicy = MineRemote.fixture.version
        XCTAssertEqual(MinePresentation.aiStatus(settings), "已授权")
        settings.cachedPolicy?.available = false
        XCTAssertEqual(MinePresentation.aiStatus(settings), "暂不可用")
    }
    func testIsolatedConsentRevokeDisconnectAndReturnRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock(), credentials = MineCredentials(), remote = MineRemote()
        let dependencies = AppDependencies(storageRoot: root, clock: clock, estimation: UnconfiguredEstimationService(), files: LocalFileAccess(), credentials: credentials, remote: remote)
        let workspace = WorkspaceModel(dependencies: dependencies)
        await workspace.load(); XCTAssertNil(workspace.errorMessage)
        await workspace.setAutomaticAI(true)
        XCTAssertEqual(MinePresentation.aiStatus(workspace.snapshot?.aiSettings), "未配置")
        let connected = await workspace.connectAI(urlText: "https://fixture.invalid", token: "isolated-test-key")
        XCTAssertTrue(connected)
        XCTAssertEqual(MinePresentation.aiStatus(workspace.snapshot?.aiSettings), "待授权")
        await workspace.acceptAI()
        XCTAssertEqual(MinePresentation.aiStatus(workspace.snapshot?.aiSettings), "已授权")
        await remote.failPolicyRequest()
        let failed = await workspace.connectAI(urlText: "https://fixture.invalid", token: "replacement-fixture-key")
        XCTAssertFalse(failed); XCTAssertNotNil(workspace.aiError)
        XCTAssertEqual(MinePresentation.aiStatus(workspace.snapshot?.aiSettings), "待授权")
        await workspace.revokeAI()
        XCTAssertEqual(MinePresentation.aiStatus(workspace.snapshot?.aiSettings), "待授权")
        await workspace.disconnectAI()
        XCTAssertEqual(MinePresentation.aiStatus(workspace.snapshot?.aiSettings), "未配置")
        let token = await credentials.token(for: URL(string: "https://fixture.invalid")!)
        XCTAssertNil(token); XCTAssertEqual(workspace.snapshot?.jobs.count, 0)
        let reopened = WorkspaceModel(dependencies: dependencies); await reopened.load()
        XCTAssertTrue(reopened.snapshot?.aiSettings.automatic == true)
        XCTAssertEqual(MinePresentation.aiStatus(reopened.snapshot?.aiSettings), "未配置")
    }
    func testTrashCountsOnlyDeletedRecords() {
        var state = DatasetSnapshot(); let time = RecordTime(clock: Clock())
        state.meals = [Meal(time: time), Meal(time: time)]; state.workouts = [Workout(time: time)]
        XCTAssertEqual(MinePresentation.trashCount(state), 0)
        state.meals[0].deletedAt = Clock().now; state.workouts[0].deletedAt = Clock().now
        XCTAssertEqual(MinePresentation.trashCount(state), 2)
    }
    func testNavigationRowsRenderAtSmallWidthAndLargestType() throws {
        for (width, type, scheme, name) in [(320.0, DynamicTypeSize.large, ColorScheme.light, "small"), (393, .large, .dark, "dark"), (320, .accessibility5, .dark, "largest")] {
            let renderer = ImageRenderer(content: VStack(spacing: 0) {
                MineNavigationRow(title: "身体资料", status: "已填写"); Divider()
                MineNavigationRow(title: "AI 估算", status: "待授权"); Divider()
                MineNavigationRow(title: "数据管理")
            }.padding(16).frame(width: width).background(PixelTheme.canvas).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, type))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width)
            let shot = XCTAttachment(image: image); shot.name = "mine-rows-" + name; shot.lifetime = .keepAlways; add(shot)
        }
    }
    func testConfiguredAISettingsRenderWithIsolatedPolicies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let dependencies = AppDependencies(storageRoot: root, clock: Clock(), estimation: UnconfiguredEstimationService(), files: LocalFileAccess(), credentials: MineCredentials(), remote: MineRemote())
        let workspace = WorkspaceModel(dependencies: dependencies)
        await workspace.load()
        let repository = try await workspace.activeRepository()
        for scenario in ["pending", "authorized", "unavailable"] {
            try await repository.commit(id: UUID()) { state in
                state.aiSettings.serviceURL = URL(string: "https://fixture.invalid")!
                state.aiSettings.cachedPolicy = MineRemote.fixture
                state.aiSettings.cachedPolicy?.available = scenario != "unavailable"
                state.aiSettings.acceptedPolicy = scenario == "authorized" ? MineRemote.fixture.version : nil
            }
            try await workspace.refresh()
            for (width, size, scheme, label) in [(393.0, DynamicTypeSize.large, ColorScheme.light, "regular"), (320, .accessibility5, .dark, "largest")] {
                let image = try await snapshot(AISettingsView(workspace: workspace)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size), width: width, scheme: scheme)
                XCTAssertEqual(image.size.width, width)
                let shot = XCTAttachment(image: image); shot.name = "mine-ai-\(scenario)-\(label)"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        try await repository.commit(id: UUID()) { state in
            var meal = Meal(time: RecordTime(clock: Clock()))
            meal.note = "午餐：鸡肉沙拉与一杯拿铁"; meal.deletedAt = Clock().now
            state.meals = [meal]
        }
        try await workspace.refresh()
        let image = try await snapshot(TrashView(workspace: workspace)
            .environment(\.dynamicTypeSize, .accessibility5).environment(\.colorScheme, .dark), width: 320, scheme: .dark)
        let shot = XCTAttachment(image: image); shot.name = "mine-trash-record-largest"; shot.lifetime = .keepAlways; add(shot)
    }
    private func snapshot<Content: View>(_ content: Content, width: CGFloat, scheme: ColorScheme) async throws -> UIImage {
        // ScrollView and system controls need a hosted hierarchy; ImageRenderer only
        // captures their background before those views have laid out.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let host = UIHostingController(rootView: content)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        host.view.frame = window.bounds
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
    }
}
