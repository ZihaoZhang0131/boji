import SwiftUI
import BojiDomain

struct ProfileView: View {
    let workspace: WorkspaceModel
    let clock: any AppClock
    @Environment(\.dismiss) private var dismiss
    @State private var sex: FormulaSex?
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var activity: Decimal?
    @State private var target = ""
    @State private var effectiveDate: Date
    @State private var error: String?
    @State private var saving = false
    @State private var confirming = false
    @State private var operationID = UUID()
    @State private var versionID = UUID()
    @FocusState private var focusedField: String?

    init(workspace: WorkspaceModel, clock: any AppClock) {
        self.workspace = workspace; self.clock = clock
        _effectiveDate = State(initialValue: clock.now)
        if let value = ProfileRules.effective(on: LocalDay(clock.now, timeZone: clock.timeZone), versions: workspace.snapshot?.profiles ?? [])?.profile {
            _sex = State(initialValue: value.sex); _age = State(initialValue: String(value.age))
            _height = State(initialValue: value.heightCM.description); _weight = State(initialValue: value.weightKG.description)
            _activity = State(initialValue: value.activityFactor); _target = State(initialValue: value.targetKcal?.description ?? "")
        }
    }

    var body: some View {
        MinePage {
            MineSection {
                VStack(spacing: 0) {
                    MineFieldRow(title: "性别") {
                        Picker("性别（公式参数）", selection: $sex) {
                            Text("请选择").tag(FormulaSex?.none)
                            Text("男性公式").tag(FormulaSex?.some(.male))
                            Text("女性公式").tag(FormulaSex?.some(.female))
                        }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44).accessibilityIdentifier("profile.sex")
                    }
                    Divider()
                    numeric("年龄（岁）", text: $age, keyboard: .numberPad, unit: "岁")
                    Divider()
                    numeric("身高（cm）", text: $height, unit: "cm")
                    Divider()
                    numeric("体重（kg）", text: $weight, unit: "kg")
                    Divider()
                    MineFieldRow(title: "日常活动") {
                        Picker("日常活动水平", selection: $activity) {
                            Text("请选择").tag(Decimal?.none)
                            Text("较少活动 · 1.2").tag(Decimal?.some(1.2))
                            Text("一般活动 · 1.35").tag(Decimal?.some(1.35))
                            Text("较多活动 · 1.5").tag(Decimal?.some(1.5))
                        }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44).accessibilityIdentifier("profile.activity")
                    }
                }
                Text("日常活动不含训练，运动净消耗另计。").font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            MineSection("摄入目标") {
                numeric("每日摄入目标（kcal，可留空）", text: $target, unit: "kcal")
                Text("留空即未设置，阶段目标不会自动填入数值。").font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            MineSection("生效日期") {
                DatePicker("资料开始生效", selection: $effectiveDate, in: ...clock.now, displayedComponents: .date)
                    .datePickerStyle(.compact).frame(minHeight: 44).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Text("今天生效不影响历史日常基线；训练保留当次体重。").font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            if let profile = try? input() {
                MineSection("估算预览") {
                    MineFieldRow(title: "静息估算") { estimate(EnergyRules.resting(profile)) }
                    MineFieldRow(title: "日常消耗基线") { estimate(EnergyRules.baseline(profile)) }
                    MineDisclosure("估算说明") {
                        Text("静息估算不等于每日摄入目标。日常基线包含日常活动，训练净消耗另计。")
                            .font(.footnote).foregroundStyle(PixelTheme.subtle).padding(.top, 8)
                    }.frame(minHeight: 44)
                }
            }
            MineDisclosure("历史版本") {
                if let versions = workspace.snapshot?.profiles, !versions.isEmpty {
                    ForEach(versions.sorted { $0.sequence > $1.sequence }) { version in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(version.effectiveDay.description + " 起生效")
                            Text("\(version.profile.weightKG.description) kg · \(version.profile.heightCM.description) cm")
                                .font(.footnote).foregroundStyle(PixelTheme.subtle)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                } else { Text("还没有个人资料").font(.footnote).padding(.top, 8) }
            }.frame(minHeight: 44)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let error { Text(error).font(.footnote).accessibilityIdentifier("profile.error") }
                Button(saving ? "正在保存" : "保存资料") {
                    do { _ = try input(); error = nil; if effectiveDay < today { confirming = true } else { Task { await save() } } }
                    catch { self.error = error.userMessage }
                }.buttonStyle(MineActionStyle(prominent: true)).disabled(saving).accessibilityIdentifier("profile.save")
            }.padding(.horizontal, 16).padding(.vertical, 12).background(PixelTheme.canvas)
        }
        .navigationTitle("身体资料").scrollDismissesKeyboard(.interactively)
        .recordingKeyboard { focusedField = nil }
        .confirmationDialog("确认回溯修改日常基线？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认并保存") { Task { await save() } }
        } message: { Text(impactDescription) }
    }
    private func estimate(_ value: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value.map(String.init) ?? "未知").monospacedDigit()
            Text("kcal／天").font(.footnote).foregroundStyle(PixelTheme.subtle)
        }
    }

    private var today: LocalDay { LocalDay(clock.now, timeZone: clock.timeZone) }
    private var effectiveDay: LocalDay { LocalDay(effectiveDate, timeZone: clock.timeZone) }
    private var impactDescription: String {
        let range = ProfileRules.affectedInterval(start: effectiveDay, versions: workspace.snapshot?.profiles ?? [])
        let ending = range.endExclusive.map { "至 \($0.adding(days: -1).description)" } ?? "起的后续日期"
        return "将改变 \(range.start.description)\(ending)的日常消耗基线；已有训练快照保持原值。"
    }
    private func numeric(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .decimalPad, unit: String) -> some View {
        MineFieldRow(title: String(label.split(separator: "（")[0])) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(label, text: text, prompt: Text(label.contains("可留空") ? "选填" : "填写").foregroundStyle(PixelTheme.subtle))
                    .keyboardType(keyboard).multilineTextAlignment(.trailing)
                    .frame(minWidth: 64, maxWidth: 140, minHeight: 44)
                    .accessibilityLabel(label).accessibilityIdentifier("profile.field." + label).focused($focusedField, equals: label)
                Text(unit).font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
        }
    }
    private func input() throws -> BodyProfile {
        guard let sex, let age = Int(age), let height = DecimalInput.parse(height), let weight = DecimalInput.parse(weight), let activity else { throw DomainError.invalidValue("请填写完整且有效的公式参数") }
        let targetValue = target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : DecimalInput.parse(target)
        if !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetValue == nil { throw DomainError.invalidValue("摄入目标不是有效数字") }
        let result = BodyProfile(sex: sex, age: age, heightCM: height, weightKG: weight, activityFactor: activity, targetKcal: targetValue)
        try EnergyRules.validate(result)
        return result
    }
    private func save() async {
        guard !saving else { return }
        saving = true; defer { saving = false }
        do {
            let profile = try input()
            let repository = try await workspace.activeRepository()
            try await repository.saveProfile(profile, effectiveDay: effectiveDay, today: today, backdateConfirmed: true, at: clock.now, operationID: operationID, versionID: versionID)
            try await workspace.refresh()
            dismiss()
        } catch { self.error = error.userMessage }
    }
}

enum DecimalInput {
    static func parse(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Error {
    var userMessage: String {
        if let domain = self as? DomainError {
            if case .invalidValue(let message) = domain { return message }
            if case .conflict = domain { return "资料已经变化，请重新打开后再试。" }
        }
        return "未能保存，输入仍保留。请重试。"
    }
}
