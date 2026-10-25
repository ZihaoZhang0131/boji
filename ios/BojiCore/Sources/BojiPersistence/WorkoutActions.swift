import Foundation
import BojiDomain

extension LocalRepository {
    public func finishWorkout(_ input: Workout, draftID: UUID, minutes: Decimal?, intensity: TrainingIntensity,
                              reestimate: Bool, at now: Date, operationID: UUID) throws {
        try persistWorkout(input, draftID: draftID, minutes: minutes, intensity: intensity, reestimate: reestimate, at: now, operationID: operationID)
    }

    /// Commits the whole form without ever persisting an intermediate draft.
    public func saveWorkout(_ input: Workout, minutes: Decimal?, intensity: TrainingIntensity,
                            reestimate: Bool, at now: Date, operationID: UUID) throws {
        guard !input.exercises.isEmpty else { throw DomainError.invalidValue("请添加至少一个动作") }
        var record = input
        record.exercises = try input.exercises.map { exercise in
            guard !exercise.sets.isEmpty else { throw DomainError.invalidValue("请为动作添加至少一组，或删除该动作") }
            var value = exercise
            value.sets = try exercise.sets.map { try WorkoutRules.confirming($0, kind: exercise.kind) }
            return value
        }
        try persistWorkout(record, draftID: nil, minutes: minutes, intensity: intensity, reestimate: reestimate, at: now, operationID: operationID)
    }

    private func persistWorkout(_ input: Workout, draftID: UUID?, minutes: Decimal?, intensity: TrainingIntensity,
                                reestimate: Bool, at now: Date, operationID: UUID) throws {
        let exercises = try WorkoutRules.completedExercises(input.exercises)
        if let minutes, !EnergyRules.isFinite(minutes) || minutes <= 0 || minutes > 360 { throw DomainError.invalidValue("时长须大于 0 且不超过 360 分钟") }
        try commit(id: operationID) { state in
            if let draftID {
                guard let draft = state.drafts.first(where: { $0.id == draftID }), draft.content.recordID == input.id,
                      draft.content.kind == .workout else { throw DomainError.conflict }
            }
            let original = state.workouts.first { $0.id == input.id }
            if let original {
                guard original.deletedAt == nil, original.lifecycleEpoch == input.lifecycleEpoch,
                      original.factsRevision == input.factsRevision else { throw DomainError.conflict }
            } else {
                guard !state.tombstones.contains(where: { $0.source == (input.source ?? state.sourceIdentity(kind: "workout", id: input.id)) }) else { throw DomainError.conflict }
            }
            var value = original ?? input
            value.name = input.name; value.time = input.time; value.exercises = exercises
            let oldEnergy = original?.energyHistory.first { $0.id == original?.currentEnergyID }
            let factsChanged = original == nil || original?.name != value.name || original?.time != value.time || original?.exercises != exercises || oldEnergy?.minutes != minutes || oldEnergy?.intensity != intensity
            if oldEnergy == nil || oldEnergy?.minutes != minutes || oldEnergy?.intensity != intensity || reestimate {
                let profile = ProfileRules.effective(on: input.time.localDay, versions: state.profiles)
                let preserveWeight = oldEnergy != nil && !reestimate
                let energy = try EnergyRules.workoutSnapshot(weightKG: preserveWeight ? oldEnergy?.weightKG : profile?.profile.weightKG,
                    minutes: minutes, intensity: intensity, profileID: preserveWeight ? oldEnergy?.profileVersionID : profile?.id, at: now)
                value.energyHistory.append(energy); value.currentEnergyID = energy.id
            }
            if factsChanged {
                value.factsRevision += 1
                state.invalidateConfirmation(on: Set([original?.time.localDay, value.time.localDay].compactMap { $0 }))
            }
            if let index = state.workouts.firstIndex(where: { $0.id == input.id }) { state.workouts[index] = value }
            else { state.workouts.append(value) }
            if let draftID {
                state.drafts.removeAll { $0.id == draftID }
                state.tombstones.append(DeletionTombstone(source: state.sourceIdentity(kind: "draft", id: draftID), deletedAt: now))
            }
        }
    }
}
