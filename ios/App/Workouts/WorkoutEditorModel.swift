import Foundation
import Observation
import BojiDomain
import BojiPersistence

@MainActor @Observable
final class WorkoutEditorModel: Identifiable {
    let id = UUID()
    private(set) var workout: Workout
    private(set) var fields: WorkoutDraftFields
    private(set) var profiles: [ProfileVersion]
    var error: String?
    var busy = false
    private let original: Workout?
    private let repository: LocalRepository
    private let clock: any AppClock
    private let operationID = UUID()

    private init(workout: Workout, original: Workout?, profiles: [ProfileVersion], repository: LocalRepository, clock: any AppClock) {
        self.workout = workout; self.original = original
        self.profiles = profiles; self.repository = repository; self.clock = clock
        var input = WorkoutDraftFields()
        for set in workout.exercises.flatMap(\.sets) {
            input.weightText[set.id] = set.weightKG?.description ?? ""
            input.repsText[set.id] = set.reps.map(String.init) ?? ""
        }
        if let energy = workout.energyHistory.first(where: { $0.id == workout.currentEnergyID }) {
            input.minutesText = energy.minutes?.description ?? ""; input.intensity = energy.intensity
        }
        fields = input
    }
    static func open(repository: LocalRepository, clock: any AppClock, day: LocalDay, editing: Workout? = nil, copying: Workout? = nil) async throws -> WorkoutEditorModel {
        let state = try await repository.snapshot()
        // Retire old-version training drafts. New form input lives only in this editor.
        for draft in state.drafts where draft.content.kind == .workout {
            try await repository.discardDraft(id: draft.id, at: clock.now, operationID: UUID())
        }
        let workout = editing ?? copying.map { WorkoutRules.copy($0, clock: clock) } ?? Workout(time: RecordTime(clock: clock, selectedDay: day))
        return WorkoutEditorModel(workout: workout, original: editing, profiles: state.profiles, repository: repository, clock: clock)
    }
    var isEditing: Bool { original != nil }
    var oldEnergy: WorkoutEnergy? { original?.energyHistory.first { $0.id == original?.currentEnergyID } }
    var profile: ProfileVersion? { ProfileRules.effective(on: workout.time.localDay, versions: profiles) }
    var weight: Decimal? { isEditing && !fields.reestimate ? oldEnergy?.weightKG : profile?.profile.weightKG }
    var preview: Int? { EnergyRules.netWorkout(weightKG: weight, minutes: DecimalInput.parse(fields.minutesText), intensity: fields.intensity) }
    var reestimatePreview: Int? { EnergyRules.netWorkout(weightKG: profile?.profile.weightKG, minutes: DecimalInput.parse(fields.minutesText), intensity: fields.intensity) }
    var selectedDate: Date {
        get { workout.time.instant ?? workout.time.localDay.date(in: clock.timeZone) }
        set {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: workout.time.timeZoneIdentifier) ?? clock.timeZone
            workout.time.localDay = LocalDay(newValue, timeZone: calendar.timeZone)
            workout.time.hour = calendar.component(.hour, from: newValue); workout.time.minute = calendar.component(.minute, from: newValue)
            workout.time.instant = newValue
        }
    }
    func setName(_ value: String) { workout.name = value }
    func setMinutes(_ value: String) { fields.minutesText = value }
    func setIntensity(_ value: TrainingIntensity) { fields.intensity = value }
    func setReestimate() { fields.reestimate = true }
    func addExercise(name: String, kind: ExerciseKind) {
        let exercise = Exercise(name: name, kind: kind, weightConvention: kind == .bodyweight ? "自重" : "总重量（kg）", sets: [WorkoutSet()])
        workout.exercises.append(exercise)
    }
    func setExerciseName(_ id: UUID, value: String) { if let i = exerciseIndex(id) { workout.exercises[i].name = value } }
    func setConvention(_ id: UUID, value: String) { if let i = exerciseIndex(id) { workout.exercises[i].weightConvention = value } }
    func removeExercise(_ id: UUID) { workout.exercises.removeAll { $0.id == id } }
    func moveExercise(_ id: UUID, earlier: Bool) {
        guard let i = exerciseIndex(id) else { return }; let next = earlier ? i - 1 : i + 1
        guard workout.exercises.indices.contains(next) else { return }; workout.exercises.swapAt(i, next)
    }
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
    func batch(exerciseID: UUID, count: String, reps: String, weight: String) -> Bool {
        guard let i = exerciseIndex(exerciseID) else { return false }
        do {
            guard let count = Int(count), let reps = Int(reps) else { throw DomainError.invalidValue("组数和次数须为整数") }
            let sets = try WorkoutRules.batch(count: count, weightKG: DecimalInput.parse(weight), reps: reps, kind: workout.exercises[i].kind)
            workout.exercises[i].sets.append(contentsOf: sets)
            for set in sets { fields.weightText[set.id] = set.weightKG?.description ?? ""; fields.repsText[set.id] = set.reps.map(String.init) ?? "" }
            error = nil; return true
        } catch { self.error = error.userMessage; return false }
    }
    func save() async -> Bool {
        guard !busy else { return false }; busy = true; defer { busy = false }
        do {
            let minutes = fields.minutesText.isEmpty ? nil : DecimalInput.parse(fields.minutesText)
            if !fields.minutesText.isEmpty && minutes == nil { throw DomainError.invalidValue("请填写有效时长，或留空待估算") }
            try await repository.saveWorkout(workout, minutes: minutes, intensity: fields.intensity, reestimate: fields.reestimate, at: clock.now, operationID: operationID)
            return true
        } catch { self.error = error.userMessage; return false }
    }
    private func exerciseIndex(_ id: UUID) -> Int? { workout.exercises.firstIndex { $0.id == id } }
}
