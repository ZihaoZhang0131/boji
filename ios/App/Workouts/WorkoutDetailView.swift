import SwiftUI
import BojiDomain

struct WorkoutSelection: Identifiable { let id: UUID }

struct WorkoutDetailView: View {
    let id: UUID
    let workspace: WorkspaceModel
    let clock: any AppClock
    var embedded = false
    var onOpenEditor: ((WorkoutEditorModel) -> Void)? = nil
    var onRecordRemoved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var editor: WorkoutEditorModel?
    @State private var deleting = false
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
                        Text("运动净消耗 · 估算").font(.footnote).foregroundStyle(PixelTheme.subtle)
                        if embedded { Text("已保存的训练记录").font(.footnote).foregroundStyle(PixelTheme.subtle) }
                    }
                    ForEach(workout.exercises) { exercise in
                        Section(exercise.name) {
                            if exercise.kind == .weighted && !exercise.weightConvention.isEmpty {
                                Text(exercise.weightConvention).font(.footnote).foregroundStyle(PixelTheme.subtle)
                            }
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(index + 1)").font(.footnote).foregroundStyle(PixelTheme.subtle)
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
                                        Text(energy.intensity.title + " · " + energy.algorithmVersion).font(.footnote).foregroundStyle(PixelTheme.subtle)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(energy.kcal.map { "\($0) kcal" } ?? "待估算")
                                            Text(energy.id == workout.currentEnergyID ? "当前估算" : "历史估算").font(.footnote).foregroundStyle(PixelTheme.subtle)
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

    }
    private func setSummary(_ set: WorkoutSet, exercise: Exercise) -> String {
        let weight = exercise.kind == .bodyweight ? "自重" : set.weightKG.map { $0.description + " kg" } ?? "— kg"
        let reps = set.reps.map { String($0) } ?? "—"
        return weight + " × " + reps + " 次"
    }
    private func open() async {
        do {
            presentEditor(try await makeEditor())
        } catch { self.error = error.userMessage }
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
    private func removeRecord() async {
        await workspace.trash(kind: .workout, id: id)
        guard workspace.errorMessage == nil else { error = workspace.errorMessage; return }
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
