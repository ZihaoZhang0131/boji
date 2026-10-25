import XCTest
import BojiDomain
import BojiPersistence
@testable import Boji

@MainActor
final class WorkoutEditorTests: XCTestCase {
    func testInputNeverPersistsAndOneSaveValidatesEverySet() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LocalRepository.open(at: root), clock = SystemClock()
        let day = LocalDay(clock.now, timeZone: clock.timeZone)
        let first = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day)
        first.addExercise(name: "引体向上", kind: .bodyweight)
        let exercise = first.workout.exercises[0], set = exercise.sets[0]
        first.setInput(exerciseID: exercise.id, setID: set.id, reps: "8.5")
        let invalid = await first.save(); XCTAssertFalse(invalid); XCTAssertNotNil(first.error)
        let pending = try await store.snapshot()
        XCTAssertTrue(pending.workouts.isEmpty)
        XCTAssertTrue(HomePresentation.entries(on: day, in: pending).isEmpty)
        XCTAssertTrue(pending.drafts.isEmpty)
        let reopenedStore = try await LocalRepository.open(at: root)
        let blank = try await WorkoutEditorModel.open(repository: reopenedStore, clock: clock, day: day)
        XCTAssertTrue(blank.workout.exercises.isEmpty); XCTAssertTrue(blank.workout.name.isEmpty)
        first.setInput(exerciseID: exercise.id, setID: set.id, reps: "8")
        first.addSet(exercise.id, copying: true)
        let saved = await first.save(); XCTAssertTrue(saved)
        let snapshot = try await store.snapshot()
        XCTAssertTrue(snapshot.drafts.isEmpty); XCTAssertEqual(snapshot.workouts.count, 1)
        XCTAssertEqual(snapshot.workouts[0].exercises[0].sets.count, 2)
        XCTAssertTrue(snapshot.workouts[0].exercises[0].sets.allSatisfy(\.completed))
        XCTAssertNil(snapshot.workouts[0].energyHistory[0].kcal)
    }

    func testEditingChangesSavedRecordOnlyAfterSaveAndNeverDuplicatesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LocalRepository.open(at: root), clock = SystemClock()
        let day = LocalDay(clock.now, timeZone: clock.timeZone)
        let input = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day)
        input.setName("上肢训练"); input.addExercise(name: "俯卧撑", kind: .bodyweight)
        let exercise = input.workout.exercises[0], set = exercise.sets[0]
        input.setInput(exerciseID: exercise.id, setID: set.id, reps: "10")
        let saved = await input.save(); XCTAssertTrue(saved)
        let original = try await store.snapshot().workouts[0]
        let editor = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day, editing: original)
        editor.setName("修改后的训练")
        editor.setInput(exerciseID: exercise.id, setID: set.id, reps: "12")
        editor.addSet(exercise.id, copying: false)
        let invalid = await editor.save(); XCTAssertFalse(invalid)
        let unchanged = try await store.snapshot()
        XCTAssertEqual(unchanged.workouts, [original]); XCTAssertTrue(unchanged.drafts.isEmpty)
        let reopened = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day, editing: original)
        XCTAssertEqual(reopened.workout, original)
        if case .workout(let visible) = HomePresentation.entries(on: day, in: unchanged)[0].event { XCTAssertEqual(visible, original) }
        else { XCTFail("Expected saved workout") }
        editor.removeSet(exerciseID: exercise.id, setID: editor.workout.exercises[0].sets[1].id)
        let updated = await editor.save(); XCTAssertTrue(updated)
        let result = try await store.snapshot()
        XCTAssertEqual(result.workouts.count, 1); XCTAssertEqual(result.workouts[0].id, original.id)
        XCTAssertEqual(result.workouts[0].name, "修改后的训练")
        XCTAssertEqual(result.workouts[0].exercises[0].sets[0].reps, 12)
        XCTAssertTrue(result.drafts.isEmpty)
    }
    func testLegacyPendingInputIsRemovedWithoutChangingSavedRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LocalRepository.open(at: root), clock = SystemClock()
        let day = LocalDay(clock.now, timeZone: clock.timeZone)
        var saved = Workout(time: RecordTime(clock: clock))
        saved.name = "已保存的训练"
        saved.exercises = [Exercise(name: "俯卧撑", kind: .bodyweight, sets: [WorkoutSet(reps: 8)])]
        try await store.saveWorkout(saved, minutes: nil, intensity: .regular, reestimate: false, at: clock.now, operationID: UUID())
        let original = try await store.snapshot().workouts[0]
        var oldInput = original; oldInput.name = "旧版未保存修改"
        try await store.saveDraft(RecordDraft(editingRecordID: original.id, content: .workout(oldInput), savedAt: clock.now), operationID: UUID())
        let editor = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day, editing: original)
        XCTAssertEqual(editor.workout, original)
        let result = try await store.snapshot()
        XCTAssertTrue(result.drafts.isEmpty); XCTAssertEqual(result.workouts, [original])
    }

}
