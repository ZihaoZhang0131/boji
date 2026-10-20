import Foundation
import BojiDomain

extension LocalRepository {
    public func saveMeal(_ input: Meal, draftID: UUID?, photos: [PhotoAsset] = [], at now: Date = Date(), operationID: UUID) throws {
        try MealRules.validate(input)
        try commit(id: operationID) { state in
            if let draftID {
                guard let draft = state.drafts.first(where: { $0.id == draftID }), draft.content.recordID == input.id,
                      draft.content.kind == .meal else { throw DomainError.conflict }
            }
            var days: Set<LocalDay> = [input.time.localDay]
            if let index = state.meals.firstIndex(where: { $0.id == input.id }) {
                let original = state.meals[index]
                var updated = try MealRules.edited(input, original: original)
                if input.manualRevision >= original.manualRevision, let estimateID = input.currentEstimateID, state.estimates.contains(where: { $0.id == estimateID && $0.recordID == input.id && $0.inputRevision == updated.inputRevision }) {
                    updated.currentEstimateID = estimateID; updated.manualRevision = max(updated.manualRevision, input.manualRevision)
                }
                if updated.factsRevision != original.factsRevision {
                    days.insert(original.time.localDay)
                    state.invalidateConfirmation(on: days)
                }
                if updated.inputRevision != original.inputRevision {
                    for index in state.jobs.indices where state.jobs[index].recordID == input.id && state.jobs[index].inputRevision != updated.inputRevision { EstimationRules.cancel(&state.jobs[index], code: "input_changed") }
                }
                state.meals[index] = updated
            } else {
                guard !state.tombstones.contains(where: { $0.source == (input.source ?? state.sourceIdentity(kind: "meal", id: input.id)) }) else { throw DomainError.conflict }
                state.meals.append(input)
                state.invalidateConfirmation(on: days)
            }
            for photo in photos where !state.photos.contains(where: { $0.id == photo.id }) { state.photos.append(photo) }
            if let draftID {
                state.drafts.removeAll { $0.id == draftID && $0.content.recordID == input.id }
                let tombstone = DeletionTombstone(source: state.sourceIdentity(kind: "draft", id: draftID), deletedAt: now)
                if !state.tombstones.contains(where: { $0.id == tombstone.id }) { state.tombstones.append(tombstone) }
            }
        }
    }

    public func saveManualEstimate(recordID: UUID, expectedInputRevision: Int64, items: [FoodItem], at now: Date, operationID: UUID, estimateID: UUID, draftID: UUID? = nil) throws {
        let total = try FoodEstimateRules.total(items)
        try commit(id: operationID) { state in
            var meal: Meal
            let formalIndex = draftID == nil ? state.meals.firstIndex { $0.id == recordID && $0.deletedAt == nil } : nil
            let draftIndex = state.drafts.firstIndex { $0.content.recordID == recordID && $0.content.kind == .meal && (draftID == nil || $0.id == draftID) }
            if let formalIndex { meal = state.meals[formalIndex] }
            else if let draftIndex, case .meal(let value) = state.drafts[draftIndex].content { meal = value }
            else { throw DomainError.conflict }
            guard meal.inputRevision == expectedInputRevision else { throw DomainError.conflict }
            var estimate = EstimateRevision(id: estimateID, recordID: recordID, inputRevision: meal.inputRevision, source: .manual, items: items, totalKcal: total, createdAt: now)
            estimate.previousRevisionID = meal.currentEstimateID
            meal.currentEstimateID = estimate.id; meal.manualRevision += 1
            state.estimates.append(estimate)
            if let formalIndex { state.meals[formalIndex] = meal }
            else if let draftIndex { state.drafts[draftIndex].content = .meal(meal) }
        }
    }
}
