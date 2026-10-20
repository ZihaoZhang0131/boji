import XCTest
import Foundation
import BojiDomain
import BojiPersistence
import BojiPortability
import BojiEstimation
@testable import Boji

private actor MigrationCredentials: ServiceCredentials {
    private var values: [URL: String] = [:]
    func token(for url: URL) -> String? { values[url] }
    func setToken(_ token: String?, for url: URL) { values[url] = token }
}

@MainActor final class WorkspacePortabilityTests:XCTestCase {
    func testRetiredQwenHostClearsConsentAndLocalCredentialWithoutChangingRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await ManagedStore(root: root).open()
        let credentials = MigrationCredentials()
        try await credentials.setToken("retired-key-fixture", for: QwenDirectClient.legacyEndpoint)
        let policy = QwenDirectClient(credentials: credentials).policy()
        try await repository.configureEstimation(url: QwenDirectClient.legacyEndpoint, policy: policy)
        try await repository.acceptEstimationPolicy(policy.version)
        var meal = Meal(time: RecordTime(clock: SystemClock())); meal.note = "保留本机餐食"
        try await repository.saveMeal(meal, draftID: nil, operationID: UUID())
        let dependencies = AppDependencies(storageRoot: root, clock: SystemClock(), estimation: UnconfiguredEstimationService(),
                                           files: LocalFileAccess(), credentials: credentials, remote: PersonalEstimationRemote(credentials: credentials))
        let workspace = WorkspaceModel(dependencies: dependencies)
        await workspace.load()
        XCTAssertNil(workspace.errorMessage)
        XCTAssertNil(workspace.snapshot?.aiSettings.serviceURL)
        XCTAssertNil(workspace.snapshot?.aiSettings.acceptedPolicy)
        XCTAssertEqual(workspace.snapshot?.activeMeals.map(\.id), [meal.id])
        let oldKey = try await credentials.token(for: QwenDirectClient.legacyEndpoint)
        XCTAssertNil(oldKey)
    }

    func testImportRefreshesViewsInvalidatesOldWritersAndRollbackRefreshesAgain() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let workspace=WorkspaceModel(dependencies:.production(storageRoot:root.appendingPathComponent("personal")))
        await workspace.load();XCTAssertNil(workspace.errorMessage)
        let old=try await workspace.activeRepository()
        var local=Meal(time:RecordTime(clock:SystemClock()));local.note="Keep existing local fact"
        try await old.saveMeal(local,draftID:nil,operationID:UUID());try await workspace.refresh()
        let source=try await LocalRepository.open(at:root.appendingPathComponent("source"))
        var foreign=Meal(time:local.time);foreign.note="Imported fixture"
        try await source.saveMeal(foreign,draftID:nil,operationID:UUID())
        try await source.commit(id:UUID()) { $0.aiSettings.acceptedPolicy="must not transfer";$0.aiSettings.automatic=true }
        let package=try PackageReader().read(await PackageExporter().export(repository:source,to:root.appendingPathComponent("exports")).url)
        let preview=try ImportPlanner.plan(package:package,local:await old.snapshot())
        try await workspace.importPackage(preview,package:package)
        XCTAssertEqual(workspace.snapshot?.activeMeals.count,2)
        XCTAssertTrue(workspace.snapshot?.activeMeals.contains{$0.id==local.id && $0.note==local.note}==true)
        XCTAssertNil(workspace.snapshot?.aiSettings.acceptedPolicy);XCTAssertEqual(workspace.snapshot?.jobs.count,0)
        do { try await old.commit(id:UUID()) { $0.meals=[] };XCTFail("Obsolete repository must remain read-only") } catch {}
        await workspace.restorePreviousStore()
        XCTAssertNil(workspace.errorMessage);XCTAssertEqual(workspace.snapshot?.activeMeals.map(\.id),[local.id])
        XCTAssertEqual(workspace.snapshot?.jobs.count,0)
    }
}
