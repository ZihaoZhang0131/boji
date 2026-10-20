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
        Form {
            Section("身体资料") {
                Picker("性别（公式参数）", selection: $sex) {
                    Text("请选择").tag(FormulaSex?.none)
                    Text("男性公式").tag(FormulaSex?.some(.male))
                    Text("女性公式").tag(FormulaSex?.some(.female))
                }
                .accessibilityIdentifier("profile.sex")
                numeric("年龄（岁）", text: $age, keyboard: .numberPad)
                numeric("身高（cm）", text: $height)
                numeric("体重（kg）", text: $weight)
                Picker("日常活动水平", selection: $activity) {
                    Text("请选择").tag(Decimal?.none)
                    Text("较少活动 · 1.2").tag(Decimal?.some(1.2))
                    Text("一般活动 · 1.35").tag(Decimal?.some(1.35))
                    Text("较多活动 · 1.5").tag(Decimal?.some(1.5))
                }
                .accessibilityIdentifier("profile.activity")
                Text("日常活动估算不含已记录的训练。训练净消耗单独计算。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("自定摄入目标") {
                numeric("每日摄入目标（kcal，可留空）", text: $target)
                Text("留空表示未设置。阶段目标不会自动填入摄入数值。")
            }
            Section("生效日期") {
                DatePicker("资料开始生效", selection: $effectiveDate, in: ...clock.now, displayedComponents: .date)
                Text("今天修改资料不改变过去日期的日常基线。历史训练始终保留当次体重快照。")
            }
            if let profile = try? input() {
                Section("估算预览") {
                    LabeledContent("静息估算（kcal／天）", value: EnergyRules.resting(profile).map(String.init) ?? "未知")
                    LabeledContent("日常消耗基线（kcal／天）", value: EnergyRules.baseline(profile).map(String.init) ?? "未知")
                }
            }
            if let error { Section { Text(error).foregroundStyle(.primary).accessibilityIdentifier("profile.error") } }
            Section {
                Button(saving ? "正在保存" : "保存资料") {
                    do { _ = try input(); error = nil; if effectiveDay < today { confirming = true } else { Task { await save() } } }
                    catch { self.error = error.userMessage }
                }
                .disabled(saving)
                .frame(minHeight: 44)
                .accessibilityIdentifier("profile.save")
            }
            Section("历史版本") {
                if let versions = workspace.snapshot?.profiles, !versions.isEmpty {
                    ForEach(versions.sorted { $0.sequence > $1.sequence }) { version in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(version.effectiveDay.description + " 起生效")
                            Text("体重 \(version.profile.weightKG.description) kg · 身高 \(version.profile.heightCM.description) cm")
                        }
                    }
                } else { Text("还没有个人资料") }
            }
        }
        .navigationTitle("个人资料")
        .scrollDismissesKeyboard(.interactively)
        .recordingKeyboard { focusedField = nil }
        .confirmationDialog("确认回溯修改日常基线？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认并保存") { Task { await save() } }
        } message: { Text(impactDescription) }
    }

    private var today: LocalDay { LocalDay(clock.now, timeZone: clock.timeZone) }
    private var effectiveDay: LocalDay { LocalDay(effectiveDate, timeZone: clock.timeZone) }
    private var impactDescription: String {
        let range = ProfileRules.affectedInterval(start: effectiveDay, versions: workspace.snapshot?.profiles ?? [])
        let ending = range.endExclusive.map { "至 \($0.adding(days: -1).description)" } ?? "起的后续日期"
        return "将改变 \(range.start.description)\(ending)的日常消耗基线；已有训练快照保持原值。"
    }
    private func numeric(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .decimalPad) -> some View {
        VStack(alignment: .leading) {
            Text(label)
            TextField(label, text: text).keyboardType(keyboard).accessibilityLabel(label).frame(minHeight: 44)
                .accessibilityIdentifier("profile.field." + label)
                .focused($focusedField, equals: label)
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
