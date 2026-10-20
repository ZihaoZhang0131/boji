import Foundation
import Observation
import BojiDomain
import BojiPersistence

enum WorkoutEditorError: Error { case activeDraft }

@MainActor @Observable
final class WorkoutEditorModel: Identifiable {
    let id: UUID
    private(set) var workout: Workout
    private(set) var fields: WorkoutDraftFields
    private(set) var profiles: [ProfileVersion]
    var error: String?
    var busy = false
    var saveStatus: DraftSaveStatus = .idle
    private var draft: RecordDraft
    private let original: Workout?
    private let repository: LocalRepository
    private let autosaver: DraftAutosaver
    private let clock: any AppClock
    private let operationID = UUID()

    private init(draft: RecordDraft, workout: Workout, original: Workout?, profiles: [ProfileVersion], repository: LocalRepository, clock: any AppClock) {
        self.id = draft.id; self.draft = draft; self.workout = workout; self.original = original
        self.profiles = profiles; self.repository = repository; self.clock = clock
        autosaver = DraftAutosaver(repository: repository, clock: clock)
        var input = draft.workoutFields ?? WorkoutDraftFields()
        if draft.workoutFields == nil {
            for set in workout.exercises.flatMap(\.sets) { input.weightText[set.id] = set.weightKG?.description ?? ""; input.repsText[set.id] = set.reps.map(String.init) ?? "" }
            if let energy = workout.energyHistory.first(where: { $0.id == workout.currentEnergyID }) { input.minutesText = energy.minutes?.description ?? ""; input.intensity = energy.intensity }
        }
        fields = input
    }
    static func open(repository: LocalRepository, clock: any AppClock, day: LocalDay, editing: Workout? = nil, copying: Workout? = nil) async throws -> WorkoutEditorModel {
        let state = try await repository.snapshot()
        if let existing = state.drafts.first(where: { $0.content.kind == .workout }), case .workout(let value) = existing.content {
            if copying != nil || (editing != nil && existing.editingRecordID != editing?.id) { throw WorkoutEditorError.activeDraft }
            return WorkoutEditorModel(draft: existing, workout: value, original: state.workouts.first { $0.id == existing.editingRecordID }, profiles: state.profiles, repository: repository, clock: clock)
        }
        let workout = editing ?? copying.map { WorkoutRules.copy($0, clock: clock) } ?? Workout(time: RecordTime(clock: clock, selectedDay: day))
        let draft = RecordDraft(editingRecordID: editing?.id, content: .workout(workout), savedAt: clock.now)
        return WorkoutEditorModel(draft: draft, workout: workout, original: editing, profiles: state.profiles, repository: repository, clock: clock)
    }
    var isEditing: Bool { draft.editingRecordID != nil }
    var completedCount: Int { workout.exercises.flatMap(\.sets).filter(\.completed).count }
    var oldEnergy: WorkoutEnergy? { original?.energyHistory.first { $0.id == original?.currentEnergyID } }
    var profile: ProfileVersion? { ProfileRules.effective(on: workout.time.localDay, versions: profiles) }
    var weight: Decimal? { isEditing && !fields.reestimate ? oldEnergy?.weightKG : profile?.profile.weightKG }
    var preview: Int? { EnergyRules.netWorkout(weightKG: weight, minutes: DecimalInput.parse(fields.minutesText), intensity: fields.intensity) }
    var reestimatePreview: Int? { EnergyRules.netWorkout(weightKG: profile?.profile.weightKG, minutes: DecimalInput.parse(fields.minutesText), intensity: fields.intensity) }
    var statusText: String {
        switch saveStatus { case .idle: "尚未修改"; case .saving: "草稿保存中"; case .saved: "草稿已保存"; case .failed(let value): value }
    }
    func observeStatus() async {
        while !Task.isCancelled {
            let latest = await autosaver.status; if latest != saveStatus { saveStatus = latest }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        }
    }
    var selectedDate: Date {
        get { workout.time.instant ?? workout.time.localDay.date(in: clock.timeZone) }
        set {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: workout.time.timeZoneIdentifier) ?? clock.timeZone
            workout.time.localDay = LocalDay(newValue, timeZone: calendar.timeZone)
            workout.time.hour = calendar.component(.hour, from: newValue); workout.time.minute = calendar.component(.minute, from: newValue)
            workout.time.instant = newValue; schedule()
        }
    }
    func setName(_ value: String) { workout.name = value; schedule() }
    func setMinutes(_ value: String) { fields.minutesText = value; schedule() }
    func setIntensity(_ value: TrainingIntensity) { fields.intensity = value; schedule() }
    func setReestimate() { fields.reestimate = true; schedule() }
    func addExercise(name: String, kind: ExerciseKind) {
        let exercise = Exercise(name: name, kind: kind, weightConvention: kind == .bodyweight ? "自重" : "总重量（kg）", sets: [WorkoutSet()])
        workout.exercises.append(exercise); schedule()
    }
    func setExerciseName(_ id: UUID, value: String) { if let i = exerciseIndex(id) { workout.exercises[i].name = value; schedule() } }
    func setConvention(_ id: UUID, value: String) { if let i = exerciseIndex(id) { workout.exercises[i].weightConvention = value; schedule() } }
    func removeExercise(_ id: UUID) { workout.exercises.removeAll { $0.id == id }; schedule() }
    func moveExercise(_ id: UUID, earlier: Bool) {
        guard let i = exerciseIndex(id) else { return }; let next = earlier ? i - 1 : i + 1
        guard workout.exercises.indices.contains(next) else { return }; workout.exercises.swapAt(i, next); schedule()
    }
    func addSet(_ exerciseID: UUID, copying: Bool) {
        guard let i = exerciseIndex(exerciseID) else { return }
        let set = copying ? workout.exercises[i].sets.last.map { WorkoutRules.reference(from: $0) } ?? WorkoutSet() : WorkoutSet()
        workout.exercises[i].sets.append(set); fields.weightText[set.id] = set.weightKG?.description ?? ""; fields.repsText[set.id] = set.reps.map(String.init) ?? ""; schedule()
    }
    func setInput(exerciseID: UUID, setID: UUID, weight: String? = nil, reps: String? = nil) {
        guard let i = exerciseIndex(exerciseID), let j = workout.exercises[i].sets.firstIndex(where: { $0.id == setID }) else { return }
        if let weight { fields.weightText[setID] = weight; workout.exercises[i].sets[j].weightKG = DecimalInput.parse(weight) }
        if let reps { fields.repsText[setID] = reps; workout.exercises[i].sets[j].reps = Int(reps) }
        workout.exercises[i].sets[j].completed = false; schedule()
    }
    func toggleSet(exerciseID: UUID, setID: UUID) {
        guard let i = exerciseIndex(exerciseID), let j = workout.exercises[i].sets.firstIndex(where: { $0.id == setID }) else { return }
        do {
            if workout.exercises[i].sets[j].completed { workout.exercises[i].sets[j].completed = false }
            else { workout.exercises[i].sets[j] = try WorkoutRules.confirming(workout.exercises[i].sets[j], kind: workout.exercises[i].kind) }
            error = nil; schedule()
        } catch { self.error = error.userMessage }
    }
    func removeSet(exerciseID: UUID, setID: UUID) {
        guard let i = exerciseIndex(exerciseID) else { return }; workout.exercises[i].sets.removeAll { $0.id == setID }; fields.weightText.removeValue(forKey: setID); fields.repsText.removeValue(forKey: setID); schedule()
    }
    func batch(exerciseID: UUID, count: String, reps: String, weight: String) -> Bool {
        guard let i = exerciseIndex(exerciseID) else { return false }
        do {
            guard let count = Int(count), let reps = Int(reps) else { throw DomainError.invalidValue("组数和次数须为整数") }
            let sets = try WorkoutRules.batch(count: count, weightKG: DecimalInput.parse(weight), reps: reps, kind: workout.exercises[i].kind)
            workout.exercises[i].sets.append(contentsOf: sets)
            for set in sets { fields.weightText[set.id] = set.weightKG?.description ?? ""; fields.repsText[set.id] = set.reps.map(String.init) ?? "" }
            error = nil; schedule(); return true
        } catch { self.error = error.userMessage; return false }
    }
    func flush() async throws { draft.content = .workout(workout); draft.workoutFields = fields; await autosaver.changed(draft); try await autosaver.flush(); saveStatus = await autosaver.status }
    func finish() async -> Bool {
        guard !busy else { return false }; busy = true; defer { busy = false }
        do {
            _ = try WorkoutRules.completedExercises(workout.exercises)
            let minutes = fields.minutesText.isEmpty ? nil : DecimalInput.parse(fields.minutesText)
            if !fields.minutesText.isEmpty && minutes == nil { throw DomainError.invalidValue("请填写有效时长，或留空待估算") }
            try await flush()
            try await repository.finishWorkout(workout, draftID: id, minutes: minutes, intensity: fields.intensity, reestimate: fields.reestimate, at: clock.now, operationID: operationID)
            return true
        } catch { self.error = error.userMessage; return false }
    }
    func discard() async -> Bool {
        guard !busy else { return false }; busy = true; defer { busy = false }
        do { try await autosaver.discard(draftID: id); return true } catch { self.error = error.userMessage; return false }
    }
    private func exerciseIndex(_ id: UUID) -> Int? { workout.exercises.firstIndex { $0.id == id } }
    private func schedule() {
        draft.revision += 1; draft.content = .workout(workout); draft.workoutFields = fields; draft.savedAt = clock.now
        let pending = draft; saveStatus = .saving; Task { await autosaver.changed(pending) }
    }
}
