import Foundation
import BojiDomain

extension LocalRepository {
    public func saveDraft(_ draft: RecordDraft, photos: [PhotoAsset] = [], operationID: UUID) throws {
        try commit(id: operationID) { state in
            guard !state.tombstones.contains(where: { $0.source == state.sourceIdentity(kind: "draft", id: draft.id) }) else { throw DomainError.conflict }
            if let target = draft.editingRecordID {
                switch draft.content {
                case .meal(let value):
                    guard let original = state.meals.first(where: { $0.id == target }), original.deletedAt == nil,
                          original.lifecycleEpoch == value.lifecycleEpoch else { throw DomainError.conflict }
                case .workout(let value):
                    guard let original = state.workouts.first(where: { $0.id == target }), original.deletedAt == nil,
                          original.lifecycleEpoch == value.lifecycleEpoch else { throw DomainError.conflict }
                }
            }
            if draft.content.kind == .workout, state.drafts.contains(where: { $0.content.kind == .workout && $0.id != draft.id }) { throw DomainError.conflict }
            if let index = state.drafts.firstIndex(where: { $0.id == draft.id }) {
                guard draft.revision > state.drafts[index].revision || draft == state.drafts[index] else { throw DomainError.conflict }
                var merged = draft
                if case .meal(var incoming) = draft.content, case .meal(let stored) = state.drafts[index].content,
                   incoming.inputRevision == stored.inputRevision, incoming.lifecycleEpoch == stored.lifecycleEpoch,
                   stored.manualRevision >= incoming.manualRevision, stored.currentEstimateID != nil {
                    incoming.currentEstimateID = stored.currentEstimateID; incoming.manualRevision = stored.manualRevision
                    merged.content = .meal(incoming)
                }
                state.drafts[index] = merged
            } else { state.drafts.append(draft) }
            for photo in photos {
                if let existing = state.photos.first(where: { $0.id == photo.id }) {
                    guard existing == photo else { throw DomainError.conflict }
                } else { state.photos.append(photo) }
            }
        }
    }

    public func discardDraft(id: UUID, at now: Date = Date(), operationID: UUID) throws {
        try commit(id: operationID) { state in
            let tombstone = DeletionTombstone(source: state.sourceIdentity(kind: "draft", id: id), deletedAt: now)
            if !state.tombstones.contains(where: { $0.id == tombstone.id }) { state.tombstones.append(tombstone) }
            guard let draft = state.drafts.first(where: { $0.id == id }) else { return }
            let recordID = draft.content.recordID
            state.drafts.removeAll { $0.id == id }
            for index in state.jobs.indices where state.jobs[index].recordID == recordID { EstimationRules.cancel(&state.jobs[index], code: "draft_discarded") }
            if let index = state.meals.firstIndex(where: { $0.id == recordID }) {
                state.meals[index].lifecycleEpoch += 1
            } else if draft.content.kind == .meal { state.estimates.removeAll { $0.recordID == recordID } }
        }
    }

    public func moveToTrash(kind: RecordKind, id: UUID, at now: Date, operationID: UUID) throws {
        try commit(id: operationID) { state in
            var day: LocalDay?
            switch kind {
            case .meal:
                guard let index = state.meals.firstIndex(where: { $0.id == id }), state.meals[index].deletedAt == nil else { return }
                day = state.meals[index].time.localDay
                state.meals[index].deletedAt = now; state.meals[index].lifecycleEpoch += 1
            case .workout:
                guard let index = state.workouts.firstIndex(where: { $0.id == id }), state.workouts[index].deletedAt == nil else { return }
                day = state.workouts[index].time.localDay
                state.workouts[index].deletedAt = now; state.workouts[index].lifecycleEpoch += 1
            }
            let removed = state.drafts.filter { $0.editingRecordID == id && $0.content.kind == kind }
            for draft in removed {
                state.tombstones.append(DeletionTombstone(source: state.sourceIdentity(kind: "draft", id: draft.id), deletedAt: now))
            }
            state.drafts.removeAll { $0.editingRecordID == id && $0.content.kind == kind }
            if kind == .meal {
                for index in state.jobs.indices where state.jobs[index].recordID == id { EstimationRules.cancel(&state.jobs[index], code: "record_deleted") }
            }
            if let day { state.invalidateConfirmation(on: [day]) }
        }
    }

    public func restore(kind: RecordKind, id: UUID, at now: Date, operationID: UUID) throws {
        try commit(id: operationID) { state in
            var day: LocalDay?
            switch kind {
            case .meal:
                guard let index = state.meals.firstIndex(where: { $0.id == id }), let deleted = state.meals[index].deletedAt else { return }
                guard now.timeIntervalSince(deleted) < Self.trashRetention else { throw DomainError.invalidValue("恢复期限已过") }
                state.meals[index].deletedAt = nil; state.meals[index].lifecycleEpoch += 1; day = state.meals[index].time.localDay
            case .workout:
                guard let index = state.workouts.firstIndex(where: { $0.id == id }), let deleted = state.workouts[index].deletedAt else { return }
                guard now.timeIntervalSince(deleted) < Self.trashRetention else { throw DomainError.invalidValue("恢复期限已过") }
                state.workouts[index].deletedAt = nil; state.workouts[index].lifecycleEpoch += 1; day = state.workouts[index].time.localDay
            }
            if let day { state.invalidateConfirmation(on: [day]) }
        }
    }

    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    public func permanentlyDelete(kind: RecordKind, id: UUID, confirmed: Bool, at now: Date, operationID: UUID) throws {
        guard confirmed else { throw DomainError.invalidValue("请先确认永久删除") }
        try commit(id: operationID) { state in try Self.purge(kind: kind, id: id, at: now, from: &state) }
        try? collectOrphanPhotos()
    }

    public func expireTrash(at now: Date) throws {
        let state = try snapshot()
        let meals = state.meals.filter { $0.deletedAt.map { now.timeIntervalSince($0) >= Self.trashRetention } ?? false }.map(\.id)
        let workouts = state.workouts.filter { $0.deletedAt.map { now.timeIntervalSince($0) >= Self.trashRetention } ?? false }.map(\.id)
        guard !meals.isEmpty || !workouts.isEmpty else { return }
        try commit(id: UUID()) { state in
            for id in meals { try Self.purge(kind: .meal, id: id, at: now, from: &state) }
            for id in workouts { try Self.purge(kind: .workout, id: id, at: now, from: &state) }
        }
        try? collectOrphanPhotos()
    }

    private static func purge(kind: RecordKind, id: UUID, at now: Date, from state: inout DatasetSnapshot) throws {
        var source: SourceIdentity?
        switch kind {
        case .meal:
            guard let value = state.meals.first(where: { $0.id == id }) else { return }
            guard value.deletedAt != nil else { throw DomainError.invalidValue("仅可永久删除回收站中的记录") }
            source = value.source
            state.meals.removeAll { $0.id == id }; state.estimates.removeAll { $0.recordID == id }
        case .workout:
            guard let value = state.workouts.first(where: { $0.id == id }) else { return }
            guard value.deletedAt != nil else { throw DomainError.invalidValue("仅可永久删除回收站中的记录") }
            source = value.source; state.workouts.removeAll { $0.id == id }
        }
        let identity = source ?? SourceIdentity(datasetID: state.dataset.id, entityID: id, kind: kind.rawValue)
        let tombstone = DeletionTombstone(source: identity, deletedAt: now)
        if !state.tombstones.contains(where: { $0.id == tombstone.id }) { state.tombstones.append(tombstone) }
        state.drafts.removeAll { $0.content.recordID == id }
        if kind == .meal { state.jobs.removeAll { $0.recordID == id } }
    }
}
