import Foundation
import Testing
import BojiDomain

@Test func specifiedEnergyExamplesAndUnknowns() throws {
    let profile = BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2)
    #expect(EnergyRules.resting(profile) == 1659)
    #expect(EnergyRules.baseline(profile) == 1991)
    #expect(EnergyRules.netWorkout(weightKG: 70, minutes: 45, intensity: .regular) == 138)
    #expect(EnergyRules.resting(nil) == nil)
    #expect(EnergyRules.netWorkout(weightKG: nil, minutes: 45, intensity: .regular) == nil)
    #expect(EnergyRules.netWorkout(weightKG: 70, minutes: nil, intensity: .regular) == nil)
    #expect(EnergyRules.netWorkout(weightKG: 70, minutes: 0, intensity: .regular) == nil)
    let snapshot = try EnergyRules.workoutSnapshot(weightKG: 70, minutes: 45, intensity: .regular, profileID: UUID(), at: Date(timeIntervalSince1970: 0))
    var updatedProfile = profile; updatedProfile.weightKG = 72
    #expect(EnergyRules.baseline(updatedProfile) != EnergyRules.baseline(profile))
    #expect(snapshot.weightKG == 70 && snapshot.kcal == 138)
    #expect(snapshot.algorithmVersion == "met-net-v1")
    #expect(throws: DomainError.self) { try EnergyRules.workoutSnapshot(weightKG: 70, minutes: 361, intensity: .regular, profileID: nil, at: Date()) }
}

@Test func profileBoundariesAndHistoryDates() throws {
    var profile = BodyProfile(sex: .female, age: 18, heightCM: 100, weightKG: 30, activityFactor: 1.2)
    try EnergyRules.validate(profile)
    profile.age = 59; profile.heightCM = 230; profile.weightKG = 250; profile.targetKcal = 10000
    try EnergyRules.validate(profile)
    profile.age = 16
    #expect(throws: DomainError.self) { try EnergyRules.validate(profile) }
    profile.age = 28; profile.weightKG = .nan
    #expect(throws: DomainError.self) { try EnergyRules.validate(profile) }
    profile.weightKG = 70; profile.targetKcal = nil
    try EnergyRules.validate(profile)
    let today = try LocalDay(year: 2026, month: 10, day: 17)
    let previous = ProfileVersion(effectiveDay: today.adding(days: -3), sequence: 1, profile: profile, createdAt: Date())
    let current = ProfileVersion(effectiveDay: today, sequence: 2, profile: profile, createdAt: Date())
    let latest = ProfileVersion(effectiveDay: today, sequence: 3, profile: profile, createdAt: Date())
    #expect(ProfileRules.effective(on: today.adding(days: -4), versions: [previous, current, latest]) == nil)
    #expect(ProfileRules.effective(on: today.adding(days: -1), versions: [latest, previous, current])?.id == previous.id)
    #expect(ProfileRules.effective(on: today, versions: [latest, previous, current])?.id == latest.id)
    #expect(ProfileRules.affectedInterval(start: today.adding(days: -2), versions: [previous, current]).endExclusive == today)
}

@Test func goalsKeepSameDayHistoryAndNoteChangesDoNotAddStage() throws {
    let day = try LocalDay(year: 2026, month: 10, day: 17)
    let first = try GoalRules.update(stages: [], goal: .maintain, start: day, note: "旧备注", today: day, sequence: 1)
    let second = try GoalRules.update(stages: first, goal: .gainSteadily, start: day, note: "新备注", today: day, sequence: 2)
    #expect(second.count == 2 && second[0].endDay == day)
    #expect(GoalRules.effective(on: day, stages: second)?.goal == .gainSteadily)
    let edited = try GoalRules.update(stages: second, goal: .gainSteadily, start: day, note: "改备注", today: day, sequence: 3)
    #expect(edited.count == 2 && edited[1].id == second[1].id && edited[1].note == "改备注")
    #expect(throws: DomainError.self) { try GoalRules.update(stages: edited, goal: .loseSlowly, start: day.adding(days: -1), note: "", today: day, sequence: 4) }
}
