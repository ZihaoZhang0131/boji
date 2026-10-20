import Foundation
import Testing
import BojiDomain
import BojiPersistence

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("boji-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func persistentRoundTripPreservesIdentityOrderNilAndHistories() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let original = try await store.snapshot()
    #expect(original.meals.isEmpty && original.profiles.isEmpty && original.drafts.isEmpty)
    let clock = FixedClock("2026-10-17T11:23:00Z")
    var meal = Meal(time: RecordTime(clock: clock))
    meal.note = "只有文字的晚餐"
    let asset1 = try await store.preparePhoto(imageFixture())
    let asset2 = try await store.preparePhoto(imageFixture(orientation: 6))
    meal.photoIDs = [asset2.id, asset1.id]
    var workout = Workout(time: meal.time)
    workout.exercises = [Exercise(name: "引体向上", kind: .bodyweight, sets: [WorkoutSet(reps: 8, completed: true), WorkoutSet(reps: 7, completed: true)])]
    let energy = WorkoutEnergy(weightKG: nil, minutes: nil, intensity: .regular, profileVersionID: nil, kcal: nil, algorithmVersion: "met-net-v1", createdAt: clock.now)
    workout.energyHistory = [energy]; workout.currentEnergyID = energy.id
    let profile = ProfileVersion(effectiveDay: meal.time.localDay, sequence: 1, profile: BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2), createdAt: clock.now)
    let estimate = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual, items: [FoodItem(name: "整餐", grams: nil, kcal: 600)], totalKcal: 600, createdAt: clock.now)
    meal.currentEstimateID = estimate.id
    meal.deletedAt = clock.now
    meal.lifecycleEpoch = 1
    let goal = GoalStage(startDay: meal.time.localDay, goal: .maintain, sequence: 1)
    let draft = RecordDraft(content: .workout(workout), savedAt: clock.now)
    let tombstone = DeletionTombstone(source: SourceIdentity(datasetID: original.dataset.id, entityID: UUID(), kind: "meal"), deletedAt: clock.now)
    let inputMeal = meal, inputWorkout = workout
    try await store.commit(id: UUID()) { state in
        state.meals = [inputMeal]; state.workouts = [inputWorkout]; state.photos = [asset1, asset2]
        state.profiles = [profile]
        state.estimates = [estimate]; state.goals = [goal]; state.drafts = [draft]; state.tombstones = [tombstone]
    }
    let secondConnection = try await LocalRepository.open(at: root)
    let restored = try await secondConnection.snapshot()
    #expect(restored.dataset.id == original.dataset.id)
    #expect(restored.dataset.revision == 1)
    #expect(restored.meals == [meal])
    #expect(restored.workouts == [workout])
    #expect(restored.profiles == [profile])
    #expect(restored.estimates == [estimate] && restored.goals == [goal])
    #expect(restored.drafts == [draft] && restored.tombstones == [tombstone])
    #expect(restored.workouts[0].energyHistory[0].kcal == nil)
}

@Test func failedEditKeepsOriginalValueAndRejectsDuplicateDrafts() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let store = try await LocalRepository.open(at: root)
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "原值"
    let value = meal
    try await store.commit(id: UUID()) { $0.meals = [value] }
    let failing = try await LocalRepository.open(at: root, fault: { _ in throw CocoaError(.fileWriteOutOfSpace) })
    await #expect(throws: CocoaError.self) { try await failing.commit(id: UUID()) { $0.meals[0].note = "未保存的改动" } }
    #expect(try await failing.snapshot().meals[0].note == "原值")
    let fresh = try await LocalRepository.open(at: root)
    #expect(try await fresh.snapshot().meals[0].note == "原值")
    let workout = Workout(time: meal.time)
    let draft = RecordDraft(content: .workout(workout), savedAt: clock.now)
    await #expect(throws: DomainError.conflict) {
        try await fresh.commit(id: UUID()) {
            $0.drafts = [draft, RecordDraft(content: .workout(workout), savedAt: clock.now)]
        }
    }
    #expect(try await fresh.snapshot().drafts.isEmpty)
}

final class FailOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true
    func check(_ point: CommitPoint) throws {
        guard case .beforeSave = point else { return }
        lock.lock(); defer { lock.unlock() }
        if shouldFail { shouldFail = false; throw CocoaError(.fileWriteOutOfSpace) }
    }
}

@Test func failedSaveRollsBackAndRetryCommitsOnlyOnceAcrossRestart() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let failure = FailOnce()
    let store = try await LocalRepository.open(at: root, fault: { try failure.check($0) })
    let meal = Meal(time: RecordTime(clock: FixedClock("2026-10-17T12:00:00Z")))
    let operation = UUID()
    await #expect(throws: CocoaError.self) { try await store.commit(id: operation) { $0.meals.append(meal) } }
    let failed = try await store.snapshot()
    #expect(failed.meals.isEmpty && failed.dataset.revision == 0)
    let result = try await store.commit(id: operation) { $0.meals.append(meal) }
    #expect(result.revision == 1 && !result.alreadyCommitted)
    let reopened = try await LocalRepository.open(at: root)
    let duplicate = try await reopened.commit(id: operation) { $0.meals.append(meal) }
    #expect(duplicate.alreadyCommitted && duplicate.revision == 1)
    #expect(try await reopened.snapshot().meals.count == 1)
}

@Test func serialCommitsRejectStaleRevision() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    try await store.commit(id: UUID(), expectedRevision: 0) { _ in }
    await #expect(throws: DomainError.conflict) { try await store.commit(id: UUID(), expectedRevision: 0) { _ in } }
    #expect(try await store.snapshot().dataset.revision == 1)
}
