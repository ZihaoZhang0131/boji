import Foundation

public enum EnergyRules {
    public static let workoutAlgorithm = "met-net-v1"
    public static func isFinite(_ value: Decimal) -> Bool { !value.isNaN && NSDecimalNumber(decimal: value).doubleValue.isFinite }
    public static func rounded(_ value: Decimal) -> Int {
        var value = value, result = Decimal()
        NSDecimalRound(&result, &value, 0, .plain)
        return NSDecimalNumber(decimal: result).intValue
    }
    public static func validate(_ profile: BodyProfile) throws {
        guard (18...59).contains(profile.age) else { throw DomainError.invalidValue("当前公式适用于 18—59 岁") }
        guard isFinite(profile.heightCM), (100...230).contains(profile.heightCM) else { throw DomainError.invalidValue("身高须为 100—230 cm") }
        guard isFinite(profile.weightKG), (30...250).contains(profile.weightKG) else { throw DomainError.invalidValue("体重须为 30—250 kg") }
        guard [Decimal(string: "1.2")!, Decimal(string: "1.35")!, Decimal(string: "1.5")!].contains(profile.activityFactor) else { throw DomainError.invalidValue("请选择有效的日常活动水平") }
        if let target = profile.targetKcal, !isFinite(target) || !(1...10000).contains(target) { throw DomainError.invalidValue("摄入目标须为 1—10000 kcal，或留空") }
    }
    public static func resting(_ profile: BodyProfile?) -> Int? {
        guard let profile, (try? validate(profile)) != nil else { return nil }
        return rounded(10 * profile.weightKG + Decimal(string: "6.25")! * profile.heightCM - 5 * Decimal(profile.age) + (profile.sex == .male ? 5 : -161))
    }
    public static func baseline(_ profile: BodyProfile?) -> Int? {
        guard let profile, let resting = resting(profile) else { return nil }
        return rounded(Decimal(resting) * profile.activityFactor)
    }
    public static func netWorkout(weightKG: Decimal?, minutes: Decimal?, intensity: TrainingIntensity) -> Int? {
        guard let weightKG, let minutes, isFinite(weightKG), (30...250).contains(weightKG), isFinite(minutes), minutes > 0, minutes <= 360 else { return nil }
        return rounded((intensity.met - 1) * Decimal(string: "3.5")! * weightKG / 200 * minutes)
    }
    public static func workoutSnapshot(weightKG: Decimal?, minutes: Decimal?, intensity: TrainingIntensity, profileID: UUID?, at now: Date) throws -> WorkoutEnergy {
        if let minutes, !isFinite(minutes) || minutes <= 0 || minutes > 360 { throw DomainError.invalidValue("时长须大于 0 且不超过 360 分钟") }
        if let weightKG, !isFinite(weightKG) || !(30...250).contains(weightKG) { throw DomainError.invalidValue("体重须为 30—250 kg") }
        return WorkoutEnergy(weightKG: weightKG, minutes: minutes, intensity: intensity, profileVersionID: profileID,
                             kcal: netWorkout(weightKG: weightKG, minutes: minutes, intensity: intensity), algorithmVersion: workoutAlgorithm, createdAt: now)
    }
}

public enum ProfileRules {
    public static func effective(on day: LocalDay, versions: [ProfileVersion]) -> ProfileVersion? {
        versions.filter { $0.effectiveDay <= day }.max { ($0.effectiveDay, $0.sequence) < ($1.effectiveDay, $1.sequence) }
    }
    public static func affectedInterval(start: LocalDay, versions: [ProfileVersion]) -> (start: LocalDay, endExclusive: LocalDay?) {
        (start, versions.filter { $0.effectiveDay > start }.map(\.effectiveDay).min())
    }
    public static func validateEffectiveDay(_ day: LocalDay, today: LocalDay) throws {
        guard day <= today else { throw DomainError.invalidValue("资料生效日期不能晚于今天") }
    }
}

public enum GoalRules {
    public static func effective(on day: LocalDay, stages: [GoalStage]) -> GoalStage? {
        stages.filter { $0.startDay <= day && ($0.endDay == nil || day < $0.endDay!) }.max { ($0.startDay, $0.sequence) < ($1.startDay, $1.sequence) }
    }
    public static func update(stages: [GoalStage], goal: Goal, start: LocalDay, note: String, today: LocalDay, sequence: Int64, id: UUID = UUID()) throws -> [GoalStage] {
        guard start <= today else { throw DomainError.invalidValue("阶段开始日期不能晚于今天") }
        var result = stages
        if let current = stages.filter({ $0.endDay == nil }).max(by: { $0.sequence < $1.sequence }), let index = result.firstIndex(where: { $0.id == current.id }) {
            guard start >= current.startDay else { throw DomainError.invalidValue("新阶段不能早于当前阶段") }
            if current.goal == goal && current.startDay == start { result[index].note = note; return result }
            result[index].endDay = start
        }
        var stage = GoalStage(id: id, startDay: start, goal: goal, sequence: sequence); stage.note = note
        result.append(stage)
        return result
    }
}
