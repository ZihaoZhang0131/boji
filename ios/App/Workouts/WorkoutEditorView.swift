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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var customName = ""
    @State private var customKind: ExerciseKind = .weighted
    @State private var discardConfirmation = false
    @State private var reestimateConfirmation = false
    @State private var batchExercise: Exercise?
    @State private var showingDetails = false
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("训练名称（可选）", text: Binding(get: { model.workout.name }, set: { model.setName($0) })).accessibilityIdentifier("workout.name")
                        .focused($focusedField, equals: "name")
                    Text("已确认 \(model.completedCount) 组 · 结束前均为草稿").font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("训练信息") {
                        DatePicker("训练日期和时间", selection: Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 }))
                        LabeledContent("时区", value: model.workout.time.timeZoneIdentifier).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(model.workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                    Section {
                        TextField("动作名称", text: Binding(get: { exercise.name }, set: { model.setExerciseName(exercise.id, value: $0) })).accessibilityLabel("动作名称")
                            .font(PixelTheme.font(18, relativeTo: .headline))
                            .focused($focusedField, equals: exercise.id.uuidString + ".name")
                        if exercise.kind == .weighted {
                            DisclosureGroup {
                                TextField("重量口径", text: Binding(get: { exercise.weightConvention }, set: { model.setConvention(exercise.id, value: $0) })).accessibilityLabel("重量口径，例如总重量或单侧")
                                    .focused($focusedField, equals: exercise.id.uuidString + ".convention")
                            } label: { Text(exercise.weightConvention.isEmpty ? "重量口径" : exercise.weightConvention).font(.footnote).foregroundStyle(.secondary) }
                        } else { Text("自重").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                            setRow(set, number: setIndex + 1, exercise: exercise)
                        }
                        Button { model.addSet(exercise.id, copying: false) } label: { Label("添加一组", systemImage: "plus") }.frame(minHeight: 44)
                        DisclosureGroup("更多操作") {
                            Button("沿用上一组（未完成）") { model.addSet(exercise.id, copying: true) }.frame(minHeight: 44).disabled(exercise.sets.isEmpty)
                            Button("批量补记完成组") { batchExercise = exercise }.frame(minHeight: 44)
                            ViewThatFits(in: .horizontal) {
                                HStack { exerciseActions(exercise, index: index) }
                                VStack(alignment: .leading) { exerciseActions(exercise, index: index) }
                            }
                            .buttonStyle(PixelButtonStyle())
                        }
                    }
                }
                Section("添加动作") {
                    Menu {
                        ForEach(["杠铃卧推", "杠铃深蹲", "硬拉", "哑铃划船"], id: \.self) { name in Button(name) { model.addExercise(name: name, kind: .weighted) } }
                        ForEach(["引体向上", "俯卧撑"], id: \.self) { name in Button(name + "（自重）") { model.addExercise(name: name, kind: .bodyweight) } }
                    } label: {
                        Text("常用动作").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    DisclosureGroup("自定义动作") {
                        TextField("自定义动作名称", text: $customName)
                            .focused($focusedField, equals: "customName")
                        Picker("动作类型", selection: $customKind) { Text("负重").tag(ExerciseKind.weighted); Text("自重").tag(ExerciseKind.bodyweight) }
                        Button("添加自定义动作") { model.addExercise(name: customName, kind: customKind); customName = "" }.frame(minHeight: 44)
                            .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("消耗") {
                    LabeledContent("运动净消耗") {
                        Text(model.preview.map { "\($0) kcal" } ?? "待估算")
                            .accessibilityIdentifier("workout.energy.preview")
                    }
                    TextField("实际时长（分钟，可留空）", text: Binding(get: { model.fields.minutesText }, set: { model.setMinutes($0) }))
                        .keyboardType(.decimalPad).accessibilityLabel("实际时长（分钟，可留空）")
                        .focused($focusedField, equals: "minutes")
                    Picker("训练类型", selection: Binding(get: { model.fields.intensity }, set: { model.setIntensity($0) })) {
                        ForEach(TrainingIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if model.fields.reestimate { Text("保存时按当次资料重新估算，旧值保留。").font(.footnote) }
                    DisclosureGroup("估算说明") {
                        Text(model.weight.map { "体重快照 \($0.description) kg" } ?? "当次体重未知，可先保存训练")
                        Text("已扣除同时段静息消耗；整次训练只计算一次。缺少时长或体重时保留未知。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if model.isEditing {
                            if !model.fields.reestimate { Text("沿用历史体重快照，当前资料的修改不会改变旧训练。").font(.footnote).foregroundStyle(.secondary) }
                            Button("用当次日期资料重新估算") { reestimateConfirmation = true }.frame(minHeight: 44)
                        } else if let profile = model.profile { Text("体重来源：\(profile.effectiveDay.description) 生效资料").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Text(model.statusText).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("workout.draftStatus")
                    if let error = model.error { Text(error).accessibilityIdentifier("workout.error") }
                    if case .failed = model.saveStatus { Button("重试保存草稿") { Task { await close(flushOnly: true) } } }
                    Button(model.isEditing ? "保存训练修改" : "结束并保存训练") {
                        Task { if await model.finish() { await onSaved(model.workout.time.localDay); dismiss() } }
                    }.frame(minHeight: 44).accessibilityIdentifier("workout.finish")
                    Button(model.isEditing ? "放弃修改" : "放弃训练草稿", role: .destructive) { discardConfirmation = true }.frame(minHeight: 44)
                }
            }
            .bojiForm()
            .disabled(model.busy)
            .scrollDismissesKeyboard(.interactively)
            .recordingKeyboard { focusedField = nil }
            .navigationTitle(model.isEditing ? "编辑训练" : "记训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("收起") { Task { await close() } }.disabled(model.busy) }
                if model.isEditing && workspace != nil && clock != nil && onReplaceEditor != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("详情") { Task { await openDetails() } }
                            .disabled(model.busy)
                            .accessibilityLabel("训练详情与历史")
                            .accessibilityIdentifier("workout.details")
                    }
                }
            }
            .navigationDestination(isPresented: $showingDetails) {
                if let workspace, let clock {
                    WorkoutDetailView(id: model.workout.id, workspace: workspace, clock: clock,
                                      embedded: true, editingContext: model,
                                      onOpenEditor: onReplaceEditor, onRecordRemoved: onRecordRemoved)
                }
            }
            .confirmationDialog("放弃本次草稿？", isPresented: $discardConfirmation, titleVisibility: .visible) {
                Button("确认放弃", role: .destructive) { Task { if await model.discard() { await onClosed(); dismiss() } } }
            } message: { Text("已保存的正式训练保持原值。") }
            .confirmationDialog("确认重新估算？", isPresented: $reestimateConfirmation, titleVisibility: .visible) {
                Button("确认使用当次资料") { model.setReestimate() }
            } message: {
                Text("旧值：\(model.oldEnergy?.kcal.map { "\($0) kcal" } ?? "未知")；新值：\(model.reestimatePreview.map { "\($0) kcal" } ?? "未知")。新体重：\(model.profile?.profile.weightKG.description ?? "未知") kg。确认后仍需保存训练才会生效。")
            }
        }
        .interactiveDismissDisabled()
        .font(PixelTheme.font()).tint(.primary)
        .task { await model.observeStatus() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { do { try await model.flush() } catch { model.error = error.userMessage } } } }
        .sheet(item: $batchExercise) { exercise in BatchSetsView(exercise: exercise, model: model) }
    }
    private func setRow(_ set: WorkoutSet, number: Int, exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第 \(number) 组").font(.footnote).foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { setInputs(set, number: number, exercise: exercise) }
            } else {
                HStack(alignment: .top, spacing: 16) { setInputs(set, number: number, exercise: exercise) }
            }
            HStack {
                Button(set.completed ? "取消这组完成" : "确认这组完成") { model.toggleSet(exerciseID: exercise.id, setID: set.id) }
                    .buttonStyle(PixelButtonStyle()).accessibilityValue(set.completed ? "已完成" : "未完成")
                Spacer(minLength: 8)
                Menu {
                    Button("删除这组", role: .destructive) { model.removeSet(exerciseID: exercise.id, setID: set.id) }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("第 \(number) 组操作")
            }
        }.padding(.vertical, 8)
    }
    @ViewBuilder private func setInputs(_ set: WorkoutSet, number: Int, exercise: Exercise) -> some View {
        if exercise.kind == .weighted {
            VStack(alignment: .leading, spacing: 4) {
                Text("负重 / kg").font(.footnote).foregroundStyle(.secondary)
                TextField("负重（kg）", text: Binding(get: { model.fields.weightText[set.id] ?? "" }, set: { model.setInput(exerciseID: exercise.id, setID: set.id, weight: $0) }))
                    .keyboardType(.decimalPad).accessibilityLabel("第 \(number) 组负重（kg）")
                    .focused($focusedField, equals: set.id.uuidString + ".weight").frame(minHeight: 44)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("次数").font(.footnote).foregroundStyle(.secondary)
            TextField("次数", text: Binding(get: { model.fields.repsText[set.id] ?? "" }, set: { model.setInput(exerciseID: exercise.id, setID: set.id, reps: $0) }))
                .keyboardType(.numberPad).accessibilityLabel("第 \(number) 组次数")
                .focused($focusedField, equals: set.id.uuidString + ".reps").frame(minHeight: 44)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func exerciseActions(_ exercise: Exercise, index: Int) -> some View {
        Button("前移") { model.moveExercise(exercise.id, earlier: true) }.disabled(index == 0)
        Button("后移") { model.moveExercise(exercise.id, earlier: false) }.disabled(index == model.workout.exercises.count - 1)
        Button("删除动作", role: .destructive) { model.removeExercise(exercise.id) }
    }
    private func close(flushOnly: Bool = false) async {
        do { try await model.flush(); if !flushOnly { await onClosed(); dismiss() } } catch { model.error = error.userMessage }
    }
    private func openDetails() async {
        do {
            try await model.flush()
            showingDetails = true
        } catch { model.error = error.userMessage }
    }
}

private struct BatchSetsView: View {
    let exercise: Exercise
    let model: WorkoutEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var count = ""
    @State private var reps = ""
    @State private var weight = ""
    @FocusState private var focusedField: String?
    var body: some View {
        NavigationStack {
            Form {
                Text(exercise.name + " · " + exercise.weightConvention)
                TextField("已完成组数（1—30）", text: $count).keyboardType(.numberPad).focused($focusedField, equals: "count")
                TextField("每组次数（1—999）", text: $reps).keyboardType(.numberPad).focused($focusedField, equals: "reps")
                if exercise.kind == .weighted { TextField("负重（kg）", text: $weight).keyboardType(.decimalPad).focused($focusedField, equals: "weight") }
                Text("使用本次训练时间；生成后可逐组调整，结束训练前仍是草稿。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = model.error { Text(error) }
                Button("确认生成完成组") { if model.batch(exerciseID: exercise.id, count: count, reps: reps, weight: weight) { dismiss() } }.frame(minHeight: 44)
            }.bojiForm().navigationTitle("批量补记").navigationBarTitleDisplayMode(.inline).recordingKeyboard { focusedField = nil }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.font(PixelTheme.font()).tint(.primary)
    }
}
