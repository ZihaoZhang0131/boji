import Foundation
import Testing
import BojiDomain
import BojiPersistence

@Test func backdatedProfileRequiresConfirmationAndDoesNotRewriteTraining() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let today = LocalDay(clock.now, timeZone: clock.timeZone)
    let oldDay = today.adding(days: -7)
    let original = BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2)
    let firstID = UUID()
    try await store.saveProfile(original, effectiveDay: oldDay, today: today, backdateConfirmed: true, at: clock.now, operationID: UUID(), versionID: firstID)
    var workout = Workout(time: RecordTime(clock: clock, selectedDay: oldDay))
    let energy = try EnergyRules.workoutSnapshot(weightKG: 70, minutes: 45, intensity: .regular, profileID: firstID, at: clock.now)
    workout.energyHistory = [energy]; workout.currentEnergyID = energy.id
    let saved = workout
    try await store.commit(id: UUID()) { $0.workouts = [saved] }
    var changed = original; changed.weightKG = 72
    try await store.saveProfile(changed, effectiveDay: today, today: today, backdateConfirmed: false, at: clock.now, operationID: UUID(), versionID: UUID())
    let current = try await store.snapshot()
    #expect(ProfileRules.effective(on: today.adding(days: -1), versions: current.profiles)?.profile.weightKG == 70)
    #expect(ProfileRules.effective(on: today, versions: current.profiles)?.profile.weightKG == 72)
    await #expect(throws: DomainError.self) {
        try await store.saveProfile(changed, effectiveDay: oldDay, today: today, backdateConfirmed: false, at: clock.now, operationID: UUID(), versionID: UUID())
    }
    try await store.saveProfile(changed, effectiveDay: oldDay, today: today, backdateConfirmed: true, at: clock.now, operationID: UUID(), versionID: UUID())
    let after = try await store.snapshot()
    #expect(ProfileRules.effective(on: oldDay, versions: after.profiles)?.profile.weightKG == 72)
    #expect(after.workouts == [saved])
    #expect(after.profiles.count == 3 && after.profiles.allSatisfy { $0.profile.targetKcal == nil })
}

@Test func goalChangesPreservePersonalTargetAndReopenWithoutDuplicateStages() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let day = LocalDay(clock.now, timeZone: clock.timeZone)
    let profile = BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2, targetKcal: 2400)
    try await store.saveProfile(profile, effectiveDay: day, today: day, backdateConfirmed: false, at: clock.now, operationID: UUID(), versionID: UUID())
    let operation = UUID(), stage = UUID()
    try await store.saveGoal(.loseSlowly, start: day, note: "按自己的计划", today: day, operationID: operation, stageID: stage)
    try await store.saveGoal(.loseSlowly, start: day, note: "按自己的计划", today: day, operationID: operation, stageID: stage)
    let reopened = try await LocalRepository.open(at: root)
    let state = try await reopened.snapshot()
    #expect(state.goals.count == 1 && state.goals[0].id == stage)
    #expect(state.profiles[0].profile.targetKcal == 2400)
}
