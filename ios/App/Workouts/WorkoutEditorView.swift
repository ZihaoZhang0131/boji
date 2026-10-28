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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDetails = false
    @State private var showingExercises = false
    @State private var customName = ""
    @State private var customKind: ExerciseKind = .weighted
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.workout.exercises) { exercise in exerciseSection(exercise) }
                        if showingExercises || model.workout.exercises.isEmpty {
                            exercisePicker
                        } else {
                            Button { showingExercises = true } label: { Text("添加动作").frame(maxWidth: .infinity) }
                                .buttonStyle(PixelButtonStyle()).accessibilityIdentifier("workout.addExercise")
                        }
                        if let error = model.error { Text(error).font(.footnote).accessibilityIdentifier("workout.error") }
                        if model.isEditing && workspace != nil && clock != nil && onReplaceEditor != nil {
                            Button("详情") { focusedField = nil; showingDetails = true }
                                .font(.footnote).foregroundStyle(PixelTheme.subtle).frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("workout.details")
                        }
                    }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                }
                .background(PixelTheme.canvas).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { actionBar(proxy: proxy) }
                .disabled(model.busy).recordingKeyboard { focusedField = nil }
            }
            .navigationTitle(model.isEditing ? "编辑训练" : "记训练").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingDetails) {
                if let workspace, let clock {
                    WorkoutDetailView(id: model.workout.id, workspace: workspace, clock: clock, embedded: true,
                                      onOpenEditor: onReplaceEditor, onRecordRemoved: onRecordRemoved)
                }
            }
        }
        .font(.body).tint(.primary).interactiveDismissDisabled(model.busy)
    }

    private func actionBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                focusedField = nil
                Task { await onClosed(); dismiss() }
            } label: {
                Text("放弃").frame(maxWidth: .infinity, minHeight: 50)
                    .background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
            }.accessibilityIdentifier("workout.close")
            Button {
                if let issue = model.firstInvalidInput {
                    model.error = issue.message
                    focusedField = issue.field
                    if let field = issue.field { proxy.scrollTo(field, anchor: .center) }
                } else {
                    focusedField = nil
                    Task { if await model.save() { await onSaved(model.workout.time.localDay); dismiss() } }
                }
            } label: {
                Text("保存").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(PixelTheme.canvas).contentShape(Rectangle())
            }.accessibilityIdentifier("workout.save")
        }.buttonStyle(.plain).disabled(model.busy)
            .padding(.horizontal, 20).padding(.vertical, 12).background(PixelTheme.canvas)
    }

    private func weightHeading(_ exercise: Exercise) -> String {
        let text = exercise.weightConvention
        if text.contains("单只") { return "单只 kg" }
        if text.contains("含杆") { return "含杆 kg" }
        if text.isEmpty || text.contains("总重量") { return "kg" }
        return text.localizedCaseInsensitiveContains("kg") ? text : text + " kg"
    }

    private func exerciseSection(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { model.removeExercise(exercise.id) } label: {
                    Text("删除").font(.footnote).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(PixelTheme.subtle).accessibilityLabel("删除" + exercise.name)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    Text("组").frame(width: 24)
                    if exercise.kind == .weighted { Text(weightHeading(exercise)).frame(maxWidth: .infinity) }
                    Text("次").frame(maxWidth: .infinity)
                }.font(.caption).foregroundStyle(PixelTheme.subtle).accessibilityHidden(true)
            }
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("第 \(index + 1) 组").font(.subheadline)
                        setFields(set, exercise: exercise, number: index + 1)
                    }
                } else {
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.subheadline).foregroundStyle(PixelTheme.subtle).frame(width: 24)
                        setFields(set, exercise: exercise, number: index + 1)
                    }
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { model.removeLastSet(exercise.id) } label: { stepSymbol(increasing: false) }
                    .disabled(exercise.sets.count <= 1).accessibilityLabel(exercise.name + "减少一组")
                Text("\(exercise.sets.count) 组").font(.subheadline).monospacedDigit()
                Button { model.addSet(exercise.id, copying: true) } label: { stepSymbol(increasing: true) }
                    .accessibilityLabel(exercise.name + "增加一组")
                Spacer(minLength: 0)
            }.buttonStyle(.plain)
        }.padding(16).background(colorScheme == .dark ? Color(white: 0.20) : PixelTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stepSymbol(increasing: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1).frame(width: 18, height: 2)
            if increasing { RoundedRectangle(cornerRadius: 1).frame(width: 2, height: 18) }
        }.frame(width: 44, height: 44).contentShape(Rectangle())
    }

    @ViewBuilder private func setFields(_ set: WorkoutSet, exercise: Exercise, number: Int) -> some View {
        if exercise.kind == .weighted {
            if dynamicTypeSize.isAccessibilitySize { Text(weightHeading(exercise)).font(.caption).foregroundStyle(PixelTheme.subtle) }
            TextField("—", text: Binding(get: { model.fields.weightText[set.id] ?? "" }, set: { model.setInput(exerciseID: exercise.id, setID: set.id, weight: $0) }))
                .keyboardType(.decimalPad).accessibilityLabel("第 \(number) 组负重（kg）").accessibilityHint(exercise.name + "，" + exercise.weightConvention)
                .focused($focusedField, equals: set.id.uuidString + ".weight").id(set.id.uuidString + ".weight")
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48)
                .background(PixelTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
        }
        if dynamicTypeSize.isAccessibilitySize { Text("次数").font(.caption).foregroundStyle(PixelTheme.subtle) }
        TextField("—", text: Binding(get: { model.fields.repsText[set.id] ?? "" }, set: { model.setInput(exerciseID: exercise.id, setID: set.id, reps: $0) }))
            .keyboardType(.numberPad).accessibilityLabel("第 \(number) 组次数").accessibilityHint(exercise.name)
            .focused($focusedField, equals: set.id.uuidString + ".reps").id(set.id.uuidString + ".reps")
            .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48)
            .background(PixelTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
    }

    private var exercisePicker: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(["杠铃卧推", "杠铃深蹲", "硬拉", "哑铃划船", "引体向上", "俯卧撑"], id: \.self) { name in
                    Button { addExercise(name, kind: ["引体向上", "俯卧撑"].contains(name) ? .bodyweight : .weighted) } label: {
                        Text(name).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(PixelButtonStyle())
                }
            }
            TextField("其他动作", text: $customName).recordingField().focused($focusedField, equals: "custom")
                .accessibilityLabel("其他动作").submitLabel(.done)
            if !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Picker("动作类型", selection: $customKind) { Text("负重").tag(ExerciseKind.weighted); Text("自重").tag(ExerciseKind.bodyweight) }
                    .pickerStyle(.menu).frame(minHeight: 44)
                Button("添加") { addExercise(customName.trimmingCharacters(in: .whitespacesAndNewlines), kind: customKind) }
                    .frame(maxWidth: .infinity).buttonStyle(PixelButtonStyle())
            }
            if !model.workout.exercises.isEmpty {
                Button("收起") { showingExercises = false; focusedField = nil }
                    .font(.subheadline).foregroundStyle(PixelTheme.subtle).frame(minWidth: 44, minHeight: 44)
            }
        }.accessibilityIdentifier("workout.inlinePicker")
    }
    private func addExercise(_ name: String, kind: ExerciseKind) {
        model.addExercise(name: name, kind: kind); showingExercises = false; customName = ""; focusedField = nil
    }
}
