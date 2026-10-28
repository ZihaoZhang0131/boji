import Foundation
import BojiDomain

public enum MigrationPoint: Sendable, CaseIterable { case afterSnapshot, afterShadowReady, beforeActivation, afterActivation }

/// Activates complete database generations through a small atomically written pointer.
/// A source database is never copied while its SQLite/WAL files are live.
public actor ManagedStore {
    public let root: URL
    private let files: any FileAccess
    private var repository: LocalRepository?
    private var opening = false
    private var upgrading = false
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct Pointer: Codable, Equatable {
        var generation: UUID
        var schemaVersion = 1
    }
    private struct Journal: Codable { var previous: Pointer; var candidate: Pointer }
    private struct Ready: Codable { var datasetID: UUID; var revision: Int64; var schemaVersion: Int }

    public init(root: URL, files: any FileAccess = LocalFileAccess()) { self.root = root; self.files = files }

    public func open() async throws -> LocalRepository {
        if let repository { return repository }
        guard !opening else { throw DomainError.conflict }
        opening = true
        defer { opening = false }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let active: Pointer
        if exists("active.json") {
            active = try decoder.decode(Pointer.self, from: files.read(path("active.json")))
            try validate(active)
        } else {
            if exists("bootstrap.json") {
                active = try decoder.decode(Pointer.self, from: files.read(path("bootstrap.json")))
            } else {
                // An absent pointer with existing user stores is damage, not a new installation.
                let stores = path("stores")
                if FileManager.default.fileExists(atPath: stores.path), !(try FileManager.default.contentsOfDirectory(atPath: stores.path)).isEmpty { throw DomainError.corruptStore }
                guard !exists("records.store") else { throw DomainError.invalidValue("检测到旧布局资料，请先进行显式迁移") }
                active = Pointer(generation: UUID())
                try files.writeAtomically(encoder.encode(active), to: path("bootstrap.json"))
            }
            guard active.schemaVersion == 1 else { throw DomainError.unsupportedSchema(active.schemaVersion) }
            let initial = try await LocalRepository.open(at: directory(active))
            try await writeReady(initial, pointer: active)
            try files.writeAtomically(encoder.encode(active), to: path("active.json"))
            try FileManager.default.removeItem(at: path("bootstrap.json"))
        }
        let opened = try await LocalRepository.open(at: directory(active))
        let value = try await opened.snapshot()
        let ready = try decoder.decode(Ready.self, from: files.read(directory(active).appendingPathComponent("ready.json")))
        guard value.dataset.id == ready.datasetID, value.dataset.schemaVersion == ready.schemaVersion else { throw DomainError.corruptStore }
        if exists("migration.json") {
            let journal = try decoder.decode(Journal.self, from: files.read(path("migration.json")))
            guard journal.previous.generation != journal.candidate.generation else { throw DomainError.corruptStore }
            if active == journal.previous {
                try? FileManager.default.removeItem(at: directory(journal.candidate))
            } else if active != journal.candidate { throw DomainError.conflict }
            try FileManager.default.removeItem(at: path("migration.json"))
        }
        repository = opened
        return opened
    }

    /// The v1 release needs no data transform; this same path validates future known-version
    /// transforms before activation. Unknown versions are rejected before opening SwiftData.
    public func rebuild(fault: @escaping @Sendable (MigrationPoint) throws -> Void = { _ in }, transform: @Sendable (inout DatasetSnapshot) throws -> Void = { _ in }) async throws -> LocalRepository {
        try await rebuildWithMedia(fault: fault, importedMedia: nil, transform: transform)
    }

    public func rebuildWithMedia(fault: @escaping @Sendable (MigrationPoint) throws -> Void = { _ in }, importedMedia: (@Sendable (PhotoAsset) throws -> Data?)?, transform: @Sendable (inout DatasetSnapshot) throws -> Void) async throws -> LocalRepository {
        guard !upgrading else { throw DomainError.conflict }
        upgrading = true
        defer { upgrading = false }
        let source = try await open()
        let pointerBytes = try files.read(path("active.json"))
        let previous = try decoder.decode(Pointer.self, from: pointerBytes)
        try validate(previous)
        let candidate = Pointer(generation: UUID())
        let recovery = try await source.beginMaintenance()
        var activated = false
        do {
            try files.writeAtomically(encoder.encode(Journal(previous: previous, candidate: candidate)), to: path("migration.json"))
            try fault(.afterSnapshot)
            var value = recovery.lease.value
            try transform(&value)
            guard value.dataset == recovery.lease.value.dataset else { throw DomainError.invalidValue("迁移不能替换资料集身份") }
            value.dataset.revision += 1; value.backup.dirty = true
            try value.validateIdentityAndReferences()
            let shadow = try await LocalRepository.open(at: directory(candidate))
            let destination = MediaVault(root: directory(candidate))
            try FileManager.default.createDirectory(at: directory(candidate).appendingPathComponent("media"), withIntermediateDirectories: true)
            for asset in value.photos where value.referencedPhotoIDs.contains(asset.id) {
                let data: Data
                if let imported = try importedMedia?(asset) { data = imported }
                else { data = try await source.readPhoto(asset) }
                try files.writeAtomically(data, to: destination.url(for: asset))
            }
            try await shadow.initializeRecovery(value, receipts: recovery.receipts)
            let restored = try await shadow.snapshot()
            guard restored.dataset == value.dataset else { throw DomainError.corruptStore }
            try await writeReady(shadow, pointer: candidate)
            try fault(.afterShadowReady)
            guard try files.read(path("active.json")) == pointerBytes else { throw DomainError.conflict }
            try files.writeAtomically(pointerBytes, to: path("previous.json"))
            try fault(.beforeActivation)
            try files.writeAtomically(encoder.encode(candidate), to: path("active.json"))
            activated = true; repository = shadow
            try fault(.afterActivation)
            try FileManager.default.removeItem(at: path("migration.json"))
            // The obsolete source stays read-only for any callers still holding it.
            await source.releaseSnapshot(recovery.lease.id)
            return shadow
        } catch {
            if !activated { await source.endMaintenance(leaseID: recovery.lease.id) }
            else { await source.releaseSnapshot(recovery.lease.id) }
            throw error
        }
    }

    public func restorePrevious() async throws -> LocalRepository {
        guard !upgrading else { throw DomainError.conflict }
        upgrading = true
        defer { upgrading = false }
        guard exists("previous.json") else { throw DomainError.invalidValue("没有可恢复的升级前资料") }
        let previousBytes = try files.read(path("previous.json"))
        let previous = try decoder.decode(Pointer.self, from: previousBytes)
        try validate(previous)
        let restored = try await LocalRepository.open(at: directory(previous))
        _ = try await restored.snapshot()
        let current = try files.read(path("active.json"))
        // Freeze old writers before replacing the pointer. Recovery is an explicit user action.
        let oldRepository = try await open()
        let recovery = try await oldRepository.beginMaintenance()
        do {
            let localBackup = recovery.lease.value.backup
            let previousBackup = try await restored.snapshot().backup
            try await restored.updateBackup(expectedBookmark: previousBackup.directoryBookmark) {
                $0 = localBackup; $0.dirty = true
                if $0.directoryBookmark != nil { $0.status = .dirty }
            }
            try files.writeAtomically(previousBytes, to: path("active.json"))
        } catch {
            await oldRepository.endMaintenance(leaseID: recovery.lease.id)
            throw error
        }
        repository = restored
        await oldRepository.releaseSnapshot(recovery.lease.id)
        // Once activation succeeded, failures in optional housekeeping do not undo recovery.
        try? files.writeAtomically(current, to: path("previous.json"))
        if exists("migration.json") { try? FileManager.default.removeItem(at: path("migration.json")) }
        return restored
    }

    private func validate(_ pointer: Pointer) throws {
        guard pointer.schemaVersion == 1 else { throw DomainError.unsupportedSchema(pointer.schemaVersion) }
        let location = directory(pointer)
        guard location.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/stores/"),
              FileManager.default.fileExists(atPath: location.appendingPathComponent("ready.json").path),
              FileManager.default.fileExists(atPath: location.appendingPathComponent("records.store").path) else { throw DomainError.corruptStore }
    }

    private func writeReady(_ store: LocalRepository, pointer: Pointer) async throws {
        let value = try await store.snapshot()
        try files.writeAtomically(encoder.encode(Ready(datasetID: value.dataset.id, revision: value.dataset.revision, schemaVersion: value.dataset.schemaVersion)), to: directory(pointer).appendingPathComponent("ready.json"))
    }
    private func directory(_ pointer: Pointer) -> URL { path("stores/" + pointer.generation.uuidString) }
    private func path(_ component: String) -> URL { root.appendingPathComponent(component) }
    private func exists(_ component: String) -> Bool { FileManager.default.fileExists(atPath: path(component).path) }
}
