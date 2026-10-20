import Foundation
import Testing
import BojiDomain
import BojiPersistence

@Test func draftCoalescesRecoversAndFailureRemainsRetryable() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let failure = FailOnce()
    let repository = try await LocalRepository.open(at: root, fault: { try failure.check($0) })
    let autosaver = DraftAutosaver(repository: repository, clock: clock)
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "第一版"
    let id = UUID()
    await autosaver.changed(RecordDraft(id: id, content: .meal(meal), savedAt: clock.now))
    meal.note = "第二版"
    await autosaver.changed(RecordDraft(id: id, content: .meal(meal), savedAt: clock.now))
    await #expect(throws: CocoaError.self) { try await autosaver.flush() }
    if case .failed = await autosaver.status {} else { Issue.record("保存失败未暴露") }
    #expect(try await repository.snapshot().drafts.isEmpty)
    try await autosaver.flush()
    let reopened = try await LocalRepository.open(at: root)
    let restored = try await reopened.snapshot()
    #expect(restored.drafts.count == 1 && restored.meals.isEmpty)
    #expect(restored.drafts[0].content == .meal(meal))
    try await autosaver.discard(draftID: id)
    #expect(try await repository.snapshot().drafts.isEmpty)
    let lateDraft = RecordDraft(id: id, content: .meal(meal), savedAt: clock.now)
    await #expect(throws: DomainError.conflict) { try await repository.saveDraft(lateDraft, operationID: UUID()) }
}

@Test func editingDraftDoesNotChangeFormalRecordAndOneWorkoutDraftSurvives() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let store = try await LocalRepository.open(at: root)
    var workout = Workout(time: RecordTime(clock: clock)); workout.name = "原训练"
    let original = workout
    try await store.commit(id: UUID()) { $0.workouts = [original] }
    workout.name = "草稿修改"
    let draft = RecordDraft(editingRecordID: workout.id, content: .workout(workout), savedAt: clock.now)
    try await store.saveDraft(draft, operationID: UUID())
    #expect(try await store.snapshot().workouts == [original])
    let another = RecordDraft(content: .workout(workout), savedAt: clock.now)
    await #expect(throws: DomainError.conflict) { try await store.saveDraft(another, operationID: UUID()) }
    #expect(try await store.snapshot().drafts == [draft])
    try await store.moveToTrash(kind: .workout, id: original.id, at: clock.now, operationID: UUID())
    try await store.restore(kind: .workout, id: original.id, at: clock.now, operationID: UUID())
    await #expect(throws: DomainError.conflict) { try await store.saveDraft(draft, operationID: UUID()) }
}

@Test func trashBoundaryRestoresIdentityInvalidatesJobsAndCreatesTombstone() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let store = try await LocalRepository.open(at: root)
    let photo = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: clock)); meal.photoIDs = [photo.id]
    let input = meal
    try await store.commit(id: UUID()) { state in
        state.meals = [input]; state.photos = [photo]
        state.jobs = [EstimateJob(datasetID: state.dataset.id, meal: input, consentEpoch: 1, policyVersion: "p1", automatic: true, queuedAt: clock.now)]
        state.confirmations = [DayConfirmation(day: input.time.localDay, confirmedAt: clock.now, factsRevision: 0)]
    }
    try await store.moveToTrash(kind: .meal, id: meal.id, at: clock.now, operationID: UUID())
    let trash = try await store.snapshot()
    #expect(trash.activeMeals.isEmpty && trash.confirmations.isEmpty)
    #expect(trash.jobs[0].status == .cancelled && trash.meals[0].lifecycleEpoch == 1)
    try await store.restore(kind: .meal, id: meal.id, at: clock.now.addingTimeInterval(LocalRepository.trashRetention - 1), operationID: UUID())
    #expect(try await store.snapshot().activeMeals.map(\.id) == [meal.id])
    #expect(try await store.snapshot().meals[0].lifecycleEpoch == 2)
    try await store.moveToTrash(kind: .meal, id: meal.id, at: clock.now, operationID: UUID())
    await #expect(throws: DomainError.self) { try await store.permanentlyDelete(kind: .meal, id: meal.id, confirmed: false, at: clock.now, operationID: UUID()) }
    await #expect(throws: DomainError.self) { try await store.restore(kind: .meal, id: meal.id, at: clock.now.addingTimeInterval(LocalRepository.trashRetention), operationID: UUID()) }
    try await store.expireTrash(at: clock.now.addingTimeInterval(LocalRepository.trashRetention))
    let purged = try await store.snapshot()
    #expect(purged.meals.isEmpty && purged.jobs.isEmpty)
    #expect(purged.tombstones.count == 1 && purged.tombstones[0].source.entityID == meal.id)
    await #expect(throws: DomainError.missingPhoto(photo.id)) { try await store.readPhoto(photo) }
}
