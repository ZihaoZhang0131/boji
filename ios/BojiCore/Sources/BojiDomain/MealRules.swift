import Foundation

public enum MealRules {
    public static func validate(_ meal: Meal) throws {
        guard !meal.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !meal.photoIDs.isEmpty else { throw DomainError.invalidValue("请添加照片或写一句话") }
        guard meal.photoIDs.count <= 9, Set(meal.photoIDs).count == meal.photoIDs.count else { throw DomainError.invalidValue("每餐最多九张不同照片") }
        guard (0...23).contains(meal.time.hour), (0...59).contains(meal.time.minute) else { throw DomainError.invalidValue("记录时间无效") }
    }

    public static func edited(_ draft: Meal, original: Meal) throws -> Meal {
        try validate(draft)
        guard draft.id == original.id, original.deletedAt == nil, draft.lifecycleEpoch == original.lifecycleEpoch,
              draft.factsRevision == original.factsRevision else { throw DomainError.conflict }
        var value = original
        value.time = draft.time; value.note = draft.note; value.slot = draft.slot; value.tags = draft.tags; value.photoIDs = draft.photoIDs
        let inputChanged = draft.note != original.note || draft.photoIDs != original.photoIDs || draft.inputRevision > original.inputRevision
        let factsChanged = inputChanged || draft.time != original.time || draft.slot != original.slot || draft.tags != original.tags
        if factsChanged { value.factsRevision += 1 }
        if inputChanged { value.inputRevision = max(original.inputRevision + 1, draft.inputRevision); value.currentEstimateID = nil }
        return value
    }
}

public enum FoodEstimateRules {
    public static func total(_ items: [FoodItem]) throws -> Decimal {
        guard !items.isEmpty else { throw DomainError.invalidValue("至少保留一个食物项") }
        for item in items {
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  EnergyRules.isFinite(item.kcal), item.kcal >= 0,
                  item.grams.map({ EnergyRules.isFinite($0) && $0 >= 0 }) ?? true else { throw DomainError.invalidValue("食物项名称、克数或热量无效") }
        }
        let total = items.reduce(Decimal.zero) { $0 + $1.kcal }
        guard EnergyRules.isFinite(total), total <= 10000 else { throw DomainError.invalidValue("整餐热量不能超过 10000 kcal") }
        return total
    }
    public static func validate(_ revision: EstimateRevision) throws {
        guard try total(revision.items) == revision.totalKcal else { throw DomainError.invalidValue("项目热量与整餐合计不一致") }
        if let range = revision.range {
            guard EnergyRules.isFinite(range.low), EnergyRules.isFinite(range.high), range.low >= 0,
                  range.low <= revision.totalKcal, revision.totalKcal <= range.high else { throw DomainError.invalidValue("估算范围无效") }
        }
    }
    public static func changingGrams(_ item: FoodItem, to grams: Decimal) throws -> FoodItem {
        guard EnergyRules.isFinite(grams), grams >= 0 else { throw DomainError.invalidValue("克数无效") }
        guard let reference = item.referenceGrams, EnergyRules.isFinite(reference), reference > 0,
              EnergyRules.isFinite(item.referenceKcal), item.referenceKcal >= 0 else { throw DomainError.invalidValue("原克数未知或为零，请直接确认热量") }
        var value = item; value.grams = grams; value.kcal = item.referenceKcal * grams / reference
        _ = try total([value])
        return value
    }
    public static func settingCalories(_ item: FoodItem, to kcal: Decimal, grams: Decimal?) throws -> FoodItem {
        var value = item
        value.kcal = kcal; value.grams = grams; value.referenceGrams = grams; value.referenceKcal = kcal
        _ = try total([value])
        return value
    }
}
