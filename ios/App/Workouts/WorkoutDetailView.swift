import SwiftUI
import BojiDomain

struct WorkoutSelection: Identifiable { let id: UUID }

struct WorkoutDetailView: View {
    let id: UUID
    let workspace: WorkspaceModel
    let clock: any AppClock
    @Environment(\.dismiss) private var dismiss
    @State private var editor: WorkoutEditorModel?
    @State private var deleting = false
    @State private var conflict = false
    @State private var copying = false
    @State private var error: String?
    private var workout: Workout? { workspace.snapshot?.activeWorkouts.first { $0.id == id } }
    var body: some View {
        NavigationStack {
            List {
                if let workout {
                    Section {
                        Text(workout.name.isEmpty ? "训练" : workout.name)
                        Text(workout.time.localDay.description + " " + workout.time.displayTime)
                        Text("\(workout.exercises.flatMap(\.sets).count) 个完成组")
                    }
                    ForEach(workout.exercises) { exercise in
                        Section(exercise.name) {
                            Text(exercise.kind == .bodyweight ? "自重" : exercise.weightConvention)
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                Text("第 \(index + 1) 组 · " + (set.weightKG.map { $0.description + " kg × " } ?? "") + "\(set.reps ?? 0) 次 · 完成")
                            }
                        }
                    }
                    Section("消耗与历史") {
                        ForEach(workout.energyHistory.reversed()) { energy in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(energy.id == workout.currentEnergyID ? "当前估算" : "历史估算")
                                Text(energy.kcal.map { "\($0) kcal" } ?? "待估算")
                                Text(energy.inputDescription)
                                Text(energy.intensity.title + " · " + energy.algorithmVersion).font(.footnote)
                            }
                        }
                    }
                    Section {
                        Button("编辑训练") { copying = false; Task { await open() } }.frame(minHeight: 44)
                        Button("复制为本次训练") { copying = true; Task { await open() } }.frame(minHeight: 44)
                        Button("移到回收站", role: .destructive) { deleting = true }.frame(minHeight: 44)
                    }
                }
                if let error { Text(error) }
            }.navigationTitle("训练详情")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog("将这次训练移到回收站？", isPresented: $deleting, titleVisibility: .visible) {
                    Button("确认删除", role: .destructive) { Task { await workspace.trash(kind: .workout, id: id); if workspace.errorMessage == nil { dismiss() } else { error = workspace.errorMessage } } }
                }
                .confirmationDialog("已有进行中的训练草稿", isPresented: $conflict, titleVisibility: .visible) {
                    Button("继续已有草稿") { Task { await resumeExisting() } }
                    Button("放弃旧草稿并继续", role: .destructive) { Task { await discardExisting() } }
                } message: { Text("每次只保留一个活动训练，已有草稿不会被覆盖。") }
        }
        .sheet(item: $editor) { model in
            WorkoutEditorView(model: model, onSaved: { _ in try? await workspace.refresh() }, onClosed: { try? await workspace.refresh() })
        }
        .font(PixelTheme.font()).tint(.primary)
    }
    private func open() async {
        guard let workout else { return }
        do {
            let repository = try await workspace.activeRepository()
            editor = try await WorkoutEditorModel.open(repository: repository, clock: clock, day: workout.time.localDay, editing: copying ? nil : workout, copying: copying ? workout : nil)
        } catch WorkoutEditorError.activeDraft { conflict = true }
        catch { self.error = error.userMessage }
    }
    private func resumeExisting() async {
        do { editor = try await WorkoutEditorModel.open(repository: workspace.activeRepository(), clock: clock, day: LocalDay(clock.now, timeZone: clock.timeZone)) }
        catch { self.error = error.userMessage }
    }
    private func discardExisting() async {
        do {
            let repository = try await workspace.activeRepository()
            if let draft = try await repository.snapshot().drafts.first(where: { $0.content.kind == .workout }) {
                try await repository.discardDraft(id: draft.id, at: clock.now, operationID: UUID())
            }
            try await workspace.refresh(); await open()
        } catch { self.error = error.userMessage }
    }
}

private extension WorkoutEnergy {
    var inputDescription: String {
        let weight = weightKG.map { $0.description + " kg" } ?? "体重未知"
        let duration = minutes.map { $0.description + " 分钟" } ?? "时长未知"
        return weight + " · " + duration
    }
}
