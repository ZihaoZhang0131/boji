import Foundation
import Testing
import BojiDomain
import BojiPersistence

@Test func inputVersionsAndManualHistoryPreserveSources() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock))
    await #expect(throws: DomainError.self) { try await store.saveMeal(meal, draftID: nil, operationID: UUID()) }
    meal.note = "下午一杯拿铁"
    let operation = UUID()
    try await store.saveMeal(meal, draftID: nil, operationID: operation)
    try await store.saveMeal(meal, draftID: nil, operationID: operation)
    try await store.saveManualEstimate(recordID: meal.id, expectedInputRevision: 0, items: [FoodItem(name: "拿铁", grams: nil, kcal: 200)], at: clock.now, operationID: UUID(), estimateID: UUID())
    var edited = try await store.snapshot().meals[0]
    edited.slot = "下午茶"
    try await store.saveMeal(edited, draftID: nil, operationID: UUID())
    #expect(try await store.snapshot().meals[0].currentEstimateID != nil)
    #expect(try await store.snapshot().meals[0].inputRevision == 0)
    edited = try await store.snapshot().meals[0]
    edited.note = "只喝了一半拿铁"
    try await store.saveMeal(edited, draftID: nil, operationID: UUID())
    let state = try await store.snapshot()
    #expect(state.meals.count == 1 && state.meals[0].currentEstimateID == nil && state.meals[0].inputRevision == 1)
    #expect(state.estimates.count == 1 && state.estimates[0].totalKcal == 200)
}

@Test func portionEditingUsesOriginalReferenceWithoutRoundingDrift() throws {
    let item = FoodItem(name: "米饭", grams: 100, kcal: 200)
    let larger = try FoodEstimateRules.changingGrams(item, to: 150)
    #expect(larger.kcal == 300)
    let small = try FoodEstimateRules.changingGrams(larger, to: Decimal(string: "33.333")!)
    let back = try FoodEstimateRules.changingGrams(small, to: 100)
    #expect(back.kcal == 200)
    #expect(throws: DomainError.self) { try FoodEstimateRules.changingGrams(FoodItem(name: "整餐", grams: nil, kcal: 200), to: 150) }
    #expect(throws: DomainError.self) { try FoodEstimateRules.total([FoodItem(name: "", grams: nil, kcal: 1)]) }
    #expect(throws: DomainError.self) { try FoodEstimateRules.total([FoodItem(name: "超限", grams: nil, kcal: 10001)]) }
}

@Test func mealFactsAndRecognitionInputsHaveSeparateRevisions() throws {
    var original = Meal(time: RecordTime(clock: FixedClock("2026-10-17T12:00:00Z")))
    original.photoIDs = [UUID(), UUID()]; original.currentEstimateID = UUID()
    var metadata = original
    metadata.time.localDay = original.time.localDay.adding(days: -1); metadata.slot = "午餐"; metadata.tags = ["补记"]
    let moved = try MealRules.edited(metadata, original: original)
    #expect(moved.inputRevision == original.inputRevision && moved.currentEstimateID == original.currentEstimateID)
    var reordered = original; reordered.photoIDs.reverse()
    let changed = try MealRules.edited(reordered, original: original)
    #expect(changed.inputRevision == 1 && changed.currentEstimateID == nil)
    var restoredText = original; restoredText.inputRevision = 2
    #expect(try MealRules.edited(restoredText, original: original).currentEstimateID == nil)
    #expect(throws: DomainError.conflict) { try MealRules.edited(metadata, original: changed) }
    var tooMany = original; tooMany.photoIDs = (0..<10).map { _ in UUID() }
    #expect(throws: DomainError.self) { try MealRules.validate(tooMany) }
    for value in [Decimal.nan, -1, 10001] {
        #expect(throws: DomainError.self) { try FoodEstimateRules.total([FoodItem(name: "整餐", grams: nil, kcal: value)]) }
    }
}

@Test func textOnlyMealReopensWithSelectedTimeAndClassification() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let clock = FixedClock("2026-10-17T12:00:00Z"), day = try LocalDay(year: 2026, month: 10, day: 2)
    var meal = Meal(time: RecordTime(clock: clock, selectedDay: day)); meal.note = "下午一杯无糖拿铁"; meal.slot = "下午茶"; meal.tags = ["补记"]
    let operation = UUID()
    try await store.saveMeal(meal, draftID: nil, operationID: operation)
    let reopened = try await LocalRepository.open(at: root)
    try await reopened.saveMeal(meal, draftID: nil, operationID: operation)
    let records = try await reopened.snapshot().meals
    #expect(records == [meal] && records[0].time.timeZoneIdentifier == "Asia/Shanghai")
    #expect(records[0].time.localDay == day && records[0].time.displayTime == "20:00")
}

@Test func manualCorrectionsKeepOriginalModelRevisionAndEveryConfirmedChange() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "米饭"
    var model = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .model, items: [FoodItem(name: "米饭", grams: 100, kcal: 200)], totalKcal: 200, createdAt: clock.now)
    model.provider = "test-fixture"; model.model = "fixture-only"
    meal.currentEstimateID = model.id
    let originalMeal = meal, originalEstimate = model
    try await store.commit(id: UUID()) { $0.meals = [originalMeal]; $0.estimates = [originalEstimate] }
    let firstID = UUID(), secondID = UUID()
    try await store.saveManualEstimate(recordID: meal.id, expectedInputRevision: 0, items: [FoodEstimateRules.changingGrams(model.items[0], to: 150)], at: clock.now.addingTimeInterval(1), operationID: UUID(), estimateID: firstID)
    try await store.saveManualEstimate(recordID: meal.id, expectedInputRevision: 0, items: [FoodItem(name: "整餐", grams: nil, kcal: 250)], at: clock.now.addingTimeInterval(2), operationID: UUID(), estimateID: secondID)
    let state = try await store.snapshot()
    #expect(state.estimates.count == 3 && state.estimates.first(where: { $0.id == model.id }) == model)
    #expect(state.estimates.first(where: { $0.id == firstID })?.previousRevisionID == model.id)
    #expect(state.estimates.first(where: { $0.id == secondID })?.previousRevisionID == firstID)
    #expect(state.meals[0].currentEstimateID == secondID && state.meals[0].manualRevision == 2)
}
