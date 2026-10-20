import Foundation

public struct AIServicePolicy: Codable, Equatable, Sendable {
    public var available: Bool
    public var version: String
    public var provider: String?
    public var model: String?
    public var sentData: [String]
    public var providerRetention: String
    public var rawRetentionHours: Int
    public var metadataRetentionDays: Int
    public var feePayer: String
    public var dailyAttempts: Int
    public init(available: Bool, version: String, provider: String?, model: String?, sentData: [String], providerRetention: String, rawRetentionHours: Int, metadataRetentionDays: Int, feePayer: String, dailyAttempts: Int) {
        self.available = available; self.version = version; self.provider = provider; self.model = model; self.sentData = sentData
        self.providerRetention = providerRetention; self.rawRetentionHours = rawRetentionHours; self.metadataRetentionDays = metadataRetentionDays; self.feePayer = feePayer; self.dailyAttempts = dailyAttempts
    }
}

public enum EstimationRules {
    public static func meal(for job: EstimateJob, in state: DatasetSnapshot) -> Meal? {
        if let draftID = job.draftID, let draft = state.drafts.first(where: { $0.id == draftID }), case .meal(let meal) = draft.content { return meal }
        return state.activeMeals.first { $0.id == job.recordID }
    }
    public static func eligible(_ job: EstimateJob, in state: DatasetSnapshot) -> Bool {
        guard state.dataset.mode == .personal, state.dataset.id == job.datasetID,
              state.aiSettings.serviceURL == job.serviceURL,
              state.aiSettings.acceptedPolicy == job.policyVersion,
              state.aiSettings.cachedPolicy?.available == true,
              state.aiSettings.cachedPolicy?.version == job.policyVersion,
              state.aiSettings.consentEpoch == job.consentEpoch,
              !(job.automatic && !state.aiSettings.automatic && job.requestCreatedAt == nil),
              let meal = meal(for: job, in: state), !meal.isDemo, meal.deletedAt == nil,
              meal.id == job.recordID, meal.inputRevision == job.inputRevision,
              meal.lifecycleEpoch == job.lifecycleEpoch, meal.manualRevision == job.manualRevision,
              meal.photoIDs == job.photoIDs, meal.note == job.note else { return false }
        if let formal = state.activeMeals.first(where: { $0.id == job.recordID }), formal.manualRevision > job.manualRevision { return false }
        return true
    }
    public static func cancel(_ job: inout EstimateJob, code: String) {
        guard !job.status.isTerminal else { return }
        job.status = .cancelled; job.errorCode = code
        job.remoteCancellationPending = job.remoteJobID != nil
    }
}
