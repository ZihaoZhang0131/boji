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
                        ForEach(meal.photoIDs, id: \.self) { photoID in
                            if let image = images[photoID] {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("饮食照片")
                            } else { Text("照片暂时无法读取，原记录仍保留。") }
                        }
                        if !meal.note.isEmpty { Text(meal.note).accessibilityIdentifier("meal.detail.note") }
                    }
                    Section("热量") {
                        if let current { EstimateContents(revision: current) }
                        else {
                            Text("待估算").accessibilityIdentifier("meal.calories.unknown")
                            if !history.isEmpty {
                                Text("记录已变化，需重新估算或人工确认。旧值保留在历史中。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Button("人工填写或修正") { showingCalories = true }.frame(minHeight: 44)
                            .accessibilityIdentifier("meal.manual")
                        AIRecordControls(workspace: workspace, meal: meal)
                    }
                    Section {
                        DisclosureGroup("记录信息") {
                            LabeledContent("进食时间", value: meal.time.localDay.description + " " + meal.time.displayTime)
                            LabeledContent("时区", value: meal.time.timeZoneIdentifier)
                            if let slot = meal.slot { LabeledContent("餐次", value: slot) }
                            if !meal.tags.isEmpty { LabeledContent("标签", value: meal.tags.joined(separator: " · ")) }
                        }
                    }
                    if !history.isEmpty {
                        Section {
                            DisclosureGroup("估算与修正历史") {
                                ForEach(history) { revision in
                                    DisclosureGroup {
                                        EstimateContents(revision: revision)
                                        Text("输入版本 \(revision.inputRevision)").font(.footnote).foregroundStyle(.secondary)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(revision.totalKcal.description + " kcal · " + revision.sourceTitle)
                                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                                            if revision.id == current?.id { Text("当前有效").font(.footnote) }
                                        }
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
            .bojiForm()
            .navigationTitle("饮食")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(revision.totalKcal.description + " kcal")
                .font(PixelTheme.font(24, relativeTo: .title2)).monospacedDigit()
                .accessibilityIdentifier("meal.calories.total")
            Text(revision.sourceTitle).font(.footnote).foregroundStyle(.secondary)
        }
        if !revision.items.isEmpty || revision.range != nil || !revision.questions.isEmpty || revision.provider != nil {
            DisclosureGroup("估算明细") {
                ForEach(revision.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                        Text((item.grams.map { $0.description + " g" } ?? "克数未知") + " · " + item.kcal.description + " kcal")
                            .foregroundStyle(.secondary)
                        ForEach(Array(item.assumptions.enumerated()), id: \.offset) { _, value in Text("假设：" + value).font(.footnote) }
                    }.padding(.vertical, 4)
                }
                if let range = revision.range { Text("估算范围 \(range.low.description)—\(range.high.description) kcal") }
                ForEach(Array(revision.questions.enumerated()), id: \.offset) { _, value in Text(value) }
                if let provider = revision.provider { Text(provider + " · " + (revision.model ?? "模型未知")).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

extension EstimateRevision {
    var sourceTitle: String {
        switch source { case .manual: "人工确认"; case .model: "AI 估算"; case .demo: "演示数据" }
    }
}
