import Foundation
import Testing
import BojiDomain
import BojiPersistence

@Test func incompleteIntakeAndUnknownBurnAreNotZero() throws {
    let clock = FixedClock("2026-10-17T12:00:00Z"), time = RecordTime(clock: FixedClock("2026-10-17T12:00:00Z"))
    var state = DatasetSnapshot()
    var known = Meal(time: time); known.note = "已知"
    let estimate = EstimateRevision(recordID: known.id, inputRevision: 0, source: .manual, items: [FoodItem(name: "整餐", grams: nil, kcal: 500)], totalKcal: 500, createdAt: clock.now)
    known.currentEstimateID = estimate.id
    var unknown = Meal(time: time); unknown.note = "未知"
    state.meals = [known, unknown]; state.estimates = [estimate]
    state.confirmations = [DayConfirmation(day: time.localDay, confirmedAt: clock.now, factsRevision: 0)]
    let result = ReviewRules.day(time.localDay, in: state)
    #expect(result.knownIntakeKcal == 500 && result.pendingMeals == 1 && !result.complete)
    #expect(result.totalBurnKcal == nil && result.differenceKcal == nil)
    state.profiles = [ProfileVersion(effectiveDay: time.localDay.adding(days: -10), sequence: 1, profile: BodyProfile(sex: .male, age: 28, heightCM: 175, weightKG: 70, activityFactor: 1.2), createdAt: clock.now)]
    state.meals = [known]
    let complete = ReviewRules.day(time.localDay, in: state)
    #expect(complete.complete && complete.totalBurnKcal == 1991 && complete.differenceKcal == -1491)
    var workout = Workout(time: time); workout.exercises = [Exercise(name: "自重", kind: .bodyweight, sets: [WorkoutSet(reps: 8, completed: true)])]
    state.workouts = [workout]
    let waiting = ReviewRules.day(time.localDay, in: state)
    #expect(waiting.pendingWorkouts == 1 && waiting.totalBurnKcal == nil && !waiting.complete)
    state.workouts = []; state.meals = []
    #expect(!ReviewRules.day(time.localDay, in: state).complete)
}

@Test func twoCompleteDaysAverageAndSearchUseOnlyFormalFacts() throws {
    let clock = FixedClock("2026-10-17T12:00:00Z"), day = RecordTime(clock: FixedClock("2026-10-17T12:00:00Z")).localDay
    var state = DatasetSnapshot()
    for offset in 0..<2 {
        var meal = Meal(time: RecordTime(clock: clock, selectedDay: day.adding(days: -offset))); meal.note = "Latte \(offset)"; meal.tags = ["咖啡"]
        let kcal = Decimal(500 + offset * 200)
        let revision = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual, items: [FoodItem(name: "整餐", grams: nil, kcal: kcal)], totalKcal: kcal, createdAt: clock.now)
        meal.currentEstimateID = revision.id; state.meals.append(meal); state.estimates.append(revision)
        state.confirmations.append(DayConfirmation(day: meal.time.localDay, confirmedAt: clock.now, factsRevision: 0))
    }
    let range = try ReviewRules.range(ending: day, count: 7, in: state)
    #expect(range.days.count == 7 && range.days.last?.day == day)
    #expect(range.completeDayCount == 2 && range.averageIntakeKcal == 600)
    #expect(try JSONDecoder().decode(ReviewRange.self, from: JSONEncoder().encode(range)) == range)
    #expect(RecordQuery.meals(search: "LATTE", in: state).count == 2)
    #expect(RecordQuery.meals(search: "咖啡", in: state).count == 2)
    #expect(RecordQuery.meals(search: "", photosOnly: true, in: state).isEmpty)
    state.meals[0].deletedAt = clock.now
    #expect(RecordQuery.meals(search: "", in: state).count == 1)
    #expect(RecordQuery.timeline(on: day, in: state).isEmpty)
}

@Test func confirmationsSurviveEstimatesButNotMovedFacts() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "文字餐食"
    let day = meal.time.localDay
    await #expect(throws: DomainError.self) { try await store.confirmDay(day, confirmed: true, at: clock.now, operationID: UUID()) }
    try await store.saveMeal(meal, draftID: nil, operationID: UUID())
    try await store.confirmDay(day, confirmed: true, at: clock.now, operationID: UUID())
    try await store.saveManualEstimate(recordID: meal.id, expectedInputRevision: 0, items: [FoodItem(name: "整餐", grams: nil, kcal: 0)], at: clock.now, operationID: UUID(), estimateID: UUID())
    #expect(try await store.snapshot().confirmations.count == 1)
    var other = Meal(time: RecordTime(clock: clock, selectedDay: day.adding(days: -1))); other.note = "新日期原有餐食"
    try await store.saveMeal(other, draftID: nil, operationID: UUID())
    try await store.confirmDay(other.time.localDay, confirmed: true, at: clock.now, operationID: UUID())
    #expect(try await store.snapshot().confirmations.count == 2)
    var moved = try #require(await store.snapshot().meals.first { $0.id == meal.id }); moved.time.localDay = day.adding(days: -1)
    try await store.saveMeal(moved, draftID: nil, operationID: UUID())
    let state = try await store.snapshot()
    #expect(state.confirmations.isEmpty && state.meals.first(where: { $0.id == meal.id })?.currentEstimateID != nil)
    #expect(RecordQuery.timeline(on: day, in: state).isEmpty)
    #expect(RecordQuery.timeline(on: moved.time.localDay, in: state).count == 2)
    #expect(ReviewRules.day(moved.time.localDay, in: state).pendingMeals == 1)
}

@Test func customReviewRangesIncludeBothEndpointsAndRejectInvalidSpans() throws {
    func day(_ value: String) throws -> LocalDay {
        let p = value.split(separator: "-").map { Int($0)! }
        return try LocalDay(year: p[0], month: p[1], day: p[2])
    }
    for (start, end, count) in [("2026-10-09", "2026-10-09", 1), ("2025-12-29", "2026-01-04", 7),
                               ("2024-02-28", "2024-03-01", 3), ("2026-03-07", "2026-03-09", 3),
                               ("2026-07-12", "2026-10-09", 90)] {
        let a = try day(start), b = try day(end)
        let range = try ReviewRules.range(starting: a, ending: b, in: DatasetSnapshot())
        #expect(range.days.count == count)
        #expect(range.days.first?.day == a && range.days.last?.day == b)
        #expect(Set(range.days.map(\.day)).count == count)
        #expect(try ReviewRules.range(ending: b, count: count, in: DatasetSnapshot()) == range)
    }
    let end = try day("2026-10-09")
    #expect(throws: DomainError.self) { try ReviewRules.range(starting: end.adding(days: -90), ending: end, in: DatasetSnapshot()) }
    #expect(throws: DomainError.self) { try ReviewRules.range(starting: end.adding(days: 1), ending: end, in: DatasetSnapshot()) }
    for count in [0, -1, 91] {
        #expect(throws: DomainError.self) { try ReviewRules.range(ending: end, count: count, in: DatasetSnapshot()) }
    }
}
