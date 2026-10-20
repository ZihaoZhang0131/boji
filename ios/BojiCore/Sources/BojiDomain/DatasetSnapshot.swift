import Foundation

public struct DatasetSnapshot: Codable, Equatable, Sendable {
    public var dataset: Dataset
    public var meals: [Meal] = []
    public var workouts: [Workout] = []
    public var photos: [PhotoAsset] = []
    public var drafts: [RecordDraft] = []
    public var profiles: [ProfileVersion] = []
    public var goals: [GoalStage] = []
    public var estimates: [EstimateRevision] = []
    public var jobs: [EstimateJob] = []
    public var confirmations: [DayConfirmation] = []
    public var tombstones: [DeletionTombstone] = []
    public var importOrigins: [EntityOrigin] = []
    public var aiSettings = AISettings()
    public var backup = BackupState()
    public init(dataset: Dataset = Dataset()) { self.dataset = dataset }

    public var referencedPhotoIDs: Set<UUID> {
        Set(meals.flatMap(\.photoIDs) + drafts.flatMap { $0.content.photoIDs } + jobs.filter { !$0.status.isTerminal }.flatMap(\.photoIDs))
    }
    public var activeMeals: [Meal] { meals.filter { $0.deletedAt == nil && !$0.isDemo } }
    public var activeWorkouts: [Workout] { workouts.filter { $0.deletedAt == nil && !$0.isDemo } }

    public func validateIdentityAndReferences() throws {
        guard dataset.schemaVersion == 1 else { throw DomainError.unsupportedSchema(dataset.schemaVersion) }
        func unique<T: Hashable>(_ ids: [T]) throws {
            guard ids.count == Set(ids).count else { throw DomainError.invalidValue("重复标识") }
        }
        try unique(meals.map(\.id)); try unique(workouts.map(\.id)); try unique(photos.map(\.id))
        try unique(drafts.map(\.id)); try unique(profiles.map(\.id)); try unique(goals.map(\.id))
        try unique(estimates.map(\.id)); try unique(jobs.map(\.id)); try unique(confirmations.map(\.id)); try unique(tombstones.map(\.id))
        try unique(importOrigins.map(\.id))
        guard drafts.filter({ $0.content.kind == .workout }).count <= 1 else { throw DomainError.conflict }
        let photoIDs = Set(photos.map(\.id))
        for id in referencedPhotoIDs where !photoIDs.contains(id) { throw DomainError.missingPhoto(id) }
        let mealIDs = Set(meals.map(\.id) + drafts.compactMap { if case .meal(let value) = $0.content { value.id } else { nil } })
        for revision in estimates where !mealIDs.contains(revision.recordID) { throw DomainError.corruptStore }
        for meal in meals {
            try unique(meal.photoIDs)
            guard meal.photoIDs.count <= 9 else { throw DomainError.invalidValue("每餐最多九张照片") }
            if let id = meal.currentEstimateID, !estimates.contains(where: { $0.id == id && $0.recordID == meal.id }) { throw DomainError.corruptStore }
        }
        for workout in workouts {
            try unique(workout.exercises.map(\.id)); try unique(workout.exercises.flatMap { $0.sets.map(\.id) })
            try unique(workout.energyHistory.map(\.id))
            if let id = workout.currentEnergyID, !workout.energyHistory.contains(where: { $0.id == id }) { throw DomainError.corruptStore }
        }
    }

    public func sourceIdentity(kind: String, id: UUID) -> SourceIdentity {
        importOrigins.first { $0.kind == kind && $0.localID == id }?.source ?? SourceIdentity(datasetID: dataset.id, entityID: id, kind: kind)
    }

    public mutating func invalidateConfirmation(on days: Set<LocalDay>) {
        confirmations.removeAll { days.contains($0.day) }
    }
}
