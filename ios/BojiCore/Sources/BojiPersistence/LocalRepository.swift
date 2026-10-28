import Foundation
import SwiftData
import BojiDomain

public enum CommitPoint: Sendable { case afterChangesStaged, beforeSave }
public typealias CommitFault = @Sendable (CommitPoint) throws -> Void
public struct CommitResult: Equatable, Sendable {
    public let revision: Int64
    public let alreadyCommitted: Bool
}

@ModelActor
public actor LocalRepository: RecordRepository {
    private var fault: CommitFault = { _ in }
    private var leases: [UUID: Set<UUID>] = [:]
    private var leasedAssets: [UUID: [PhotoAsset]] = [:]
    private var pendingAssets: [UUID: PhotoAsset] = [:]
    private var media: MediaVault?
    private var maintenance = false

    public static func open(at directory: URL, mode: DatasetMode = .personal, inMemory: Bool = false, fault: @escaping CommitFault = { _ in }) async throws -> LocalRepository {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        let container = try await StoreContainerFactory.shared.make(directory: directory, inMemory: inMemory)
        let repository = LocalRepository(modelContainer: container)
        try await repository.prepare(mode: mode, fault: fault, media: MediaVault(root: directory))
        return repository
    }

    private func prepare(mode: DatasetMode, fault: @escaping CommitFault, media: MediaVault) throws {
        modelContext.autosaveEnabled = false
        self.fault = fault
        self.media = media
        let metadata = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Metadata>())
        guard metadata.count <= 1 else { throw DomainError.corruptStore }
        if metadata.isEmpty {
            guard try modelContext.fetchCount(FetchDescriptor<StoreSchemaV1.Entity>()) == 0,
                  try modelContext.fetchCount(FetchDescriptor<StoreSchemaV1.Receipt>()) == 0 else { throw DomainError.corruptStore }
            let initial = DatasetSnapshot(dataset: Dataset(mode: mode))
            modelContext.insert(try metadataRow(initial))
            do { try modelContext.save() } catch { modelContext.rollback(); throw error }
        }
        let state = try snapshot()
        guard state.dataset.mode == mode else { throw DomainError.conflict }
        try collectOrphanPhotos()
    }

    public func snapshot() throws -> DatasetSnapshot {
        guard let metadata = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Metadata>()).first else { throw DomainError.corruptStore }
        let decoder = JSONDecoder()
        var snapshot = DatasetSnapshot(dataset: try decoder.decode(Dataset.self, from: metadata.payload))
        snapshot.aiSettings = try decoder.decode(AISettings.self, from: metadata.aiSettings)
        snapshot.backup = try decoder.decode(BackupState.self, from: metadata.backup)
        let rows = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Entity>(sortBy: [SortDescriptor(\.key)]))
        for row in rows {
            switch row.kind {
            case "meal": snapshot.meals.append(try decoder.decode(Meal.self, from: row.payload))
            case "workout": snapshot.workouts.append(try decoder.decode(Workout.self, from: row.payload))
            case "photo": snapshot.photos.append(try decoder.decode(PhotoAsset.self, from: row.payload))
            case "draft": snapshot.drafts.append(try decoder.decode(RecordDraft.self, from: row.payload))
            case "profile": snapshot.profiles.append(try decoder.decode(ProfileVersion.self, from: row.payload))
            case "goal": snapshot.goals.append(try decoder.decode(GoalStage.self, from: row.payload))
            case "estimate": snapshot.estimates.append(try decoder.decode(EstimateRevision.self, from: row.payload))
            case "job": snapshot.jobs.append(try decoder.decode(EstimateJob.self, from: row.payload))
            case "confirmation": snapshot.confirmations.append(try decoder.decode(DayConfirmation.self, from: row.payload))
            case "tombstone": snapshot.tombstones.append(try decoder.decode(DeletionTombstone.self, from: row.payload))
            case "origin": snapshot.importOrigins.append(try decoder.decode(EntityOrigin.self, from: row.payload))
            default: throw DomainError.corruptStore
            }
        }
        try snapshot.validateIdentityAndReferences()
        return snapshot
    }

    /// The closure operates on detached values. No await occurs between reading and committing.
    /// A caller keeps the same operation ID when retrying a failed/unknown submission.
    @discardableResult
    public func commit(id: UUID, expectedRevision: Int64? = nil, _ change: @Sendable (inout DatasetSnapshot) throws -> Void) throws -> CommitResult {
        guard !maintenance else { throw DomainError.invalidValue("资料维护中，请稍后重试") }
        let receipts = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Receipt>(predicate: #Predicate { $0.id == id }))
        if let receipt = receipts.first { return CommitResult(revision: receipt.revision, alreadyCommitted: true) }
        let current = try snapshot()
        var next = current
        if let expectedRevision, next.dataset.revision != expectedRevision { throw DomainError.conflict }
        let originalDataset = next.dataset
        try change(&next)
        guard next.dataset == originalDataset else { throw DomainError.invalidValue("不可修改资料集身份或修订号") }
        next.dataset.revision += 1
        next.backup.dirty = true
        if next.backup.directoryBookmark != nil { next.backup.status = .dirty }
        try next.validateIdentityAndReferences()
        guard let media else { throw DomainError.corruptStore }
        let previousAssets = Dictionary(uniqueKeysWithValues: current.photos.map { ($0.id, $0) })
        let previousReferences = current.referencedPhotoIDs
        for photo in next.photos where next.referencedPhotoIDs.contains(photo.id) &&
            (!previousReferences.contains(photo.id) || previousAssets[photo.id] != photo) { _ = try media.read(photo) }
        do {
            try stage(next)
            try fault(.afterChangesStaged)
            modelContext.insert(StoreSchemaV1.Receipt(id: id, revision: next.dataset.revision))
            try fault(.beforeSave)
            try modelContext.save()
            for id in next.referencedPhotoIDs { pendingAssets.removeValue(forKey: id) }
            return CommitResult(revision: next.dataset.revision, alreadyCommitted: false)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func recordBackupPublication(pointerRevision:Int64,digest:String,at now:Date,expectedBookmark:Data) throws {
        let revision=try snapshot().dataset.revision
        try updateBackup(expectedBookmark:expectedBookmark) {
            $0.lastPublishedRevision=pointerRevision;$0.pointerSHA256=digest;$0.lastWrittenAt=now
            $0.lastUploadStatus = .unknown
            $0.activeExportID=nil;$0.activePointerSHA256=nil;$0.dirty=revision>pointerRevision
            $0.status = $0.dirty ? .dirty : .written;$0.lastError=nil;$0.retryCount=0;$0.nextRetryAt=nil
        }
    }

    /// Operational backup metadata is durable but does not create another dirty content revision.
    public func updateBackup(expectedBookmark: Data?, _ change: @Sendable (inout BackupState) throws -> Void) throws {
        guard !maintenance else { throw DomainError.conflict }
        let state = try snapshot()
        guard state.backup.directoryBookmark == expectedBookmark,
              let metadata = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Metadata>()).first else { throw DomainError.conflict }
        var backup = state.backup;try change(&backup)
        do {
            metadata.backup = try JSONEncoder().encode(backup)
            try fault(.beforeSave);try modelContext.save()
        } catch { modelContext.rollback();throw error }
    }

    private func metadataRow(_ snapshot: DatasetSnapshot) throws -> StoreSchemaV1.Metadata {
        let encoder = JSONEncoder()
        return try StoreSchemaV1.Metadata(payload: encoder.encode(snapshot.dataset), aiSettings: encoder.encode(snapshot.aiSettings), backup: encoder.encode(snapshot.backup))
    }

    private func stage(_ snapshot: DatasetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var desired: [String: (String, Data)] = [:]
        func add<T: Encodable & Identifiable>(_ values: [T], kind: String) throws {
            for value in values { desired["\(kind)/\(value.id)"] = (kind, try encoder.encode(value)) }
        }
        try add(snapshot.meals, kind: "meal"); try add(snapshot.workouts, kind: "workout")
        try add(snapshot.photos, kind: "photo"); try add(snapshot.drafts, kind: "draft")
        try add(snapshot.profiles, kind: "profile"); try add(snapshot.goals, kind: "goal")
        try add(snapshot.estimates, kind: "estimate"); try add(snapshot.jobs, kind: "job")
        try add(snapshot.confirmations, kind: "confirmation"); try add(snapshot.tombstones, kind: "tombstone")
        try add(snapshot.importOrigins, kind: "origin")
        for row in try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Entity>()) {
            if let entry = desired.removeValue(forKey: row.key) {
                if row.payload != entry.1 { row.payload = entry.1 }
            } else { modelContext.delete(row) }
        }
        for (key, entry) in desired { modelContext.insert(StoreSchemaV1.Entity(key: key, kind: entry.0, payload: entry.1)) }
        guard let metadata = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Metadata>()).first else { throw DomainError.corruptStore }
        metadata.payload = try encoder.encode(snapshot.dataset)
        metadata.aiSettings = try encoder.encode(snapshot.aiSettings)
        metadata.backup = try encoder.encode(snapshot.backup)
    }

    public func acquireSnapshot() throws -> SnapshotLease {
        let value = try snapshot()
        let lease = SnapshotLease(id: UUID(), value: value)
        leases[lease.id] = value.referencedPhotoIDs
        leasedAssets[lease.id] = value.photos.filter { value.referencedPhotoIDs.contains($0.id) }
        return lease
    }

    public func releaseSnapshot(_ leaseID: UUID) { leases.removeValue(forKey: leaseID); leasedAssets.removeValue(forKey: leaseID) }

    public func protectedPhotoIDs() throws -> Set<UUID> {
        try snapshot().referencedPhotoIDs.union(leases.values.flatMap { $0 }).union(pendingAssets.keys)
    }

    public func preparePhoto(_ data: Data) throws -> PhotoAsset {
        guard let media else { throw DomainError.corruptStore }
        let asset = try media.ingest(data)
        pendingAssets[asset.id] = asset
        return asset
    }

    public func readPhoto(_ asset: PhotoAsset) throws -> Data {
        guard let media else { throw DomainError.corruptStore }
        return try media.read(asset)
    }

    public func thumbnail(_ asset: PhotoAsset) throws -> Data {
        guard let media else { throw DomainError.corruptStore }
        return try media.thumbnail(asset)
    }

    public func releasePreparedPhoto(_ id: UUID) { pendingAssets.removeValue(forKey: id) }

    public func collectOrphanPhotos() throws {
        guard let media else { throw DomainError.corruptStore }
        let state = try snapshot()
        let references = state.photos.filter { state.referencedPhotoIDs.contains($0.id) }
        let assets = references + leasedAssets.values.flatMap { $0 } + Array(pendingAssets.values)
        try media.collectOrphans(keeping: Set(assets.map(\.relativePath)))
    }

    public func beginMaintenance() throws -> RecoverySnapshot {
        guard !maintenance else { throw DomainError.conflict }
        let lease = try acquireSnapshot()
        let receipts = try modelContext.fetch(FetchDescriptor<StoreSchemaV1.Receipt>()).map { CommitReceipt(id: $0.id, revision: $0.revision) }
        maintenance = true
        return RecoverySnapshot(lease: lease, receipts: receipts)
    }

    public func endMaintenance(leaseID: UUID) { releaseSnapshot(leaseID); maintenance = false }

    public func initializeRecovery(_ value: DatasetSnapshot, receipts: [CommitReceipt]) throws {
        let current = try snapshot()
        guard current.dataset.revision == 0,
              try modelContext.fetchCount(FetchDescriptor<StoreSchemaV1.Entity>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<StoreSchemaV1.Receipt>()) == 0,
              let media else { throw DomainError.conflict }
        try value.validateIdentityAndReferences()
        for photo in value.photos where value.referencedPhotoIDs.contains(photo.id) { _ = try media.read(photo) }
        do {
            try stage(value)
            for receipt in receipts { modelContext.insert(StoreSchemaV1.Receipt(id: receipt.id, revision: receipt.revision)) }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }
}

// Core Data shares derived schema metadata between containers. Serialize container construction
// (including migration) while keeping each repository's reads and commits on its own model actor.
private actor StoreContainerFactory {
    static let shared = StoreContainerFactory()
    func make(directory: URL, inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: StoreSchemaV1.self)
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, url: directory.appendingPathComponent("records.store"), cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: StoreMigrationPlan.self, configurations: [configuration])
    }
}

public struct SnapshotLease: Sendable {
    public let id: UUID
    public let value: DatasetSnapshot
}

public struct CommitReceipt: Codable, Equatable, Sendable {
    public let id: UUID
    public let revision: Int64
}

public struct RecoverySnapshot: Sendable {
    public let lease: SnapshotLease
    public let receipts: [CommitReceipt]
}
