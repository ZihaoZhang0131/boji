import Foundation
import Testing
import BojiDomain
import BojiPersistence

@Test func workoutValidationReferenceAndBatchBoundaries() throws {
    for reps in [1, 999] { try WorkoutRules.validate(WorkoutSet(reps: reps), kind: .bodyweight) }
    for reps in [nil, 0, 1000] { #expect(throws: DomainError.self) { try WorkoutRules.validate(WorkoutSet(reps: reps), kind: .bodyweight) } }
    for weight in [Decimal(0), 1000] { try WorkoutRules.validate(WorkoutSet(weightKG: weight, reps: 1), kind: .weighted) }
    for weight in [Decimal(-1), 1001, .nan] { #expect(throws: DomainError.self) { try WorkoutRules.validate(WorkoutSet(weightKG: weight, reps: 1), kind: .weighted) } }
    let done = try WorkoutRules.confirming(WorkoutSet(weightKG: 40, reps: 8), kind: .weighted)
    let reference = WorkoutRules.reference(from: done)
    #expect(!reference.completed && reference.id != done.id && reference.reps == 8)
    for count in [1, 30] { #expect(try WorkoutRules.batch(count: count, weightKG: nil, reps: 8, kind: .bodyweight).count == count) }
    for count in [0, 31] { #expect(throws: DomainError.self) { try WorkoutRules.batch(count: count, weightKG: nil, reps: 8, kind: .bodyweight) } }
    let six = [done, done] + Array(repeating: reference, count: 4)
    #expect(try WorkoutRules.completedExercises([Exercise(name: "卧推", kind: .weighted, sets: six)])[0].sets.count == 2)
    #expect(throws: DomainError.self) { try WorkoutRules.completedExercises([Exercise(name: "卧推", kind: .weighted, sets: [reference])]) }
}

@Test func workoutFinishCopyAndReestimateKeepHistoryAndIdentity() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let clock = FixedClock("2026-10-17T12:00:00Z"), day = LocalDay(FixedClock("2026-10-17T12:00:00Z").now, timeZone: TimeZone(secondsFromGMT: 0)!)
    var input = Workout(time: RecordTime(clock: clock)); input.name = "背部"
    var sets = try WorkoutRules.batch(count: 3, weightKG: nil, reps: 8, kind: .bodyweight)
    sets[2].reps = 7
    input.exercises = [Exercise(name: "引体向上", kind: .bodyweight, sets: sets + [WorkoutSet(reps: 6)])]
    let draft = RecordDraft(content: .workout(input), savedAt: clock.now)
    try await store.saveDraft(draft, operationID: UUID())
    #expect(try await store.snapshot().workouts.isEmpty)
    let operation = UUID()
    try await store.finishWorkout(input, draftID: draft.id, minutes: nil, intensity: .regular, reestimate: false, at: clock.now, operationID: operation)
    try await store.finishWorkout(input, draftID: draft.id, minutes: nil, intensity: .regular, reestimate: false, at: clock.now, operationID: operation)
    let original = try await store.snapshot().workouts[0]
    #expect(original.exercises[0].sets.map(\.reps) == [8, 8, 7])
    #expect(original.energyHistory.count == 1 && original.energyHistory[0].kcal == nil)
    try await store.saveProfile(BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2), effectiveDay: day, today: day, backdateConfirmed: false, at: clock.now, operationID: UUID(), versionID: UUID())
    #expect(try await store.snapshot().workouts[0] == original)
    let edited = RecordDraft(editingRecordID: original.id, content: .workout(original), savedAt: clock.now)
    try await store.saveDraft(edited, operationID: UUID())
    try await store.finishWorkout(original, draftID: edited.id, minutes: 45, intensity: .regular, reestimate: true, at: clock.now, operationID: UUID())
    let updated = try await store.snapshot().workouts[0]
    #expect(updated.id == original.id && updated.energyHistory.count == 2 && updated.energyHistory[1].kcal == 138)
    let copied = WorkoutRules.copy(updated, clock: clock)
    #expect(copied.id != original.id && copied.energyHistory.isEmpty && copied.currentEnergyID == nil)
    #expect(copied.exercises.flatMap(\.sets).allSatisfy { !$0.completed })
    #expect(Set(copied.exercises.flatMap { $0.sets.map(\.id) }).isDisjoint(with: original.exercises.flatMap { $0.sets.map(\.id) }))
}

@Test func completeTrainingLifecycleSurvivesRestartWeightChangeCopyAndTrashWithoutDoubleCounting() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let clock=FixedClock("2026-10-17T10:00:00Z"),day=LocalDay(clock.now,timeZone:clock.timeZone)
    let first=try await LocalRepository.open(at:root)
    try await first.saveProfile(BodyProfile(sex:.male,age:28,heightCM:175,weightKG:70,activityFactor:1.2),effectiveDay:day,today:day,backdateConfirmed:false,at:clock.now,operationID:UUID(),versionID:UUID())
    var input=Workout(time:RecordTime(clock:clock));input.name="Lifecycle fixture"
    input.exercises=[Exercise(name:"Bodyweight",kind:.bodyweight,sets:[WorkoutSet(reps:8,completed:true),WorkoutSet(reps:7,completed:true),WorkoutSet(reps:6,completed:false)])]
    let draft=RecordDraft(content:.workout(input),savedAt:clock.now)
    try await first.saveDraft(draft,operationID:UUID())
    let restarted=try await LocalRepository.open(at:root)
    #expect(try await restarted.snapshot().drafts[0].id==draft.id)
    try await restarted.finishWorkout(input,draftID:draft.id,minutes:45,intensity:.regular,reestimate:false,at:clock.now,operationID:UUID())
    let original=try #require(await restarted.snapshot().workouts.first),energy=try #require(original.energyHistory.first)
    #expect(original.exercises.flatMap(\.sets).count==2 && energy.kcal==138)
    try await restarted.saveProfile(BodyProfile(sex:.male,age:28,heightCM:175,weightKG:80,activityFactor:1.2),effectiveDay:day,today:day,backdateConfirmed:false,at:clock.now.addingTimeInterval(1),operationID:UUID(),versionID:UUID())
    #expect(try await restarted.snapshot().workouts[0].energyHistory[0]==energy)
    var copied=WorkoutRules.copy(original,clock:clock)
    #expect(copied.energyHistory.isEmpty && copied.exercises.flatMap(\.sets).allSatisfy{!$0.completed})
    copied.exercises[0].sets[0].completed=true
    let copiedDraft=RecordDraft(content:.workout(copied),savedAt:clock.now)
    try await restarted.saveDraft(copiedDraft,operationID:UUID())
    try await restarted.finishWorkout(copied,draftID:copiedDraft.id,minutes:45,intensity:.regular,reestimate:false,at:clock.now,operationID:UUID())
    #expect(try await restarted.snapshot().workouts.first{$0.id==copied.id}?.energyHistory[0].weightKG==80)
    var edit=original;edit.name="Edited old session"
    let editing=RecordDraft(editingRecordID:original.id,content:.workout(edit),savedAt:clock.now)
    try await restarted.saveDraft(editing,operationID:UUID())
    try await restarted.finishWorkout(edit,draftID:editing.id,minutes:45,intensity:.regular,reestimate:false,at:clock.now,operationID:UUID())
    #expect(try await restarted.snapshot().workouts.first{$0.id==original.id}?.energyHistory==original.energyHistory)
    try await restarted.moveToTrash(kind:.workout,id:original.id,at:clock.now,operationID:UUID())
    #expect(try await restarted.snapshot().activeWorkouts.count==1)
    try await restarted.restore(kind:.workout,id:original.id,at:clock.now.addingTimeInterval(10),operationID:UUID())
    try await restarted.restore(kind:.workout,id:original.id,at:clock.now.addingTimeInterval(10),operationID:UUID())
    let final=try await LocalRepository.open(at:root),state=try await final.snapshot()
    #expect(state.activeWorkouts.count==2 && state.drafts.isEmpty)
    #expect(ReviewRules.day(day,in:state).knownWorkoutKcal==296)
}
