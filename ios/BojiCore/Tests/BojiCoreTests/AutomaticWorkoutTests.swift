import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiPortability

@Test func automaticEnergyUsesSeparateActiveAndRestPhasesAndNoExternalWeightMultiplier() throws {
    let exercises = [Exercise(name: "卧推", kind: .weighted, sets: [WorkoutSet(weightKG: 60, reps: 10), WorkoutSet(weightKG: 60, reps: 10)]), Exercise(name: "俯卧撑", kind: .bodyweight, sets: [WorkoutSet(reps: 10)])]
    let a = WorkoutEstimateInputs(exercises: exercises)
    #expect(a.setCount == 3 && a.weightedReps == 20 && a.bodyweightReps == 10)
    #expect(a.minutes == 4 && a.restMinutes == 2)
    #expect(EnergyRules.automaticWorkout(weightKG: 70, inputs: a) == 6)
    var heavier = exercises; heavier[0].sets[0].weightKG = 100
    #expect(WorkoutEstimateInputs(exercises: heavier) == a)
    #expect(EnergyRules.automaticWorkout(weightKG: nil, inputs: a) == nil)
    let single = WorkoutEstimateInputs(exercises: [Exercise(name: "自重", kind: .bodyweight, sets: [WorkoutSet(reps: 1)])])
    #expect(single.restMinutes == 0 && EnergyRules.automaticWorkout(weightKG: 30, inputs: single) == 0)
    var huge = a; huge.setCount = 1000; huge.weightedReps = 999000; huge.bodyweightReps = 0
    #expect(huge.isValid && huge.supportedMinutes == nil && EnergyRules.automaticWorkout(weightKG: 70, inputs: huge) == nil)
    var forged = a; forged.restMET = 3.5
    #expect(!forged.isValid)
}

@Test func automaticSavePreservesLegacyUntilEditedAndRoundTripsHistory() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root.appendingPathComponent("store")), clock = FixedClock("2026-10-17T12:00:00Z")
    let day = LocalDay(clock.now, timeZone: clock.timeZone)
    try await store.saveProfile(BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2), effectiveDay: day, today: day, backdateConfirmed: false, at: clock.now, operationID: UUID(), versionID: UUID())
    var input = Workout(time: RecordTime(clock: clock)); input.name = "保留旧名称"
    input.exercises = [Exercise(name: "俯卧撑", kind: .bodyweight, sets: [WorkoutSet(reps: 8)])]
    try await store.saveWorkout(input, minutes: 45, intensity: .regular, reestimate: false, at: clock.now, operationID: UUID())
    let original = try await store.snapshot().workouts[0]
    try await store.saveWorkout(original, at: clock.now, operationID: UUID())
    #expect(try await store.snapshot().workouts[0] == original)
    try await store.saveProfile(BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 80, activityFactor: 1.2), effectiveDay: day, today: day, backdateConfirmed: false, at: clock.now, operationID: UUID(), versionID: UUID())
    var changed = original; changed.exercises[0].sets[0].reps = 10
    try await store.saveWorkout(changed, at: clock.now, operationID: UUID())
    let updated = try await store.snapshot().workouts[0]
    #expect(updated.name == original.name && updated.time == original.time)
    #expect(updated.energyHistory.count == 2 && updated.energyHistory[0] == original.energyHistory[0])
    #expect(updated.energyHistory[1].weightKG == 70 && updated.energyHistory[1].kcal == 2)
    #expect(updated.energyHistory[1].algorithmVersion == EnergyRules.automaticWorkoutAlgorithm)
    let output = try await PackageExporter().export(repository: store, to: root.appendingPathComponent("exports"))
    let restored = try PackageReader().read(output.url).snapshot
    #expect(restored.workouts == [updated])
    var tampered = restored; tampered.workouts[0].energyHistory[1].kcal = 500
    #expect(throws: PackageError.self) { try PackageValidation.validate(tampered) }
    let reopened = try await LocalRepository.open(at: root.appendingPathComponent("store"))
    #expect(try await reopened.snapshot().workouts == [updated])
}

@Test func automaticUnknownAndUnsupportedEstimatesStillSaveAndPrototypeImportKeepsAssumptions() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root.appendingPathComponent("store")), clock = FixedClock("2026-10-17T12:00:00Z")
    var input = Workout(time: RecordTime(clock: clock))
    input.exercises = [Exercise(name: "俯卧撑", kind: .bodyweight, sets: [WorkoutSet(reps: 8)])]
    try await store.saveWorkout(input, at: clock.now, operationID: UUID())
    let unknown = try await store.snapshot().workouts[0]
    #expect(unknown.energyHistory[0].kcal == nil && unknown.energyHistory[0].automaticInputs != nil)
    let data = Data(#"{"schema_version":1,"prototype":true,"meals":[],"workouts":[{"id":"auto","date":"2026-10-17","time":"12:00","name":"","exercises":[{"name":"俯卧撑","type":"body","sets":[{"reps":8,"done":true}]}],"energy":{"method":"sets-met-net-v1","weight":70,"minutes":0.533333,"activeKcal":1,"automaticInputs":{"weightedReps":0,"bodyweightReps":8,"setCount":1,"secondsPerRep":4,"restSeconds":60,"weightedMET":3.5,"bodyweightMET":3,"restMET":1.3}}}],"complete":[]}"#.utf8)
    var options = PrototypeOptions(timeZoneIdentifier: "UTC", undatedProfileDay: input.time.localDay)
    options.confirmedUnitsAndProvenance = true; options.confirmedAmbiguousHistory = true
    let conversion = try await PrototypeImporter().convert(data, options: options, to: root.appendingPathComponent("imports"))
    let energy = try #require(conversion.package.snapshot.workouts.first?.energyHistory.first)
    #expect(energy.automaticInputs?.bodyweightReps == 8 && energy.kcal == 1)
}
