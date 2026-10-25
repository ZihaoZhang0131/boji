import SwiftUI
import BojiDomain

struct WorkoutEditorView: View {
    @Bindable var model: WorkoutEditorModel
    let onSaved: (LocalDay) async -> Void
    let onClosed: () async -> Void
    var workspace: WorkspaceModel? = nil
    var clock: (any AppClock)? = nil
    var onReplaceEditor: ((WorkoutEditorModel) -> Void)? = nil
    var onRecordRemoved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDetails = false
    @State private var showingExercises = false
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    TextField("训练名称（可选）", text: Binding(get: { model.workout.name }, set: { model.setName($0) }))
                        .accessibilityIdentifier("workout.name").focused($focusedField, equals: "name").recordingField()
                    ForEach(model.workout.exercises) { exercise in exerciseSection(exercise) }
                    Button("添加动作") { focusedField = nil; showingExercises = true }
                        .frame(maxWidth: .infinity).buttonStyle(PixelButtonStyle()).accessibilityIdentifier("workout.addExercise")
                    metadata
                    if let error = model.error { Text(error).font(.footnote).accessibilityIdentifier("workout.error") }
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }
            .background(PixelTheme.canvas).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                RecordingSaveBar(disabled: model.busy, identifier: "workout.save") {
                    focusedField = nil
                    Task { if await model.save() { await onSaved(model.workout.time.localDay); dismiss() } }
                }
            }
            .disabled(model.busy).recordingKeyboard { focusedField = nil }
            .navigationTitle(model.isEditing ? "编辑训练" : "记训练").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("放弃") { Task { await onClosed(); dismiss() } }.disabled(model.busy).accessibilityIdentifier("workout.close")
                }
                if model.isEditing && workspace != nil && clock != nil && onReplaceEditor != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("详情") { focusedField = nil; showingDetails = true }.accessibilityIdentifier("workout.details")
                    }
                }
            }
            .navigationDestination(isPresented: $showingDetails) {
                if let workspace, let clock {
                    WorkoutDetailView(id: model.workout.id, workspace: workspace, clock: clock, embedded: true,
                                      onOpenEditor: onReplaceEditor, onRecordRemoved: onRecordRemoved)
                }
            }
        }
        .font(.body).tint(.primary).interactiveDismissDisabled(model.busy)
        .sheet(isPresented: $showingExercises) { ExercisePickerView(model: model) }
    }

    private var metadata: some View {
        VStack(spacing: 8) {
            Divider().padding(.bottom, 4)
            RecordingTimePicker(selection: Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 }))
                .datePickerStyle(.compact).frame(minHeight: 44)
            HStack {
                Text("时长").foregroundStyle(PixelTheme.subtle)
                Spacer()
                TextField("—", text: Binding(get: { model.fields.minutesText }, set: { model.setMinutes($0) }))
                    .keyboardType(.decimalPad).multilineTextAlignment(.center)
                    .frame(width: 72, height: 44).background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("实际时长（分钟，可留空）").focused($focusedField, equals: "minutes")
                Text("分钟").font(.subheadline).foregroundStyle(PixelTheme.subtle)
            }
            AnyLayout(dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                Text("强度").foregroundStyle(PixelTheme.subtle)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Picker("强度", selection: Binding(get: { model.fields.intensity }, set: { model.setIntensity($0) })) {
                    ForEach(TrainingIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(minHeight: 44)
            }
            AnyLayout(dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                Text("训练消耗").foregroundStyle(PixelTheme.subtle)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text(model.preview.map { "\($0) kcal" } ?? "待估算").monospacedDigit().accessibilityIdentifier("workout.energy.preview")
            }.frame(minHeight: 44)
        }
    }

    private func exerciseSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name).font(.headline)
                Spacer(minLength: 12)
                Button("删除") { model.removeExercise(exercise.id) }.font(.footnote).foregroundStyle(PixelTheme.subtle)
                    .frame(minWidth: 44, minHeight: 44).accessibilityLabel("删除" + exercise.name)
            }
            if exercise.kind == .weighted { Text(exercise.weightConvention).font(.caption).foregroundStyle(PixelTheme.subtle) }
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    Text("组").frame(width: 24)
                    if exercise.kind == .weighted { Text("kg").frame(maxWidth: .infinity) }
                    Text("次").frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 1)
                }.font(.caption).foregroundStyle(PixelTheme.subtle).accessibilityHidden(true)
            }
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("第 \(index + 1) 组"); Spacer(); removeSet(set, exercise: exercise, number: index + 1) }
                        setFields(set, exercise: exercise, number: index + 1)
                    }
                } else {
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.subheadline).foregroundStyle(PixelTheme.subtle).frame(width: 24)
                        setFields(set, exercise: exercise, number: index + 1)
                        removeSet(set, exercise: exercise, number: index + 1)
                    }
                }
            }
            Button("添加一组") { model.addSet(exercise.id, copying: true) }
                .font(.subheadline).foregroundStyle(PixelTheme.subtle).frame(minHeight: 44)
        }
    }
    @ViewBuilder private func setFields(_ set: WorkoutSet, exercise: Exercise, number: Int) -> some View {
        if exercise.kind == .weighted {
            if dynamicTypeSize.isAccessibilitySize { Text("重量 / kg").font(.caption).foregroundStyle(PixelTheme.subtle) }
            TextField("—", text: Binding(get: { model.fields.weightText[set.id] ?? "" }, set: { model.setInput(exerciseID: exercise.id, setID: set.id, weight: $0) }))
                .keyboardType(.decimalPad).accessibilityLabel("第 \(number) 组负重（kg）")
                .focused($focusedField, equals: set.id.uuidString + ".weight")
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                .background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        }
        if dynamicTypeSize.isAccessibilitySize { Text("次数").font(.caption).foregroundStyle(PixelTheme.subtle) }
        TextField("—", text: Binding(get: { model.fields.repsText[set.id] ?? "" }, set: { model.setInput(exerciseID: exercise.id, setID: set.id, reps: $0) }))
            .keyboardType(.numberPad).accessibilityLabel("第 \(number) 组次数")
            .focused($focusedField, equals: set.id.uuidString + ".reps")
            .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
            .background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private func removeSet(_ set: WorkoutSet, exercise: Exercise, number: Int) -> some View {
        Button { model.removeSet(exerciseID: exercise.id, setID: set.id) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
            .buttonStyle(.plain).foregroundStyle(PixelTheme.subtle).accessibilityLabel("删除第 \(number) 组")
    }
}

private struct ExercisePickerView: View {
    let model: WorkoutEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ExerciseKind = .weighted
    var body: some View {
        NavigationStack {
            List {
                ForEach(["杠铃卧推", "杠铃深蹲", "硬拉", "哑铃划船", "引体向上", "俯卧撑"], id: \.self) { title in
                    Button(title) { model.addExercise(name: title, kind: ["引体向上", "俯卧撑"].contains(title) ? .bodyweight : .weighted); dismiss() }
                        .frame(minHeight: 44)
                }.listRowSeparator(.hidden)
                Section {
                    TextField("其他动作", text: $name)
                    Picker("类型", selection: $kind) { Text("负重").tag(ExerciseKind.weighted); Text("自重").tag(ExerciseKind.bodyweight) }
                    Button("添加") { model.addExercise(name: name, kind: kind); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.listRowSeparator(.hidden)
            }.bojiForm().navigationTitle("添加动作").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } } }
        }.tint(.primary)
    }
}
