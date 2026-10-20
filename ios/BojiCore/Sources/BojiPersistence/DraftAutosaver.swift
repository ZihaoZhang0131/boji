import Foundation
import BojiDomain

public enum DraftSaveStatus: Equatable, Sendable {
    case idle, saving, saved(Date), failed(String)
}

public actor DraftAutosaver {
    private let repository: LocalRepository
    private let clock: any AppClock
    private var scheduled: Task<Void, Never>?
    private var pending: (draft: RecordDraft, photos: [PhotoAsset], operation: UUID)?
    private var generation: Int64 = 0
    private var latestInputRevision: Int64 = -1
    public private(set) var status: DraftSaveStatus = .idle

    public init(repository: LocalRepository, clock: any AppClock) { self.repository = repository; self.clock = clock }
    deinit { scheduled?.cancel() }

    public func changed(_ input: RecordDraft, photos: [PhotoAsset] = []) {
        guard input.revision >= latestInputRevision else { return }
        latestInputRevision = input.revision
        generation = max(generation, input.revision) + 1
        var draft = input; draft.revision = generation; draft.savedAt = clock.now
        pending = (draft, photos, UUID()); status = .saving
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try await self?.flush()
            } catch { /* flush exposes failures via status and retains pending values. */ }
        }
    }

    public func flush() async throws {
        scheduled?.cancel(); scheduled = nil
        guard let pending else { return }
        do {
            try await repository.saveDraft(pending.draft, photos: pending.photos, operationID: pending.operation)
            if generation == pending.draft.revision {
                self.pending = nil; status = .saved(pending.draft.savedAt)
            }
        } catch {
            if generation == pending.draft.revision { status = .failed("草稿未保存，请重试。当前输入仍保留。") }
            throw error
        }
    }

    public func discard(draftID: UUID) async throws {
        scheduled?.cancel(); scheduled = nil
        generation += 1
        // A persistent draft tombstone rejects writes already in flight, even if they arrive later.
        try await repository.discardDraft(id: draftID, at: clock.now, operationID: UUID())
        pending = nil; status = .idle
    }
}
