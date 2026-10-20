import XCTest
import BojiDomain
import BojiPersistence
@testable import Boji

@MainActor
final class WorkoutEditorTests: XCTestCase {
    func testIncompleteInputRestartsAndOnlyConfirmedGroupsFinish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await LocalRepository.open(at: root), clock = SystemClock()
        let day = LocalDay(clock.now, timeZone: clock.timeZone)
        let first = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day)
        first.addExercise(name: "引体向上", kind: .bodyweight)
        let exercise = first.workout.exercises[0], set = exercise.sets[0]
        first.setInput(exerciseID: exercise.id, setID: set.id, reps: "8.5")
        first.toggleSet(exerciseID: exercise.id, setID: set.id)
        XCTAssertEqual(first.completedCount, 0); XCTAssertNotNil(first.error)
        try await first.flush()
        let second = try await WorkoutEditorModel.open(repository: store, clock: clock, day: day)
        XCTAssertEqual(second.id, first.id); XCTAssertEqual(second.fields.repsText[set.id], "8.5")
        second.setInput(exerciseID: exercise.id, setID: set.id, reps: "8")
        second.toggleSet(exerciseID: exercise.id, setID: set.id)
        second.addSet(exercise.id, copying: true)
        XCTAssertEqual(second.completedCount, 1)
        let saved = await second.finish(); XCTAssertTrue(saved)
        let snapshot = try await store.snapshot()
        XCTAssertTrue(snapshot.drafts.isEmpty); XCTAssertEqual(snapshot.workouts.count, 1)
        XCTAssertEqual(snapshot.workouts[0].exercises[0].sets.count, 1)
        XCTAssertNil(snapshot.workouts[0].energyHistory[0].kcal)
    }
}
