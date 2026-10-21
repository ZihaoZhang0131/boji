import SwiftUI
import BojiDomain

struct WorkoutSelection: Identifiable { let id: UUID }

struct WorkoutDetailView: View {
    let id: UUID
    let workspace: WorkspaceModel
    let clock: any AppClock
    var embedded = false
    var editingContext: WorkoutEditorModel? = nil
    var onOpenEditor: ((WorkoutEditorModel) -> Void)? = nil
    var onRecordRemoved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var editor: WorkoutEditorModel?
    @State private var deleting = false
    @State private var conflict = false
    @State private var copying = false
    @State private var error: String?
    private var workout: Workout? { workspace.snapshot?.activeWorkouts.first { $0.id == id } }
    var body: some View {
        Group {
            if embedded { detailContent }
            else { NavigationStack { detailContent } }
        }
        .sheet(item: $editor) { model in
            WorkoutEditorView(model: model, onSaved: { _ in try? await workspace.refresh() }, onClosed: { try? await workspace.refresh() })
        }
        .font(PixelTheme.font()).tint(.primary)
    }

    private var detailContent: some View {
            List {
                if let workout {
                    Section {
                        if !workout.name.isEmpty { Text(workout.name).font(PixelTheme.font(20, relativeTo: .title3)) }
                        let current = workout.energyHistory.first { $0.id == workout.currentEnergyID }
                        Text(current?.kcal.map { "\($0) kcal" } ?? "待估算")
                            .font(PixelTheme.font(24, relativeTo: .title2)).monospacedDigit()
                            .accessibilityLabel("运动净消耗，" + (current?.kcal.map { "\($0) kcal" } ?? "待估算"))
                        Text("运动净消耗 · 估算").font(.footnote).foregroundStyle(.secondary)
                        if embedded { Text("已保存的训练记录").font(.footnote).foregroundStyle(.secondary) }
                    }
                    ForEach(workout.exercises) { exercise in
                        Section(exercise.name) {
                            if exercise.kind == .weighted && !exercise.weightConvention.isEmpty {
                                Text(exercise.weightConvention).font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(index + 1)").font(.footnote).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(setSummary(set, exercise: exercise)).monospacedDigit()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("第 \(index + 1) 组，" + setSummary(set, exercise: exercise) + "，已完成")
                            }
                        }
                    }
                    Section {
                        DisclosureGroup("训练信息") {
                            LabeledContent("训练时间", value: workout.time.localDay.description + " " + workout.time.displayTime)
                            LabeledContent("时区", value: workout.time.timeZoneIdentifier)
                            LabeledContent("完成组数", value: "\(workout.exercises.flatMap(\.sets).count)")
                        }
                        if !workout.energyHistory.isEmpty {
                            DisclosureGroup("消耗估算历史") {
                                ForEach(workout.energyHistory.reversed()) { energy in
                                    DisclosureGroup {
                                        Text(energy.inputDescription)
                                        Text(energy.intensity.title + " · " + energy.algorithmVersion).font(.footnote).foregroundStyle(.secondary)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(energy.kcal.map { "\($0) kcal" } ?? "待估算")
                                            Text(energy.id == workout.currentEnergyID ? "当前估算" : "历史估算").font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        if !embedded {
                            Button("编辑训练") { copying = false; Task { await open() } }.frame(minHeight: 44)
                        }
                        Button("复制为本次训练") { copying = true; Task { await open() } }.frame(minHeight: 44)
                        Button("移到回收站", role: .destructive) { deleting = true }.frame(minHeight: 44)
                    }
                }
                if let error { Text(error) }
            }.bojiForm().navigationTitle("训练").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !embedded {
                        ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    }
                }
                .confirmationDialog("将这次训练移到回收站？", isPresented: $deleting, titleVisibility: .visible) {
                    Button("确认删除", role: .destructive) { Task { await removeRecord() } }
                } message: { Text(embedded ? "本次尚未保存的修改将放弃。正式记录可在回收站恢复。" : "正式记录可在回收站恢复。") }
                .confirmationDialog(embedded ? "当前训练有编辑草稿" : "已有进行中的训练草稿", isPresented: $conflict, titleVisibility: .visible) {
                    Button(embedded ? "返回当前修改" : "继续已有草稿") { Task { await resumeExisting() } }
                    Button(embedded ? "放弃当前修改并复制" : "放弃旧草稿并继续", role: .destructive) { Task { await discardExisting() } }
                    Button("取消", role: .cancel) { if embedded { dismiss() } }
                } message: { Text(embedded ? "复制需要结束当前编辑。放弃后仅丢弃草稿中的修改，已保存的训练保持原值。" : "每次只保留一个活动训练，已有草稿不会被覆盖。") }
    }
    private func setSummary(_ set: WorkoutSet, exercise: Exercise) -> String {
        let weight = exercise.kind == .bodyweight ? "自重" : set.weightKG.map { $0.description + " kg" } ?? "— kg"
        let reps = set.reps.map { String($0) } ?? "—"
        return weight + " × " + reps + " 次"
    }
    private func open() async {
        do {
            presentEditor(try await makeEditor())
        } catch WorkoutEditorError.activeDraft { conflict = true }
        catch { self.error = error.userMessage }
    }
    private func makeEditor() async throws -> WorkoutEditorModel {
        guard let workout else { throw DomainError.invalidValue("这条训练已移走，请返回记录页。") }
        let repository = try await workspace.activeRepository()
        return try await WorkoutEditorModel.open(repository: repository, clock: clock, day: workout.time.localDay, editing: copying ? nil : workout, copying: copying ? workout : nil)
    }
    private func presentEditor(_ next: WorkoutEditorModel) {
        if let onOpenEditor { onOpenEditor(next) }
        else { editor = next }
    }
    private func resumeExisting() async {
        if embedded { dismiss(); return }
        do { editor = try await WorkoutEditorModel.open(repository: workspace.activeRepository(), clock: clock, day: LocalDay(clock.now, timeZone: clock.timeZone)) }
        catch { self.error = error.userMessage }
    }
    private func discardExisting() async {
        var discardedEditingContext = false
        do {
            let repository = try await workspace.activeRepository()
            if let editingContext {
                guard await editingContext.discard() else { error = editingContext.error; return }
                discardedEditingContext = true
            } else if let draft = try await repository.snapshot().drafts.first(where: { $0.content.kind == .workout }) {
                try await repository.discardDraft(id: draft.id, at: clock.now, operationID: UUID())
            }
            try await workspace.refresh()
            presentEditor(try await makeEditor())
        } catch {
            if discardedEditingContext {
                workspace.errorMessage = "当前修改已放弃，但未能打开复制训练。已保存的训练仍保留，请重新打开后再试。"
                if let onRecordRemoved { onRecordRemoved() }
                else { dismiss() }
            } else { self.error = error.userMessage }
        }
    }

    private func removeRecord() async {
        await workspace.trash(kind: .workout, id: id)
        guard workspace.errorMessage == nil else { error = workspace.errorMessage; return }
        if let editingContext { _ = await editingContext.discard() }
        if let onRecordRemoved { onRecordRemoved() }
        else { dismiss() }
    }
}

private extension WorkoutEnergy {
    var inputDescription: String {
        let weight = weightKG.map { $0.description + " kg" } ?? "体重未知"
        let duration = minutes.map { $0.description + " 分钟" } ?? "时长未知"
        return weight + " · " + duration
    }
}
