import Foundation

/// Versioned product assumptions, not measured exercise or rest time.
public struct WorkoutEstimateInputs: Codable, Equatable, Sendable {
    public var weightedReps: Int
    public var bodyweightReps: Int
    public var setCount: Int
    public var secondsPerRep: Decimal = 4
    public var restSeconds: Decimal = 60
    public var weightedMET: Decimal = 3.5
    public var bodyweightMET: Decimal = 3
    public var restMET: Decimal = 1.3

    public init(exercises: [Exercise]) {
        weightedReps = exercises.filter { $0.kind == .weighted }.flatMap(\.sets).reduce(0) { $0 + ($1.reps ?? 0) }
        bodyweightReps = exercises.filter { $0.kind == .bodyweight }.flatMap(\.sets).reduce(0) { $0 + ($1.reps ?? 0) }
        setCount = exercises.flatMap(\.sets).count
    }
    public var weightedMinutes: Decimal { Decimal(weightedReps) * secondsPerRep / 60 }
    public var bodyweightMinutes: Decimal { Decimal(bodyweightReps) * secondsPerRep / 60 }
    public var restMinutes: Decimal { Decimal(max(0, setCount - 1)) * restSeconds / 60 }
    public var minutes: Decimal {
        var value = (Decimal(weightedReps + bodyweightReps) * secondsPerRep + Decimal(max(0, setCount - 1)) * restSeconds) / 60
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .plain)
        return rounded
    }
    public var isValid: Bool {
        (1...100_000).contains(setCount) && (0...99_900_000).contains(weightedReps) &&
        (0...99_900_000).contains(bodyweightReps) && weightedReps + bodyweightReps >= setCount &&
        weightedReps + bodyweightReps <= setCount * 999 && secondsPerRep == 4 && restSeconds == 60 &&
        weightedMET == 3.5 && bodyweightMET == 3 && restMET == 1.3
    }
    public var supportedMinutes: Decimal? { isValid && minutes > 0 && minutes <= 360 ? minutes : nil }
}

extension EnergyRules {
    public static let automaticWorkoutAlgorithm = "sets-met-net-v1"

    public static func automaticWorkout(weightKG: Decimal?, inputs: WorkoutEstimateInputs) -> Int? {
        guard let weightKG, isFinite(weightKG), (30...250).contains(weightKG), inputs.supportedMinutes != nil else { return nil }
        let weighted = (inputs.weightedMET - 1) * Decimal(inputs.weightedReps) * inputs.secondsPerRep
        let bodyweight = (inputs.bodyweightMET - 1) * Decimal(inputs.bodyweightReps) * inputs.secondsPerRep
        let rest = (inputs.restMET - 1) * Decimal(max(0, inputs.setCount - 1)) * inputs.restSeconds
        let value = rounded((weighted + bodyweight + rest) * Decimal(string: "3.5")! * weightKG / 12000)
        return (0...100_000).contains(value) ? value : nil
    }

    public static func automaticWorkoutSnapshot(exercises: [Exercise], weightKG: Decimal?, profileID: UUID?, at now: Date) -> WorkoutEnergy {
        let inputs = WorkoutEstimateInputs(exercises: exercises)
        var result = WorkoutEnergy(weightKG: weightKG, minutes: inputs.supportedMinutes, intensity: .regular,
            profileVersionID: profileID, kcal: automaticWorkout(weightKG: weightKG, inputs: inputs),
            algorithmVersion: automaticWorkoutAlgorithm, createdAt: now)
        result.automaticInputs = inputs
        return result
    }
}
