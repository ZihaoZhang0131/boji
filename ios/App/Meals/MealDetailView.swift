import SwiftUI
import BojiDomain

struct MealSelection: Identifiable { let id: UUID }

struct MealDetailView: View {
    let id: UUID
    let workspace: WorkspaceModel
    let clock: any AppClock
    @Environment(\.dismiss) private var dismiss
    @State private var editor: MealEditorModel?
    @State private var showingCalories = false
    @State private var confirmingTrash = false
    @State private var images: [UUID: UIImage] = [:]
    @State private var error: String?

    private var meal: Meal? { workspace.snapshot?.activeMeals.first { $0.id == id } }
    private var history: [EstimateRevision] { (workspace.snapshot?.estimates.filter { $0.recordID == id } ?? []).sorted { $0.createdAt > $1.createdAt } }
    private var current: EstimateRevision? {
        history.first { $0.id == meal?.currentEstimateID && $0.inputRevision == meal?.inputRevision && $0.source != .demo }
    }

    var body: some View {
        NavigationStack {
            List {
                if let meal {
                    Section {
                        Text(meal.time.localDay.description + " " + meal.time.displayTime)
                        Text(meal.time.timeZoneIdentifier).font(.footnote).foregroundStyle(.secondary)
                        if let slot = meal.slot { Text(slot) }
                        if !meal.tags.isEmpty { Text(meal.tags.joined(separator: " · ")) }
                        if !meal.note.isEmpty { Text(meal.note).accessibilityIdentifier("meal.detail.note") }
                        ForEach(meal.photoIDs, id: \.self) { photoID in
                            if let image = images[photoID] {
                                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("饮食照片")
                            } else { Text("照片暂时无法读取，原记录仍保留。") }
                        }
                    }
                    Section("当前热量") {
                        if let current { EstimateContents(revision: current) }
                        else {
                            Text("待估算").accessibilityIdentifier("meal.calories.unknown")
                            Text(history.isEmpty ? "尚未取得有效估算。可以先人工填写热量。" : "照片或备注已变化，请重新估算或人工确认。原值保留在历史中。")
                        }
                        Button("人工填写或修正") { showingCalories = true }.frame(minHeight: 44)
                            .accessibilityIdentifier("meal.manual")
                        AIRecordControls(workspace: workspace, meal: meal)
                    }
                    if !history.isEmpty {
                        Section("估算与修正历史") {
                            ForEach(history) { revision in
                                DisclosureGroup {
                                    EstimateContents(revision: revision)
                                    Text("输入版本 \(revision.inputRevision)")
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(revision.totalKcal.description + " kcal · " + revision.sourceTitle)
                                        Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                                        if revision.id == current?.id { Text("当前有效") }
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        Button("编辑饮食") { Task { await edit(meal) } }.frame(minHeight: 44).accessibilityIdentifier("meal.edit")
                        Button("移到回收站", role: .destructive) { confirmingTrash = true }.frame(minHeight: 44)
                    }
                } else { Text("这条记录已移走，请返回记录页。") }
                if let error { Text(error) }
            }
            .navigationTitle("饮食详情")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("将这条饮食移到回收站？", isPresented: $confirmingTrash, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    Task { await workspace.trash(kind: .meal, id: id); if workspace.errorMessage == nil { dismiss() } else { error = workspace.errorMessage } }
                }
            } message: { Text("30 天内可从「我的—回收站」恢复。") }
        }
        .task(id: meal?.photoIDs) { await loadImages() }
        .font(PixelTheme.font()).tint(.primary)
        .sheet(item: $editor) { model in
            MealEditorView(model: model, workspace: workspace, onSaved: { _ in
                try? await workspace.refresh(); await workspace.requestEstimate(recordID: model.meal.id, automatic: true)
            }, onClosed: { try? await workspace.refresh() })
        }
        .sheet(isPresented: $showingCalories) {
            if let meal { ManualEstimateView(meal: meal, initial: current, workspace: workspace, clock: clock) }
        }
    }
    private func edit(_ meal: Meal) async {
        do { editor = try await MealEditorModel.open(repository: workspace.activeRepository(), clock: clock, selectedDay: meal.time.localDay, editing: meal) }
        catch { self.error = error.userMessage }
    }
    private func loadImages() async {
        guard let meal else { return }
        do {
            let repository = try await workspace.activeRepository()
            for id in meal.photoIDs {
                guard let photo = workspace.snapshot?.photos.first(where: { $0.id == id }) else { continue }
                // Full normalized local copy, not the picker resource or a remote URL.
                images[id] = UIImage(data: try await repository.readPhoto(photo))
            }
        } catch { self.error = "部分照片暂时无法读取，请保留本机资料后重试。" }
    }
}

struct EstimateContents: View {
    let revision: EstimateRevision
    var body: some View {
        Text(revision.totalKcal.description + " kcal").accessibilityIdentifier("meal.calories.total")
        Text(revision.sourceTitle)
        ForEach(revision.items) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                Text((item.grams.map { $0.description + " g" } ?? "克数未知") + " · " + item.kcal.description + " kcal")
                ForEach(Array(item.assumptions.enumerated()), id: \.offset) { _, value in Text("假设：" + value).font(.footnote) }
            }
        }
        if let range = revision.range { Text("估算范围 \(range.low.description)—\(range.high.description) kcal") }
        ForEach(Array(revision.questions.enumerated()), id: \.offset) { _, value in Text(value) }
        if let provider = revision.provider { Text(provider + " · " + (revision.model ?? "模型未知")).font(.footnote) }
    }
}

extension EstimateRevision {
    var sourceTitle: String {
        switch source { case .manual: "人工确认"; case .model: "AI 估算"; case .demo: "演示数据" }
    }
}
