import Foundation
import BojiDomain

public enum PackageValidation {
    public static func validate(_ state: DatasetSnapshot) throws {
        try state.validateIdentityAndReferences()
        guard state.dataset.mode == .personal, state.dataset.revision >= 0, state.jobs.isEmpty else { throw PackageError.invalid("资料集或运行时任务") }
        guard state.importOrigins.count <= 200_000 else { throw PackageError.limit("来源映射") }
        var lineage: Set<String> = []
        for origin in state.importOrigins {
            guard ["meal","workout","photo","profile","goal","estimate","draft","exercise","set","energy","food"].contains(origin.kind), origin.source.kind == origin.kind,
                  origin.contentHash.map({ origin.kind == "photo" && $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }) ?? true,
                  lineage.insert("\(origin.source.datasetID)/\(origin.kind)/\(origin.source.entityID)/\(origin.contentHash ?? "")").inserted else { throw PackageError.invalid("来源映射重复或类型无效") }
        }
        let allMeals = state.meals + state.drafts.compactMap { if case .meal(let meal) = $0.content { meal } else { nil } }
        let allWorkouts = state.workouts + state.drafts.compactMap { if case .workout(let workout) = $0.content { workout } else { nil } }
        func date(_ value: Date?) throws { if let value, !value.timeIntervalSince1970.isFinite { throw PackageError.invalid("时间数值") } }
        func time(_ value: RecordTime) throws {
            guard (0...23).contains(value.hour), (0...59).contains(value.minute), TimeZone(identifier: value.timeZoneIdentifier) != nil else { throw PackageError.invalid("时间或时区") }
            try date(value.instant)
        }
        func nonnegative(_ values: Int64...) throws { guard values.allSatisfy({ $0 >= 0 && $0 < Int64.max - 1 }) else { throw PackageError.invalid("修订号") } }
        for meal in state.meals { try MealRules.validate(meal) }
        for meal in allMeals {
            try time(meal.time); try date(meal.deletedAt)
            try nonnegative(meal.factsRevision, meal.inputRevision, meal.lifecycleEpoch, meal.manualRevision)
            guard meal.photoIDs.count <= 9, Set(meal.photoIDs).count == meal.photoIDs.count else { throw PackageError.invalid("照片顺序标识") }
            if let id = meal.currentEstimateID {
                guard state.estimates.contains(where: { $0.id == id && $0.recordID == meal.id && $0.inputRevision == meal.inputRevision }) else { throw PackageError.invalid("当前估算关联") }
            }
        }
        let profileIDs = Set(state.profiles.map(\.id))
        var setCount = 0
        for workout in allWorkouts {
            try time(workout.time); try date(workout.deletedAt); try nonnegative(workout.factsRevision, workout.lifecycleEpoch)
            guard Set(workout.exercises.map(\.id)).count == workout.exercises.count else { throw PackageError.invalid("重复动作") }
            let sets = workout.exercises.flatMap(\.sets); setCount += sets.count
            guard setCount <= PackageLimits.records, Set(sets.map(\.id)).count == sets.count else { throw PackageError.limit("训练组") }
            for exercise in workout.exercises {
                for set in exercise.sets {
                    if set.completed { try WorkoutRules.validate(set, kind: exercise.kind) }
                    else {
                        if let weight = set.weightKG, !EnergyRules.isFinite(weight) || !(0...1000).contains(weight) { throw PackageError.invalid("草稿重量") }
                        if let reps = set.reps, !(1...999).contains(reps) { throw PackageError.invalid("草稿次数") }
                    }
                }
            }
            guard Set(workout.energyHistory.map(\.id)).count == workout.energyHistory.count else { throw PackageError.invalid("重复消耗历史") }
            if let id = workout.currentEnergyID, !workout.energyHistory.contains(where: { $0.id == id }) { throw PackageError.invalid("当前消耗关联") }
            for energy in workout.energyHistory {
                try date(energy.createdAt)
                if let id = energy.profileVersionID, !profileIDs.contains(id) { throw PackageError.invalid("训练体重来源") }
                if let weight = energy.weightKG, !EnergyRules.isFinite(weight) || !(30...250).contains(weight) { throw PackageError.invalid("训练体重") }
                if let minutes = energy.minutes, !EnergyRules.isFinite(minutes) || !(0...360).contains(minutes) || minutes == 0 { throw PackageError.invalid("训练时长") }
                if let kcal = energy.kcal, !(0...100_000).contains(kcal) { throw PackageError.invalid("训练消耗") }
                if energy.algorithmVersion == EnergyRules.workoutAlgorithm,
                   energy.kcal != EnergyRules.netWorkout(weightKG: energy.weightKG, minutes: energy.minutes, intensity: energy.intensity) { throw PackageError.invalid("训练消耗快照") }
            }
        }
        for workout in state.workouts {
            let completed = try WorkoutRules.completedExercises(workout.exercises)
            guard completed == workout.exercises else { throw PackageError.invalid("正式训练含未完成组") }
        }
        for profile in state.profiles { try EnergyRules.validate(profile.profile); try date(profile.createdAt); try nonnegative(profile.sequence) }
        for goal in state.goals {
            try nonnegative(goal.sequence)
            guard goal.endDay.map({ $0 >= goal.startDay }) ?? true else { throw PackageError.invalid("阶段日期倒置") }
        }
        for estimate in state.estimates {
            try FoodEstimateRules.validate(estimate); try date(estimate.createdAt); try nonnegative(estimate.inputRevision)
            guard estimate.items.count <= 100, Set(estimate.items.map(\.id)).count == estimate.items.count else { throw PackageError.invalid("估算食物项") }
            for item in estimate.items {
                guard EnergyRules.isFinite(item.referenceKcal), (0...10000).contains(item.referenceKcal),
                      item.referenceGrams.map({ EnergyRules.isFinite($0) && $0 >= 0 }) ?? true else { throw PackageError.invalid("比例参照") }
            }
            var visited: Set<UUID> = [estimate.id], previous = estimate.previousRevisionID
            while let id = previous {
                guard visited.insert(id).inserted, let parent = state.estimates.first(where: { $0.id == id && $0.recordID == estimate.recordID }) else { throw PackageError.invalid("修正历史关联或循环") }
                previous = parent.previousRevisionID
            }
        }
        var editing: Set<UUID> = []
        for draft in state.drafts {
            try date(draft.savedAt); try nonnegative(draft.revision)
            if let id = draft.editingRecordID {
                guard editing.insert(id).inserted, id == draft.content.recordID,
                      (draft.content.kind == .meal ? state.activeMeals.contains { $0.id == id } : state.activeWorkouts.contains { $0.id == id }) else { throw PackageError.invalid("编辑草稿关联") }
            }
        }
        for confirmation in state.confirmations { try date(confirmation.confirmedAt); try nonnegative(confirmation.factsRevision) }
        for tombstone in state.tombstones { try date(tombstone.deletedAt); guard ["meal","workout","draft"].contains(tombstone.source.kind) else { throw PackageError.invalid("墓碑类型") } }
    }
}
