import Foundation
import BojiDomain

extension LocalRepository {
    public func configureEstimation(url: URL?, policy: AIServicePolicy?, operationID: UUID = UUID()) throws {
        let existing = try snapshot()
        if existing.aiSettings.serviceURL == url && existing.aiSettings.cachedPolicy == policy { return }
        try commit(id: operationID) { state in
            guard state.dataset.mode == .personal else { throw DomainError.demoOperationDisabled }
            let changed = state.aiSettings.serviceURL != url || state.aiSettings.cachedPolicy != policy
            state.aiSettings.serviceURL = url; state.aiSettings.cachedPolicy = policy
            if changed {
                state.aiSettings.acceptedPolicy = nil; state.aiSettings.consentEpoch += 1
                for index in state.jobs.indices { EstimationRules.cancel(&state.jobs[index], code: "policy_changed") }
            }
        }
    }
    public func acceptEstimationPolicy(_ version: String, operationID: UUID = UUID()) throws {
        try commit(id: operationID) { state in
            guard state.dataset.mode == .personal, state.aiSettings.serviceURL != nil,
                  let policy = state.aiSettings.cachedPolicy, policy.available, policy.version == version else { throw DomainError.notConfigured }
            guard state.aiSettings.acceptedPolicy != version else { return }
            state.aiSettings.acceptedPolicy = version; state.aiSettings.consentEpoch += 1
        }
    }
    public func revokeEstimationConsent(operationID: UUID = UUID()) throws {
        try commit(id: operationID) { state in
            state.aiSettings.acceptedPolicy = nil; state.aiSettings.consentEpoch += 1
            for index in state.jobs.indices { EstimationRules.cancel(&state.jobs[index], code: "consent_revoked") }
        }
    }
    public func setAutomaticEstimation(_ enabled: Bool, operationID: UUID = UUID()) throws {
        try commit(id: operationID) { state in
            guard state.dataset.mode == .personal else { throw DomainError.demoOperationDisabled }
            state.aiSettings.automatic = enabled
            if !enabled {
                for index in state.jobs.indices where state.jobs[index].automatic && state.jobs[index].requestCreatedAt == nil {
                    EstimationRules.cancel(&state.jobs[index], code: "automatic_disabled")
                }
            }
        }
    }
    @discardableResult public func enqueueEstimate(recordID: UUID, draftID: UUID? = nil, automatic: Bool, at now: Date, retryOf: String? = nil, operationID: UUID = UUID()) throws -> UUID {
        let id = UUID()
        try commit(id: operationID) { state in
            guard state.dataset.mode == .personal else { throw DomainError.demoOperationDisabled }
            guard let policy = state.aiSettings.cachedPolicy, policy.available,
                  state.aiSettings.acceptedPolicy == policy.version, state.aiSettings.serviceURL != nil else { throw DomainError.notConfigured }
            let meal: Meal
            if let draftID, let draft = state.drafts.first(where: { $0.id == draftID }), case .meal(let value) = draft.content { meal = value }
            else if draftID == nil, let value = state.activeMeals.first(where: { $0.id == recordID }) { meal = value }
            else { throw DomainError.conflict }
            guard meal.id == recordID, !meal.isDemo else { throw DomainError.conflict }
            try MealRules.validate(meal)
            if automatic && (!state.aiSettings.automatic || meal.photoIDs.isEmpty) { throw DomainError.invalidValue("本次输入不符合自动估算条件") }
            for index in state.jobs.indices where !state.jobs[index].status.isTerminal && !EstimationRules.eligible(state.jobs[index], in: state) {
                EstimationRules.cancel(&state.jobs[index], code: "input_changed")
            }
            if state.jobs.contains(where: { $0.recordID == recordID && !$0.status.isTerminal && EstimationRules.eligible($0, in: state) }) { return }
            if automatic, state.jobs.contains(where: { $0.recordID == recordID && $0.inputRevision == meal.inputRevision && $0.lifecycleEpoch == meal.lifecycleEpoch }) { return }
            var job = EstimateJob(id: id, datasetID: state.dataset.id, meal: meal, consentEpoch: state.aiSettings.consentEpoch, policyVersion: policy.version, automatic: automatic, queuedAt: now)
            job.draftID = draftID; job.serviceURL = state.aiSettings.serviceURL; job.retryOf = retryOf
            state.jobs.append(job)
        }
        let after = try snapshot()
        if after.jobs.contains(where: { $0.id == id }) { return id }
        let meal = draftID.flatMap { id in after.drafts.first { $0.id == id } }.flatMap { draft -> Meal? in
            if case .meal(let value) = draft.content { return value }; return nil
        } ?? after.activeMeals.first { $0.id == recordID }
        guard let old = after.jobs.first(where: { $0.recordID == recordID &&
            (EstimationRules.eligible($0, in: after) || (automatic && $0.inputRevision == meal?.inputRevision && $0.lifecycleEpoch == meal?.lifecycleEpoch))
        }) else { throw DomainError.conflict }
        return old.id
    }
    public func prepareEstimateSend(id: UUID, at now: Date) throws -> EstimateJob? {
        let before = try snapshot()
        if let job = before.jobs.first(where: { $0.id == id }), job.requestCreatedAt != nil, !job.status.isTerminal, EstimationRules.eligible(job, in: before) { return job }
        try commit(id: UUID()) { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == id }), !state.jobs[index].status.isTerminal else { return }
            guard EstimationRules.eligible(state.jobs[index], in: state) else { EstimationRules.cancel(&state.jobs[index], code: "input_changed"); return }
            if state.jobs[index].requestCreatedAt == nil { state.jobs[index].requestCreatedAt = now; state.jobs[index].deadline = now.addingTimeInterval(24 * 60 * 60) }
        }
        let after = try snapshot()
        return after.jobs.first { $0.id == id && !$0.status.isTerminal && EstimationRules.eligible($0, in: after) }
    }
    public func updateEstimateJob(_ value: EstimateJob) throws {
        try commit(id: UUID()) { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == value.id }) else { return }
            guard !state.jobs[index].status.isTerminal, EstimationRules.eligible(state.jobs[index], in: state) else {
                // A response can arrive after local cancellation; retain only the remote ID for best-effort deletion.
                if let remote = value.remoteJobID { state.jobs[index].remoteJobID = remote; state.jobs[index].remoteCancellationPending = true }
                EstimationRules.cancel(&state.jobs[index], code: "input_changed"); return
            }
            state.jobs[index] = value
        }
    }
    public func cancelEstimate(id: UUID) throws {
        try commit(id: UUID()) { state in
            if let index = state.jobs.firstIndex(where: { $0.id == id }) { EstimationRules.cancel(&state.jobs[index], code: "cancelled") }
        }
    }
    public func acknowledgedRemoteCancellation(id: UUID) throws {
        try commit(id: UUID()) { state in if let index = state.jobs.firstIndex(where: { $0.id == id }) { state.jobs[index].remoteCancellationPending = false } }
    }
    public func invalidateEstimateJobs() throws {
        let state = try snapshot()
        guard state.jobs.contains(where: { !$0.status.isTerminal && !EstimationRules.eligible($0, in: state) }) else { return }
        try commit(id: UUID()) { state in
            for index in state.jobs.indices where !state.jobs[index].status.isTerminal && !EstimationRules.eligible(state.jobs[index], in: state) { EstimationRules.cancel(&state.jobs[index], code: "input_changed") }
        }
    }
    @discardableResult public func applyEstimate(jobID: UUID, revision: EstimateRevision) throws -> Bool {
        try FoodEstimateRules.validate(revision)
        try commit(id: revision.id) { state in
            guard let index = state.jobs.firstIndex(where: { $0.id == jobID }), !state.jobs[index].status.isTerminal,
                  EstimationRules.eligible(state.jobs[index], in: state), revision.recordID == state.jobs[index].recordID,
                  revision.inputRevision == state.jobs[index].inputRevision, revision.source == .model,
                  revision.provider == state.aiSettings.cachedPolicy?.provider, revision.model == state.aiSettings.cachedPolicy?.model else { return }
            let job = state.jobs[index]
            guard var meal = EstimationRules.meal(for: job, in: state) else { return }
            var saved = revision; saved.previousRevisionID = meal.currentEstimateID
            state.estimates.append(saved); meal.currentEstimateID = saved.id
            if let draftID = job.draftID, let draftIndex = state.drafts.firstIndex(where: { $0.id == draftID }) { state.drafts[draftIndex].content = .meal(meal) }
            else if let mealIndex = state.meals.firstIndex(where: { $0.id == meal.id }) { state.meals[mealIndex] = meal }
            state.jobs[index].status = .succeeded; state.jobs[index].errorCode = nil
        }
        return try snapshot().estimates.contains { $0.id == revision.id }
    }
}
