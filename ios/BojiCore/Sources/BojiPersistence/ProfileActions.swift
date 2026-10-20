import Foundation
import BojiDomain

extension LocalRepository {
    public func saveProfile(_ profile: BodyProfile, effectiveDay: LocalDay, today: LocalDay, backdateConfirmed: Bool, at now: Date, operationID: UUID, versionID: UUID) throws {
        try EnergyRules.validate(profile)
        try ProfileRules.validateEffectiveDay(effectiveDay, today: today)
        guard effectiveDay == today || backdateConfirmed else { throw DomainError.invalidValue("请确认回溯资料的影响日期") }
        try commit(id: operationID) { state in
            state.profiles.append(ProfileVersion(id: versionID, effectiveDay: effectiveDay, sequence: state.dataset.revision + 1, profile: profile, createdAt: now))
        }
    }

    public func saveGoal(_ goal: Goal, start: LocalDay, note: String, today: LocalDay, operationID: UUID, stageID: UUID) throws {
        try commit(id: operationID) { state in
            state.goals = try GoalRules.update(stages: state.goals, goal: goal, start: start, note: note, today: today, sequence: state.dataset.revision + 1, id: stageID)
        }
    }
}
