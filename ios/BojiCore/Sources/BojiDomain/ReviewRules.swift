import Foundation

public struct DayReview: Codable, Equatable, Identifiable, Sendable {
    public var id: String { day.description }
    public let day: LocalDay
    public let datasetRevision: Int64
    public let mealCount: Int
    public let pendingMeals: Int
    public let knownIntakeKcal: Decimal
    public let workoutCount: Int
    public let completedSetCount: Int
    public let pendingWorkouts: Int
    public let knownWorkoutKcal: Int
    public let baselineKcal: Int?
    public let totalBurnKcal: Int?
    public let confirmed: Bool
    public let complete: Bool
    public let differenceKcal: Decimal?
    public let targetKcal: Decimal?
    public let goal: GoalStage?
    public let missingReasons: [String]
}

public struct ReviewRange: Codable, Equatable, Sendable {
    public let days: [DayReview]
    public var completeDayCount: Int { days.filter(\.complete).count }
    public var averageIntakeKcal: Decimal? {
        let complete = days.filter(\.complete)
        return complete.isEmpty ? nil : complete.reduce(0) { $0 + $1.knownIntakeKcal } / Decimal(complete.count)
    }
    public var pendingWorkoutCount: Int { days.reduce(0) { $0 + $1.pendingWorkouts } }
    public var knownWorkoutKcal: Int { days.reduce(0) { $0 + $1.knownWorkoutKcal } }
}

public enum ReviewRules {
    public static func effectiveEstimate(for meal: Meal, in state: DatasetSnapshot) -> EstimateRevision? {
        guard let value = state.estimates.first(where: { $0.id == meal.currentEstimateID && $0.recordID == meal.id && $0.inputRevision == meal.inputRevision && $0.source != .demo }),
              (try? FoodEstimateRules.validate(value)) != nil else { return nil }
        return value
    }
    public static func day(_ day: LocalDay, in state: DatasetSnapshot) -> DayReview {
        let meals = state.activeMeals.filter { $0.time.localDay == day }
        let workouts = state.activeWorkouts.filter { $0.time.localDay == day }
        let estimates = meals.compactMap { effectiveEstimate(for: $0, in: state) }
        let intake = estimates.reduce(Decimal.zero) { $0 + $1.totalKcal }
        let energies = workouts.compactMap { workout -> Int? in
            guard let value = workout.energyHistory.first(where: { $0.id == workout.currentEnergyID }), let kcal = value.kcal, kcal >= 0 else { return nil }; return kcal
        }
        let profile = ProfileRules.effective(on: day, versions: state.profiles)?.profile
        let baseline = EnergyRules.baseline(profile)
        let knownWorkout = energies.reduce(0, +)
        let pendingMeals = meals.count - estimates.count, pendingWorkouts = workouts.count - energies.count
        let burn = pendingWorkouts == 0 ? baseline.map { $0 + knownWorkout } : nil
        let confirmed = state.confirmations.contains { $0.day == day }
        let complete = confirmed && !meals.isEmpty && pendingMeals == 0 && pendingWorkouts == 0
        var missing: [String] = []
        if meals.isEmpty { missing.append("没有饮食记录") }
        if pendingMeals > 0 { missing.append("\(pendingMeals) 餐待估算") }
        if pendingWorkouts > 0 { missing.append("\(pendingWorkouts) 次训练待估算") }
        if baseline == nil { missing.append("缺少当日有效身体资料") }
        if !confirmed { missing.append("尚未确认已记全") }
        return DayReview(day: day, datasetRevision: state.dataset.revision, mealCount: meals.count, pendingMeals: pendingMeals,
            knownIntakeKcal: intake, workoutCount: workouts.count, completedSetCount: workouts.flatMap(\.exercises).flatMap(\.sets).filter(\.completed).count,
            pendingWorkouts: pendingWorkouts, knownWorkoutKcal: knownWorkout, baselineKcal: baseline, totalBurnKcal: burn,
            confirmed: confirmed, complete: complete, differenceKcal: complete ? burn.map { intake - Decimal($0) } : nil,
            targetKcal: profile?.targetKcal, goal: GoalRules.effective(on: day, stages: state.goals), missingReasons: missing)
    }
    public static func range(ending end: LocalDay, count: Int, in state: DatasetSnapshot) throws -> ReviewRange {
        guard [7, 30].contains(count) else { throw DomainError.invalidValue("请选择 7 或 30 天") }
        return ReviewRange(days: (0..<count).map { day(end.adding(days: $0 - count + 1), in: state) })
    }
}

public enum TimelineEvent: Identifiable, Sendable {
    case meal(Meal), workout(Workout)
    public var id: String { switch self { case .meal(let value): "meal/\(value.id)"; case .workout(let value): "workout/\(value.id)" } }
    public var time: RecordTime { switch self { case .meal(let value): value.time; case .workout(let value): value.time } }
}

public enum RecordQuery {
    public static func timeline(on day: LocalDay, in state: DatasetSnapshot) -> [TimelineEvent] {
        let values = state.activeMeals.filter { $0.time.localDay == day }.map(TimelineEvent.meal) + state.activeWorkouts.filter { $0.time.localDay == day }.map(TimelineEvent.workout)
        return values.sorted { ($0.time.hour, $0.time.minute, $0.id) > ($1.time.hour, $1.time.minute, $1.id) }
    }
    public static func meals(search: String, photosOnly: Bool = false, in state: DatasetSnapshot) -> [Meal] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.activeMeals.filter { meal in
            (!photosOnly || !meal.photoIDs.isEmpty) && (query.isEmpty || ([meal.note, meal.slot ?? ""] + meal.tags).contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { ($0.time.localDay, $0.time.hour, $0.time.minute, $0.id.uuidString) > ($1.time.localDay, $1.time.hour, $1.time.minute, $1.id.uuidString) }
    }
}
