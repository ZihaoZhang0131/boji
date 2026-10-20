import SwiftUI
import BojiDomain

struct FoodItemInput: Identifiable {
    let id: UUID
    var name: String
    var grams: String
    var calories: String
    private var reference: FoodItem
    private(set) var error: String?

    init(_ item: FoodItem) {
        id = item.id; name = item.name; grams = item.grams?.description ?? ""; calories = item.kcal.description; reference = item
    }
    static func empty(name: String) -> FoodItemInput {
        var value = FoodItemInput(FoodItem(name: name, grams: nil, kcal: 0)); value.calories = ""; return value
    }
    mutating func setGrams(_ text: String) {
        grams = text; error = nil
        guard !text.isEmpty else { return }
        guard let value = DecimalInput.parse(text) else { error = "请输入有效克数"; return }
        // An unknown or zero original portion has no ratio. Keep calories for explicit confirmation.
        guard let original = reference.referenceGrams, original > 0 else { return }
        do { calories = try FoodEstimateRules.changingGrams(reference, to: value).kcal.description }
        catch { self.error = error.userMessage }
    }
    mutating func setCalories(_ text: String) {
        calories = text; error = nil
        guard let kcal = DecimalInput.parse(text) else { error = "请输入有效热量"; return }
        let amount = grams.isEmpty ? nil : DecimalInput.parse(grams)
        do { reference = try FoodEstimateRules.settingCalories(reference, to: kcal, grams: amount) }
        catch { self.error = error.userMessage }
    }
    func value() throws -> FoodItem {
        guard error == nil, let kcal = DecimalInput.parse(calories), grams.isEmpty || DecimalInput.parse(grams) != nil else { throw DomainError.invalidValue(error ?? "请检查克数和热量") }
        var item = reference; item.name = name; item.grams = grams.isEmpty ? nil : DecimalInput.parse(grams); item.kcal = kcal
        _ = try FoodEstimateRules.total([item]); return item
    }
}

struct ManualEstimateView: View {
    let meal: Meal
    let workspace: WorkspaceModel
    let clock: any AppClock
    let draftID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [FoodItemInput]
    @State private var error: String?
    @State private var saving = false
    @State private var operationID = UUID()
    @State private var estimateID = UUID()
    @FocusState private var focusedField: String?

    init(meal: Meal, initial: EstimateRevision?, workspace: WorkspaceModel, clock: any AppClock, draftID: UUID? = nil) {
        self.meal = meal; self.workspace = workspace; self.clock = clock; self.draftID = draftID
        _rows = State(initialValue: initial?.items.map(FoodItemInput.init) ?? [.empty(name: "整餐")])
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("可以只填写整餐热量，也可以分项记录。克数可留空；已知原克数时按原始比例换算，直接改热量会设定新的比例基准。")
                }
                ForEach($rows) { $row in
                    Section {
                        TextField("食物名称", text: $row.name).accessibilityLabel("食物名称")
                            .focused($focusedField, equals: row.id.uuidString + ".name")
                        TextField("克数（g，可留空）", text: Binding(get: { row.grams }, set: { row.setGrams($0) }))
                            .keyboardType(.decimalPad).accessibilityLabel("克数（g，可留空）")
                            .focused($focusedField, equals: row.id.uuidString + ".grams")
                        TextField("热量（kcal）", text: Binding(get: { row.calories }, set: { row.setCalories($0) }))
                            .keyboardType(.decimalPad).accessibilityLabel("热量（kcal）").accessibilityIdentifier("manual.calories")
                            .focused($focusedField, equals: row.id.uuidString + ".kcal")
                        if let message = row.error { Text(message) }
                        Button("删除食物项", role: .destructive) { rows.removeAll { $0.id == row.id } }.frame(minHeight: 44)
                    }
                }
                Section {
                    Button("添加食物项") { rows.append(.empty(name: "")) }.frame(minHeight: 44)
                    if let total = try? FoodEstimateRules.total(rows.map { try $0.value() }) { Text("整餐合计 \(total.description) kcal").accessibilityIdentifier("manual.total") }
                    if let error { Text(error).accessibilityIdentifier("manual.error") }
                    Button(saving ? "正在保存" : "保存人工热量") { Task { await save() } }
                        .frame(minHeight: 44).accessibilityIdentifier("manual.save")
                }
            }
            .disabled(saving)
            .scrollDismissesKeyboard(.interactively)
            .recordingKeyboard { focusedField = nil }
            .navigationTitle("人工热量")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) } }
        }.interactiveDismissDisabled(saving).font(PixelTheme.font()).tint(.primary)
    }
    private func save() async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do {
            let values = try rows.map { try $0.value() }; _ = try FoodEstimateRules.total(values)
            let repository = try await workspace.activeRepository()
            try await repository.saveManualEstimate(recordID: meal.id, expectedInputRevision: meal.inputRevision, items: values, at: clock.now, operationID: operationID, estimateID: estimateID, draftID: draftID)
            try await workspace.refresh(); dismiss()
        } catch { self.error = error.userMessage }
    }
}
