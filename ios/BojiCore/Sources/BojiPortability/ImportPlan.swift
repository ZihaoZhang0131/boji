import Foundation
import CryptoKit
import BojiDomain
import BojiPersistence

public enum ImportConflictPolicy: String, CaseIterable, Sendable { case keepLocal, useImported }
public struct ImportConflict: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let restoration: Bool
}
public struct ImportOptions: Sendable {
    public var conflicts: ImportConflictPolicy = .keepLocal
    public var restoreDeleted: Set<String> = []
    public init() {}
}
public struct ImportPlan: Sendable {
    public let baseDatasetID: UUID
    public let baseRevision: Int64
    public let manifest: PackageManifest
    public let result: DatasetSnapshot
    public let conflicts: [ImportConflict]
    public let added: Int
    public let replaced: Int
    public let duplicates: Int
    public let skipped: Int
    public let excludedDemo: Int
    public let notices: [String]
    public let incomingPhotos: [PhotoAsset]
    public var hasChanges: Bool { added + replaced > 0 }
}

public enum ImportPlanner {
    public static func stableID(_ name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16)); bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x",$0) }.joined()
        let parts = [0..<8,8..<12,12..<16,16..<20,20..<32].map { range in String(hex.dropFirst(range.lowerBound).prefix(range.count)) }
        return UUID(uuidString:parts.joined(separator:"-"))!
    }
    public static func plan(package: ValidatedPackage, local: DatasetSnapshot, options: ImportOptions = ImportOptions()) throws -> ImportPlan {
        try ExportPolicy.requirePersonalDataset(local)
        var incoming = package.snapshot, next = local
        let original = incoming
        var origins: [EntityOrigin] = [], cache: [String:UUID] = [:]
        func source(_ kind: String, _ id: UUID, explicit: SourceIdentity? = nil) -> SourceIdentity {
            original.importOrigins.first { $0.kind == kind && $0.localID == id }?.source ?? explicit ?? SourceIdentity(datasetID:original.dataset.id,entityID:id,kind:kind)
        }
        func map(_ kind: String, _ id: UUID, explicit: SourceIdentity? = nil, hash: String? = nil) -> UUID {
            let origin = source(kind,id,explicit:explicit), key = "\(origin.datasetID)/\(kind)/\(origin.entityID)/\(hash ?? "")"
            if let cached = cache[key] { return cached }
            let prior = local.importOrigins.first { $0.source == origin && $0.contentHash == hash }?.localID
            let native = origin.datasetID == local.dataset.id
            let localID: UUID
            if let prior { localID = prior }
            else if native && (kind != "photo" || !local.photos.contains(where: { $0.id == origin.entityID && $0.sha256 != hash })) { localID = origin.entityID }
            else { localID = stableID(key) }
            cache[key] = localID
            origins.append(EntityOrigin(kind:kind,localID:localID,source:origin,contentHash:hash))
            return localID
        }
        // Map top-level objects first so every reference uses the same lineage.
        var mealIDs: [UUID:UUID] = [:], workoutIDs: [UUID:UUID] = [:], profileIDs: [UUID:UUID] = [:], photoIDs: [UUID:UUID] = [:], estimateIDs: [UUID:UUID] = [:]
        for meal in original.meals { mealIDs[meal.id] = map("meal",meal.id,explicit:meal.source) }
        for workout in original.workouts { workoutIDs[workout.id] = map("workout",workout.id,explicit:workout.source) }
        for draft in original.drafts {
            switch draft.content { case .meal(let meal): mealIDs[meal.id] = map("meal",meal.id,explicit:meal.source)
            case .workout(let workout): workoutIDs[workout.id] = map("workout",workout.id,explicit:workout.source) }
        }
        for profile in original.profiles { profileIDs[profile.id] = map("profile",profile.id,explicit:profile.source) }
        for photo in original.photos { photoIDs[photo.id] = map("photo",photo.id,hash:photo.sha256) }
        for estimate in original.estimates { estimateIDs[estimate.id] = map("estimate",estimate.id) }
        for mapping in [mealIDs,workoutIDs,profileIDs,photoIDs,estimateIDs] {
            guard Set(mapping.values).count == mapping.count else { throw PackageError.invalid("同一来源对应多个实体") }
        }
        func mappedMeal(_ value: Meal) -> Meal {
            var meal = value; meal.id = mealIDs[value.id]!
            let origin = source("meal",value.id,explicit:value.source)
            meal.source = origin.datasetID == local.dataset.id && origin.entityID == meal.id ? nil : origin
            meal.photoIDs = value.photoIDs.map { photoIDs[$0]! }; meal.currentEstimateID = value.currentEstimateID.flatMap { estimateIDs[$0] }
            if let id = meal.currentEstimateID, original.estimates.first(where:{estimateIDs[$0.id] == id})?.source == .demo { meal.currentEstimateID = nil }
            return meal
        }
        func mappedWorkout(_ value: Workout) -> Workout {
            var workout = value; workout.id = workoutIDs[value.id]!
            let origin = source("workout",value.id,explicit:value.source)
            workout.source = origin.datasetID == local.dataset.id && origin.entityID == workout.id ? nil : origin
            workout.exercises = value.exercises.map { original in
                var exercise = original; exercise.id = map("exercise",original.id)
                exercise.sets = original.sets.map { original in var set = original;set.id = map("set",original.id);return set };return exercise
            }
            workout.energyHistory = value.energyHistory.map { original in
                var energy = original;energy.id = map("energy",original.id);energy.profileVersionID = original.profileVersionID.flatMap { profileIDs[$0] };return energy
            }
            workout.currentEnergyID = value.currentEnergyID.map { map("energy",$0) };return workout
        }
        incoming.meals = original.meals.map(mappedMeal); incoming.workouts = original.workouts.map(mappedWorkout)
        incoming.photos = original.photos.map { value in var photo = value;photo.id = photoIDs[value.id]!;return photo }
        incoming.profiles = original.profiles.map { value in
            var profile = value;profile.id = profileIDs[value.id]!
            let origin = source("profile",value.id,explicit:value.source);profile.source = origin.datasetID == local.dataset.id && origin.entityID == profile.id ? nil : origin
            if let current = local.profiles.first(where:{$0.id == profile.id}), profile.source != nil { profile.sequence = current.sequence }
            return profile
        }
        incoming.goals = original.goals.map { value in
            var goal = value;goal.id = map("goal",value.id,explicit:value.source)
            let origin = source("goal",value.id,explicit:value.source);goal.source = origin.datasetID == local.dataset.id && origin.entityID == goal.id ? nil : origin
            if let current = local.goals.first(where:{$0.id == goal.id}), goal.source != nil { goal.sequence = current.sequence }
            return goal
        }
        incoming.estimates = original.estimates.map { value in
            var estimate = value;estimate.id = estimateIDs[value.id]!;estimate.recordID = mealIDs[value.recordID]!
            estimate.previousRevisionID = value.previousRevisionID.flatMap { estimateIDs[$0] }
            estimate.items = value.items.map { original in var item = original;item.id = map("food",original.id);return item };return estimate
        }
        incoming.drafts = original.drafts.map { value in
            var draft = value; draft.id = map("draft",value.id)
            switch value.content {
            case .meal(let meal): draft.content = .meal(mappedMeal(meal));draft.editingRecordID = value.editingRecordID.flatMap { mealIDs[$0] }
            case .workout(let workout):
                draft.content = .workout(mappedWorkout(workout));draft.editingRecordID = value.editingRecordID.flatMap { workoutIDs[$0] }
                if var fields = value.workoutFields {
                    fields.weightText = Dictionary(uniqueKeysWithValues: fields.weightText.map { (map("set",$0.key),$0.value) })
                    fields.repsText = Dictionary(uniqueKeysWithValues: fields.repsText.map { (map("set",$0.key),$0.value) });draft.workoutFields = fields
                }
            }
            return draft
        }
        var conflicts: [ImportConflict] = [], added = 0, replaced = 0, duplicates = 0, skipped = 0, excludedDemo = 0, notices: [String] = []
        func equal<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool { try PackageCodec.encode(lhs) == PackageCodec.encode(rhs) }
        func conflict(_ key: String, _ title: String, restore: Bool = false) -> Bool {
            if !conflicts.contains(where:{$0.id == key}) { conflicts.append(ImportConflict(id:key,title:title,restoration:restore)) }
            return restore ? options.restoreDeleted.contains(key) : options.conflicts == .useImported
        }
        func deleted(_ kind: String, _ id: UUID, source: SourceIdentity?) -> Bool {
            let origin = source ?? SourceIdentity(datasetID:local.dataset.id,entityID:id,kind:kind)
            return local.tombstones.contains { $0.source == origin }
        }
        // Same-day profile history is shown as a conflict; dependent records are skipped if its source is unavailable.
        for var profile in incoming.profiles.sorted(by:{($0.effectiveDay,$0.sequence) < ($1.effectiveDay,$1.sequence)}) {
            if let index = next.profiles.firstIndex(where:{$0.id == profile.id}) {
                if try equal(next.profiles[index],profile) { duplicates += 1;continue }
                if conflict("profile/\(profile.id)","身体资料 \(profile.effectiveDay)") { next.profiles[index] = profile;replaced += 1 } else { skipped += 1 }
            } else {
                let sameDay = local.profiles.filter { $0.effectiveDay == profile.effectiveDay }
                if !sameDay.isEmpty {
                    guard conflict("profile/\(profile.id)","同日身体资料 \(profile.effectiveDay)") else { skipped += 1;continue }
                    profile.sequence = max(next.profiles.map(\.sequence).max() ?? 0,profile.sequence) + 1
                }
                next.profiles.append(profile);added += 1
            }
        }
        for var goal in incoming.goals.sorted(by:{($0.startDay,$0.sequence) < ($1.startDay,$1.sequence)}) {
            if let index = next.goals.firstIndex(where:{$0.id == goal.id}) {
                if try equal(next.goals[index],goal) { duplicates += 1;continue }
                if conflict("goal/\(goal.id)","阶段历史 \(goal.startDay)") { next.goals[index] = goal;replaced += 1 } else { skipped += 1 }
            } else {
                let overlapping = local.goals.filter { ($0.endDay == nil || goal.startDay < $0.endDay!) && (goal.endDay == nil || $0.startDay < goal.endDay!) }
                if !overlapping.isEmpty {
                    guard conflict("goal/\(goal.id)","重叠阶段历史 \(goal.startDay)") else { skipped += 1;continue }
                    goal.sequence = max(next.goals.map(\.sequence).max() ?? 0,goal.sequence) + 1
                    for index in next.goals.indices where next.goals[index].startDay <= goal.startDay && (next.goals[index].endDay == nil || next.goals[index].endDay! > goal.startDay) { next.goals[index].endDay = goal.startDay }
                }
                next.goals.append(goal);added += 1
            }
        }
        var adoptedMeals: Set<UUID> = [], acceptedRecords: Set<UUID> = []
        for meal in incoming.meals {
            if meal.isDemo { excludedDemo += 1;continue }
            let key = "meal/\(meal.id)", index = next.meals.firstIndex { $0.id == meal.id }
            let restoring = meal.deletedAt == nil && (index.map { next.meals[$0].deletedAt != nil } ?? false || deleted("meal",meal.id,source:meal.source))
            if restoring && !conflict(key,"恢复已删除餐食 \(meal.time.localDay)",restore:true) { skipped += 1;continue }
            if let index {
                let oldHistory = next.estimates.filter { $0.recordID == meal.id }.sorted { $0.id.uuidString < $1.id.uuidString }
                let newHistory = incoming.estimates.filter { $0.recordID == meal.id }.sorted { $0.id.uuidString < $1.id.uuidString }
                if try equal(next.meals[index],meal), try newHistory.allSatisfy({ item in try oldHistory.first(where: { $0.id == item.id }).map { try equal($0,item) } ?? false }) { duplicates += 1;acceptedRecords.insert(meal.id);continue }
                guard restoring || conflict(key,"餐食内容冲突 \(meal.time.localDay)") else { skipped += 1;continue }
                next.meals[index] = meal;replaced += 1
            } else { next.meals.append(meal);added += 1 }
            adoptedMeals.insert(meal.id);acceptedRecords.insert(meal.id)
            if restoring { let identity = meal.source ?? SourceIdentity(datasetID:local.dataset.id,entityID:meal.id,kind:"meal");next.tombstones.removeAll { $0.source == identity } }
        }
        for workout in incoming.workouts {
            if workout.isDemo { excludedDemo += 1;continue }
            guard workout.energyHistory.allSatisfy({ $0.profileVersionID.map { id in next.profiles.contains { $0.id == id } } ?? true }) else { skipped += 1;notices.append("训练 \(workout.time.localDay) 的身体资料来源冲突未采用，此训练暂不导入。");continue }
            let key = "workout/\(workout.id)", index = next.workouts.firstIndex { $0.id == workout.id }
            let restoring = workout.deletedAt == nil && (index.map { next.workouts[$0].deletedAt != nil } ?? false || deleted("workout",workout.id,source:workout.source))
            if restoring && !conflict(key,"恢复已删除训练 \(workout.time.localDay)",restore:true) { skipped += 1;continue }
            if let index {
                if try equal(next.workouts[index],workout) { duplicates += 1;acceptedRecords.insert(workout.id);continue }
                guard restoring || conflict(key,"训练内容冲突 \(workout.time.localDay)") else { skipped += 1;continue }
                next.workouts[index] = workout;replaced += 1
            } else { next.workouts.append(workout);added += 1 }
            acceptedRecords.insert(workout.id)
            if restoring { let identity = workout.source ?? SourceIdentity(datasetID:local.dataset.id,entityID:workout.id,kind:"workout");next.tombstones.removeAll { $0.source == identity } }
        }
        for draft in incoming.drafts {
            let isDemo: Bool
            switch draft.content { case .meal(let value): isDemo = value.isDemo;case .workout(let value):isDemo = value.isDemo }
            if isDemo { excludedDemo += 1;continue }
            if let editing = draft.editingRecordID, !acceptedRecords.contains(editing) { skipped += 1;notices.append("未采用其正式记录的编辑草稿已跳过。");continue }
            let origin = origins.first { $0.kind == "draft" && $0.localID == draft.id }!.source
            let restoring = next.tombstones.contains { $0.source == origin || $0.source == SourceIdentity(datasetID:local.dataset.id,entityID:draft.id,kind:"draft") }
            if restoring && !conflict("draft/\(draft.id)","恢复已放弃或已提交的旧草稿",restore:true) { skipped += 1;continue }
            if let index = next.drafts.firstIndex(where:{$0.id == draft.id}) {
                if try equal(next.drafts[index],draft) { duplicates += 1;continue }
                guard conflict("draft/\(draft.id)","已有草稿内容不同") else { skipped += 1;continue }
                next.drafts[index] = draft;replaced += 1
            } else {
                let collision = next.drafts.first { ($0.content.kind == .workout && draft.content.kind == .workout) || ($0.editingRecordID != nil && $0.editingRecordID == draft.editingRecordID) }
                if let collision {
                    guard conflict("draft/\(draft.id)","已有活动草稿，采用导入版本将替换它") else { skipped += 1;continue }
                    next.drafts.removeAll { $0.id == collision.id };replaced += 1
                } else { added += 1 }
                next.drafts.append(draft)
            }
            if restoring { next.tombstones.removeAll { $0.source == origin || $0.source == SourceIdentity(datasetID:local.dataset.id,entityID:draft.id,kind:"draft") } }
            if case .meal(let meal) = draft.content { adoptedMeals.insert(meal.id) }
        }
        for id in adoptedMeals {
            // Keep existing history chains; adopting a backup changes the current value, not the audit trail.
            for estimate in incoming.estimates where estimate.recordID == id {
                if let index = next.estimates.firstIndex(where:{$0.id == estimate.id}) { next.estimates[index] = estimate }
                else { next.estimates.append(estimate) }
            }
        }
        for tombstone in incoming.tombstones {
            if next.tombstones.contains(where:{$0.id == tombstone.id}) { continue }
            let meal = next.meals.first { ($0.source ?? SourceIdentity(datasetID:local.dataset.id,entityID:$0.id,kind:"meal")) == tombstone.source }
            let workout = next.workouts.first { ($0.source ?? SourceIdentity(datasetID:local.dataset.id,entityID:$0.id,kind:"workout")) == tombstone.source }
            let draft = next.drafts.first { item in next.sourceIdentity(kind:"draft",id:item.id) == tombstone.source || origins.first(where: { $0.kind == "draft" && $0.localID == item.id })?.source == tombstone.source }
            if meal != nil || workout != nil || draft != nil {
                guard conflict("tombstone/" + tombstone.id,"导入的永久删除标记与本机记录冲突") else { skipped += 1;continue }
                if let draft { next.drafts.removeAll { $0.id == draft.id } }
                if let meal { next.meals.removeAll { $0.id == meal.id };next.drafts.removeAll { $0.content.recordID == meal.id } }
                if let workout { next.workouts.removeAll { $0.id == workout.id };next.drafts.removeAll { $0.content.recordID == workout.id } }
            }
            next.tombstones.append(tombstone);added += 1
        }
        let mealIDsKept = Set(next.meals.map(\.id) + next.drafts.compactMap { if case .meal(let meal) = $0.content { meal.id } else { nil } })
        next.estimates.removeAll { !mealIDsKept.contains($0.recordID) }
        let references = Set(next.meals.flatMap(\.photoIDs) + next.drafts.flatMap { $0.content.photoIDs })
        let needed = incoming.photos.filter { references.contains($0.id) }
        for photo in needed where !next.photos.contains(where:{$0.id == photo.id}) { next.photos.append(photo) }
        next.photos.removeAll { !references.contains($0.id) }
        // A confirmation describes the exact day's facts, never the union of conflicting backups.
        let days = Set(local.activeMeals.map { $0.time.localDay } + incoming.activeMeals.map { $0.time.localDay } + next.activeMeals.map { $0.time.localDay })
        for day in days {
            let before = try dayFacts(local,on:day), after = try dayFacts(next,on:day)
            let imported = incoming.confirmations.first { $0.day == day }
            let existing = next.confirmations.first { $0.day == day }
            if before != after { next.confirmations.removeAll { $0.day == day } }
            guard try dayFacts(incoming,on:day) == after, next.activeMeals.contains(where:{$0.time.localDay == day}) else {
                if imported != nil { notices.append("合并后的 \(day) 与导入记录不完全相同，未沿用已记全确认。") };continue
            }
            let current = next.confirmations.first { $0.day == day }
            guard (current != nil) != (imported != nil) else { continue }
            let newDay = !local.activeMeals.contains { $0.time.localDay == day } && !local.activeWorkouts.contains { $0.time.localDay == day }
            guard newDay || conflict("confirmation/\(day)","\(day) 的已记全状态不同") else { continue }
            next.confirmations.removeAll { $0.day == day }
            if let imported { next.confirmations.append(imported) }
            if existing != nil { replaced += 1 } else { added += 1 }
        }
        if added + replaced > 0 {
            next.jobs = [];next.aiSettings.consentEpoch += 1
            for origin in origins where !next.importOrigins.contains(where:{$0.id == origin.id}) { next.importOrigins.append(origin) }
        }
        try PackageValidation.validate(next.withoutRuntimeJobs())
        return ImportPlan(baseDatasetID:local.dataset.id,baseRevision:local.dataset.revision,manifest:package.manifest,result:next,conflicts:conflicts,added:added,replaced:replaced,duplicates:duplicates,skipped:skipped,excludedDemo:excludedDemo,notices:Array(Set(notices)).sorted(),incomingPhotos:needed)
    }
    private struct DayFacts: Encodable {
        var meals:[Meal]; var workouts:[Workout]
    }
    private static func dayFacts(_ state:DatasetSnapshot,on day:LocalDay) throws -> Data {
        let meals = state.activeMeals.filter { $0.time.localDay == day }.map { value in
            var value = value; value.currentEstimateID = nil; value.manualRevision = 0; value.factsRevision = 0; value.inputRevision = 0; value.lifecycleEpoch = 0; return value
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let workouts = state.activeWorkouts.filter { $0.time.localDay == day }.map { value in
            var value = value
            value.energyHistory = value.energyHistory.filter { $0.id == value.currentEnergyID }.map { energy in
                var energy = energy; energy.id = stableID("day-facts"); energy.weightKG = nil; energy.profileVersionID = nil; energy.kcal = nil; energy.algorithmVersion = ""; energy.createdAt = Date(timeIntervalSince1970:0);return energy
            }
            value.currentEnergyID = nil;value.factsRevision = 0;value.lifecycleEpoch = 0;return value
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        return try PackageCodec.encode(DayFacts(meals:meals,workouts:workouts))
    }

}
private extension DatasetSnapshot {
    func withoutRuntimeJobs() -> DatasetSnapshot { var copy = self;copy.jobs = [];return copy }
}

public actor PackageImporter {
    public init() {}
    public func apply(_ plan: ImportPlan, package: ValidatedPackage, manager: ManagedStore,
                      fault: @escaping @Sendable (MigrationPoint) throws -> Void = { _ in }) async throws -> LocalRepository {
        let checked = try PackageReader().read(package.url)
        guard checked.manifest == plan.manifest else { throw PackageError.invalid("预览后的资料包已变化，请重新预览") }
        let current = try await manager.open()
        let state = try await current.snapshot()
        guard state.dataset.id == plan.baseDatasetID, state.dataset.revision == plan.baseRevision else { throw DomainError.conflict }
        guard plan.hasChanges else { return current }
        let capacity = try await manager.root.resourceValues(forKeys:[.volumeAvailableCapacityKey]).volumeAvailableCapacity
        let bytes = checked.manifest.files.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
        if let capacity, Int64(capacity) < bytes * 2 + 32 * 1024 * 1024 { throw CocoaError(.fileWriteOutOfSpace) }
        let photos = Dictionary(uniqueKeysWithValues:plan.incomingPhotos.map { ($0.id,$0) }), source = PackageFiles(root:package.url)
        return try await manager.rebuildWithMedia(fault:fault,importedMedia:{ asset in
            guard let imported = photos[asset.id] else { return nil }
            let data = try source.read(imported.relativePath,maxBytes:PackageLimits.imageBytes)
            guard data.count == imported.byteCount, PackageHash.sha256(data) == imported.sha256 else { throw PackageError.incomplete(imported.relativePath) };return data
        },transform:{ value in
            guard value.dataset.id == plan.baseDatasetID, value.dataset.revision == plan.baseRevision else { throw DomainError.conflict }
            // Preview can outlive a user's Stop / directory change. These operational
            // settings do not increment the content revision and must be read at activation.
            let localBackup = value.backup
            value = plan.result
            value.backup = localBackup
        })
    }
}
