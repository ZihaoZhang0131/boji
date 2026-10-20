import Foundation

public enum WorkoutRules {
    public static func validate(_ set: WorkoutSet, kind: ExerciseKind) throws {
        guard let reps = set.reps, (1...999).contains(reps) else { throw DomainError.invalidValue("次数须为 1—999 的整数") }
        if kind == .weighted {
            guard let weight = set.weightKG, EnergyRules.isFinite(weight), (0...1000).contains(weight) else { throw DomainError.invalidValue("负重须为 0—1000 kg") }
        } else if set.weightKG != nil { throw DomainError.invalidValue("自重动作不填写外加重量") }
    }
    public static func confirming(_ set: WorkoutSet, kind: ExerciseKind) throws -> WorkoutSet {
        try validate(set, kind: kind)
        var result = set; result.completed = true; return result
    }
    public static func reference(from previous: WorkoutSet) -> WorkoutSet {
        WorkoutSet(weightKG: previous.weightKG, reps: previous.reps, completed: false)
    }
    public static func batch(count: Int, weightKG: Decimal?, reps: Int, kind: ExerciseKind) throws -> [WorkoutSet] {
        guard (1...30).contains(count) else { throw DomainError.invalidValue("批量组数须为 1—30 的整数") }
        let value = try confirming(WorkoutSet(weightKG: kind == .weighted ? weightKG : nil, reps: reps), kind: kind)
        return (0..<count).map { _ in WorkoutSet(weightKG: value.weightKG, reps: value.reps, completed: true) }
    }
    public static func completedExercises(_ exercises: [Exercise]) throws -> [Exercise] {
        var result: [Exercise] = []
        for exercise in exercises {
            var value = exercise; value.sets = value.sets.filter(\.completed)
            guard !value.sets.isEmpty else { continue }
            guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DomainError.invalidValue("请填写动作名称") }
            if value.kind == .weighted, value.weightConvention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw DomainError.invalidValue("请填写负重口径") }
            for set in value.sets { try validate(set, kind: value.kind) }
            result.append(value)
        }
        guard !result.isEmpty else { throw DomainError.invalidValue("请至少确认完成一组，再结束训练") }
        return result
    }
    public static func copy(_ original: Workout, clock: any AppClock) -> Workout {
        var value = Workout(time: RecordTime(clock: clock)); value.name = original.name
        value.exercises = original.exercises.map { exercise in
            Exercise(name: exercise.name, kind: exercise.kind, weightConvention: exercise.weightConvention,
                     sets: exercise.sets.map { reference(from: $0) })
        }
        return value
    }
}
