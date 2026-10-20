import SwiftUI
import BojiDomain

struct TrashView: View {
    let workspace: WorkspaceModel
    @State private var deletion: TrashItem?
    private var items: [TrashItem] {
        let meals = workspace.snapshot?.meals.compactMap { meal in meal.deletedAt.map { TrashItem(id: meal.id, kind: .meal, name: meal.note.isEmpty ? "照片饮食" : meal.note, deleted: $0) } } ?? []
        let workouts = workspace.snapshot?.workouts.compactMap { workout in workout.deletedAt.map { TrashItem(id: workout.id, kind: .workout, name: workout.name, deleted: $0) } } ?? []
        return (meals + workouts).sorted { $0.deleted > $1.deleted }
    }
    var body: some View {
        List {
            Section {
                Text("删除后保留 30 天。永久删除无法在本机撤销，已导出的备份不会自动撤回。")
            }
            if items.isEmpty { Text("回收站为空").accessibilityIdentifier("trash.empty") }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.name)
                    Text("删除于 " + item.deleted.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { actions(item) }
                        VStack(alignment: .leading) { actions(item) }
                    }
                }.padding(.vertical, 8)
            }
        }
        .navigationTitle("回收站")
        .alert("永久删除这条记录？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("永久删除", role: .destructive) {
                if let item = deletion { Task { await workspace.purge(kind: item.kind, id: item.id) } }
                deletion = nil
            }
            Button("取消", role: .cancel) { deletion = nil }
        } message: { Text("本机记录、历史和无其他引用的照片将被移除。") }
    }
    @ViewBuilder private func actions(_ item: TrashItem) -> some View {
        Button("恢复") { Task { await workspace.restore(kind: item.kind, id: item.id) } }.buttonStyle(PixelButtonStyle())
        Button("永久删除", role: .destructive) { deletion = item }.buttonStyle(PixelButtonStyle())
    }
}

private struct TrashItem: Identifiable {
    let id: UUID
    let kind: RecordKind
    let name: String
    let deleted: Date
}
