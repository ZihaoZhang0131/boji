import SwiftUI
import BojiDomain

struct DaySummaryView: View {
    let review: DayReview
    let onConfirmation: (Bool) async -> Void
    @State private var confirming = false
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(review.mealCount == 0 ? "尚无饮食记录" : "已记录摄入 \(review.knownIntakeKcal.description) kcal")
                .accessibilityIdentifier("day.intake")
            Text("日常基线：" + kcal(review.baselineKcal))
            Text("已知训练净消耗：\(review.knownWorkoutKcal) kcal · \(review.workoutCount) 次训练，\(review.completedSetCount) 组")
            if review.workoutCount == 0 { Text("无训练记录，消耗仅采用日常基线。") }
            Text("估算总消耗：" + kcal(review.totalBurnKcal))
            Text("摄入减消耗：" + (review.differenceKcal.map { $0.description + " kcal" } ?? "未知"))
            if let target = review.targetKcal { Text("自定摄入目标：\(target.description) kcal") }
            if let goal = review.goal { Text("阶段：" + goal.goal.title) }
            Text(review.complete ? "完整统计日" : "尚未满足完整统计条件")
            ForEach(review.missingReasons, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
            Button(review.confirmed ? "撤销已记全" : "确认这天已记全") {
                if review.confirmed { Task { await submit(false) } } else { confirming = true }
            }.buttonStyle(PixelButtonStyle()).disabled(busy || review.mealCount == 0)
                .accessibilityIdentifier("day.confirm")
        }
        .confirmationDialog("这天的饮食和训练已全部记录？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认已记全") { Task { await submit(true) } }
        } message: { Text("待估算项目不会按零值计入。之后新增、修改、删除或恢复记录，都需要重新确认。") }
    }
    private func kcal(_ value: Int?) -> String { value.map { "\($0) kcal" } ?? "未知" }
    private func submit(_ value: Bool) async { busy = true; defer { busy = false }; await onConfirmation(value) }
}
