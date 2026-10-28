import Foundation
import Observation
import BojiDomain
import BojiPersistence

@MainActor @Observable
final class WorkoutEditorModel: Identifiable {
    let id = UUID()
    private(set) var workout: Workout
    private(set) var fields: WorkoutDraftFields
    var error: String?
    var busy = false
    private let original: Workout?
    private let repository: LocalRepository
    private let clock: any AppClock
    private let operationID = UUID()

    private init(workout: Workout, original: Workout?, repository: LocalRepository, clock: any AppClock) {
        self.workout = workout; self.original = original
        self.repository = repository; self.clock = clock
        var input = WorkoutDraftFields()
        for set in workout.exercises.flatMap(\.sets) {
            input.weightText[set.id] = set.weightKG?.description ?? ""
            input.repsText[set.id] = set.reps.map(String.init) ?? ""
        }
        fields = input
    }
    static func open(repository: LocalRepository, clock: any AppClock, day: LocalDay, editing: Workout? = nil, copying: Workout? = nil) async throws -> WorkoutEditorModel {
        let state = try await repository.snapshot()
        // Retire old-version training drafts. New form input lives only in this editor.
        for draft in state.drafts where draft.content.kind == .workout {
            try await repository.discardDraft(id: draft.id, at: clock.now, operationID: UUID())
        }
        var workout = editing ?? copying.map { WorkoutRules.copy($0, clock: clock) } ?? Workout(time: RecordTime(clock: clock, selectedDay: day))
        if editing == nil && copying != nil { workout.time = RecordTime(clock: clock, selectedDay: day) }
        return WorkoutEditorModel(workout: workout, original: editing, repository: repository, clock: clock)
    }
    var isEditing: Bool { original != nil }
    func setName(_ value: String) { workout.name = value }
    func addExercise(name: String, kind: ExerciseKind) {
        let exercise = Exercise(name: name, kind: kind, weightConvention: kind == .bodyweight ? "自重" : name.contains("哑铃") ? "单只重量（kg）" : "总重量（kg）", sets: [WorkoutSet()])
        workout.exercises.append(exercise)
    }
    func removeExercise(_ id: UUID) { workout.exercises.removeAll { $0.id == id } }
    func addSet(_ exerciseID: UUID, copying: Bool) {
        guard let i = exerciseIndex(exerciseID) else { return }
        let set = copying ? workout.exercises[i].sets.last.map { WorkoutRules.reference(from: $0) } ?? WorkoutSet() : WorkoutSet()
        workout.exercises[i].sets.append(set); fields.weightText[set.id] = set.weightKG?.description ?? ""; fields.repsText[set.id] = set.reps.map(String.init) ?? ""
    }
    func setInput(exerciseID: UUID, setID: UUID, weight: String? = nil, reps: String? = nil) {
        guard let i = exerciseIndex(exerciseID), let j = workout.exercises[i].sets.firstIndex(where: { $0.id == setID }) else { return }
        if let weight { fields.weightText[setID] = weight; workout.exercises[i].sets[j].weightKG = DecimalInput.parse(weight) }
        if let reps { fields.repsText[setID] = reps; workout.exercises[i].sets[j].reps = Int(reps) }
        workout.exercises[i].sets[j].completed = false
    }
    func removeSet(exerciseID: UUID, setID: UUID) {
        guard let i = exerciseIndex(exerciseID) else { return }; workout.exercises[i].sets.removeAll { $0.id == setID }; fields.weightText.removeValue(forKey: setID); fields.repsText.removeValue(forKey: setID)
    }
    var firstInvalidInput: (field: String?, message: String)? {
        guard !workout.exercises.isEmpty else { return (nil, "请添加至少一个动作") }
        for exercise in workout.exercises {
            for (index, set) in exercise.sets.enumerated() {
                let prefix = exercise.name + "第 \(index + 1) 组："
                if exercise.kind == .weighted, set.weightKG == nil || !EnergyRules.isFinite(set.weightKG!) || !(0...1000).contains(set.weightKG!) {
                    return (set.id.uuidString + ".weight", prefix + "请填写 0–1000 kg 的重量")
                }
                if set.reps == nil || !(1...999).contains(set.reps!) {
                    return (set.id.uuidString + ".reps", prefix + "次数须为 1–999 的整数")
                }
            }
        }
        return nil
    }
    func removeLastSet(_ exerciseID: UUID) {
        guard let exercise = workout.exercises.first(where: { $0.id == exerciseID }), exercise.sets.count > 1,
              let last = exercise.sets.last else { return }
        removeSet(exerciseID: exerciseID, setID: last.id)
    }
    func save() async -> Bool {
        guard !busy else { return false }; busy = true; defer { busy = false }
        do {
            if let issue = firstInvalidInput { throw DomainError.invalidValue(issue.message) }
            try await repository.saveWorkout(workout, at: clock.now, operationID: operationID)
            return true
        } catch { self.error = error.userMessage; return false }
    }
    private func exerciseIndex(_ id: UUID) -> Int? { workout.exercises.firstIndex { $0.id == id } }
}
