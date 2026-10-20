import Foundation
import Observation
import BojiDomain
import BojiPersistence
import BojiEstimation
import BojiPortability

@MainActor @Observable
final class WorkspaceModel {
    private(set) var snapshot: DatasetSnapshot?
    private(set) var session: WorkspaceSession?
    var errorMessage: String?
    private(set) var isLoading = false
    private let dependencies: AppDependencies
    private var managedStore: ManagedStore?
    private var estimateQueue: EstimateQueue?
    private var directoryBackup: DirectoryBackup?
    var backupError: String?
    var backupBusy = false
    let network = NetworkAvailability()
    var aiError: String?
    var clock: any AppClock { dependencies.clock }
    var isDemo: Bool { snapshot?.dataset.mode == .demo }
    var estimationService: any FoodEstimationService {
        isDemo ? DemoDisabledEstimationService() : dependencies.estimation
    }

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func load() async {
        guard session == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var suffix = "Boji/Personal"
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--ui-test-store"), arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) {
                suffix = "Boji/UITests/" + id.uuidString
            }
            #endif
            let root = try dependencies.storageRoot ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(suffix, isDirectory: true)
            let manager = ManagedStore(root: root)
            managedStore = manager
            let repository = try await manager.open()
            try await repository.expireTrash(at: dependencies.clock.now)
            if try await repository.snapshot().aiSettings.serviceURL == QwenDirectClient.legacyEndpoint {
                // A credential for the retired host must never silently authorize the new host.
                try await repository.configureEstimation(url: nil, policy: nil)
                try? await dependencies.credentials.setToken(nil, for: QwenDirectClient.legacyEndpoint)
            }
            let value = try await repository.snapshot()
            directoryBackup = nil
            session = WorkspaceSession(personal: repository, clock: dependencies.clock)
            estimateQueue = EstimateQueue(repository: repository, remote: dependencies.remote, clock: dependencies.clock)
            snapshot = value; errorMessage = nil
        } catch {
            errorMessage = "资料未能打开，原资料未被清空。请重试；若仍失败，请保留应用资料并按恢复说明处理。"
        }
    }

    func toggleDemo() async {
        guard let session, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if isDemo { await session.leaveDemo(); await estimateQueue?.setSuspended(false) }
            else { await estimateQueue?.setSuspended(true); try await session.enterDemo() }
            snapshot = try await session.activeRepository().snapshot()
            errorMessage = nil
        } catch { await estimateQueue?.setSuspended(isDemo); errorMessage = "未能切换资料空间，个人资料保持原样。" }
    }

    func restorePreviousStore() async {
        guard let managedStore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            await estimateQueue?.setSuspended(true)
            let repository = try await managedStore.restorePrevious()
            try await repository.commit(id: UUID()) { state in state.jobs = [];state.aiSettings.consentEpoch += 1 }
            snapshot = try await repository.snapshot()
            directoryBackup = nil
            session = WorkspaceSession(personal: repository, clock: dependencies.clock)
            estimateQueue = EstimateQueue(repository: repository, remote: dependencies.remote, clock: dependencies.clock)
            errorMessage = nil
        } catch { await estimateQueue?.setSuspended(isDemo); errorMessage = "无法恢复升级前资料。现有资料未被清空；请保留应用容器并查看恢复说明。" }
    }

    func importPackage(_ plan: ImportPlan, package: ValidatedPackage) async throws {
        guard let managedStore, !isLoading, !isDemo else { throw DomainError.conflict }
        isLoading = true;defer { isLoading = false }
        await estimateQueue?.setSuspended(true)
        do {
            let repository = try await PackageImporter().apply(plan, package: package, manager: managedStore)
            directoryBackup = nil
            session = WorkspaceSession(personal: repository, clock: dependencies.clock)
            estimateQueue = EstimateQueue(repository: repository, remote: dependencies.remote, clock: dependencies.clock)
            snapshot = try await repository.snapshot();errorMessage = nil
        } catch {
            // An interrupted activation may already have selected a complete new generation.
            if let repository = try? await managedStore.open() {
                directoryBackup = nil
                session = WorkspaceSession(personal: repository, clock: dependencies.clock)
                estimateQueue = EstimateQueue(repository: repository, remote: dependencies.remote, clock: dependencies.clock)
                snapshot = try? await repository.snapshot()
            } else { await estimateQueue?.setSuspended(false) }
            throw error
        }
    }

    private func backups() async throws -> DirectoryBackup {
        if let directoryBackup { return directoryBackup }
        let cache = try FileManager.default.url(for:.cachesDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("BojiBackupStaging")
        let value = DirectoryBackup(repository:try await activeRepository(),cache:cache,clock:dependencies.clock)
        directoryBackup = value;return value
    }
    func connectBackup(_ url:URL) async {
        guard !isDemo,!isLoading,!backupBusy else { return };backupBusy = true;defer { backupBusy = false }
        do { try await backups().connect(url);try await refresh();backupError = nil;await processBackup(immediate:true) }
        catch { backupError = error.localizedDescription }
    }
    func disconnectBackup() async {
        guard !isDemo,!isLoading,!backupBusy else { return };backupBusy = true;defer { backupBusy = false }
        do { try await backups().disconnect();try await refresh();backupError = nil }
        catch { backupError = error.localizedDescription }
    }
    func backupNow() async {
        guard !backupBusy else { return };backupBusy = true;defer { backupBusy = false }
        await processBackup(immediate:true)
    }
    func resumeBackup() async {
        guard !isDemo,!isLoading,session != nil else { return }
        do { try await backups().resume() } catch { backupError = error.localizedDescription }
    }
    func processBackup(immediate:Bool=false) async {
        guard !isDemo,!isLoading,session != nil else { return }
        do {
            let coordinator = try await backups();await coordinator.run(immediate:immediate)
            try await refresh()
        } catch { backupError = error.localizedDescription }
    }

    func trash(kind: RecordKind, id: UUID) async {
        await perform { repository in
            try await repository.moveToTrash(kind: kind, id: id, at: self.dependencies.clock.now, operationID: UUID())
        }
    }

    func activeRepository() async throws -> LocalRepository {
        guard let session else { throw DomainError.notConfigured }
        return await session.activeRepository()
    }

    func refresh() async throws {
        let repository = try await activeRepository()
        try await repository.expireTrash(at: dependencies.clock.now)
        snapshot = try await repository.snapshot()
    }

    func confirm(_ day: LocalDay, value: Bool) async {
        await perform { repository in
            try await repository.confirmDay(day, confirmed: value, at: self.dependencies.clock.now, operationID: UUID())
        }
    }

    func connectAI(urlText: String, token: String) async -> Bool {
        guard !isDemo else { return false }
        do {
            guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ServiceFailure("https_required") }
            try ServiceClient.validateURL(url)
            if !token.isEmpty {
                try await dependencies.credentials.setToken(token, for: url)
                try await activeRepository().revokeEstimationConsent()
            }
            guard try await dependencies.credentials.token(for: url) != nil else { throw ServiceFailure("unauthorized") }
            let policy = try await dependencies.remote.policy(url: url)
            try await activeRepository().configureEstimation(url: url, policy: policy)
            try await refresh(); aiError = nil; return true
        } catch { aiError = error.estimationMessage; return false }
    }
    func acceptAI() async {
        guard let policy = snapshot?.aiSettings.cachedPolicy else { return }
        await aiOperation { try await $0.acceptEstimationPolicy(policy.version) }
    }
    func revokeAI() async { await aiOperation { try await $0.revokeEstimationConsent() }; await processEstimation() }
    func setAutomaticAI(_ value: Bool) async { await aiOperation { try await $0.setAutomaticEstimation(value) } }
    func disconnectAI() async {
        let url = snapshot?.aiSettings.serviceURL
        await revokeAI()
        await aiOperation { try await $0.configureEstimation(url: nil, policy: nil) }
        if let url { do { try await dependencies.credentials.setToken(nil, for: url) } catch { aiError = error.estimationMessage } }
    }
    func requestEstimate(recordID: UUID, draftID: UUID? = nil, automatic: Bool = false, retryOf: String? = nil) async {
        guard !isDemo else { return }
        if automatic, snapshot?.aiSettings.automatic != true || snapshot?.aiSettings.acceptedPolicy == nil { return }
        do {
            let repository = try await activeRepository()
            if automatic, !(try await repository.snapshot().activeMeals.first { $0.id == recordID }?.photoIDs.isEmpty == false) { return }
            try await repository.enqueueEstimate(recordID: recordID, draftID: draftID, automatic: automatic, at: dependencies.clock.now, retryOf: retryOf)
            try await refresh(); aiError = nil
        } catch { aiError = error.estimationMessage }
    }
    func cancelEstimate(_ id: UUID) async { await aiOperation { try await $0.cancelEstimate(id: id) }; await processEstimation() }
    func processEstimation() async {
        guard !isDemo, let estimateQueue, session != nil,
              snapshot?.jobs.contains(where: { !$0.status.isTerminal || $0.remoteCancellationPending == true }) == true else { return }
        await estimateQueue.runOnce(networkAvailable: network.isOnline)
        do {
            try await refresh()
            if await estimateQueue.storageFailed { aiError = "识别任务状态未能保存，原始记录仍在。请稍后重试。" }
        } catch { aiError = error.estimationMessage }
    }
    private func aiOperation(_ action: (LocalRepository) async throws -> Void) async {
        guard !isDemo else { return }
        do { try await action(activeRepository()); try await refresh(); aiError = nil }
        catch { aiError = error.estimationMessage }
    }

    func restore(kind: RecordKind, id: UUID) async {
        await perform { repository in
            try await repository.restore(kind: kind, id: id, at: self.dependencies.clock.now, operationID: UUID())
        }
    }

    func purge(kind: RecordKind, id: UUID) async {
        await perform { repository in
            try await repository.permanentlyDelete(kind: kind, id: id, confirmed: true, at: self.dependencies.clock.now, operationID: UUID())
        }
    }

    private func perform(_ operation: (LocalRepository) async throws -> Void) async {
        guard let session else { return }
        do {
            let repository = await session.activeRepository()
            try await operation(repository)
            snapshot = try await repository.snapshot(); errorMessage = nil
        } catch { errorMessage = "操作未保存，原资料仍在。请重试。" }
    }
}
