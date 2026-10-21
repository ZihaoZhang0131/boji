import SwiftUI
import BojiDomain

struct DaySummaryView: View {
    let review: DayReview
    let onConfirmation: (Bool) async -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirming = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 12) {
                metricLayout {
                    Text(review.pendingMeals > 0 ? "已知摄入" : "摄入").foregroundStyle(.secondary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 16) }
                    Text(intake)
                        .font(PixelTheme.font(22, relativeTo: .title2))
                        .monospacedDigit()
                        .accessibilityLabel(review.mealCount == 0 ? "尚无饮食记录" : (review.pendingMeals == review.mealCount ? "摄入待估算" : "已记录摄入 \(review.knownIntakeKcal.description) kcal"))
                        .accessibilityIdentifier("day.intake")
                }
                metric("总消耗", value: kcal(review.totalBurnKcal))
                metric("差值", value: review.differenceKcal.map { $0.description + " kcal" } ?? "—")
            }
            DisclosureGroup(review.complete ? "已记全 · 统计详情" : (review.confirmed ? "待补全估算 · 统计详情" : "未确认记全 · 统计详情")) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("日常基线", value: kcal(review.baselineKcal))
                    LabeledContent("训练净消耗", value: review.pendingWorkouts == review.workoutCount && review.workoutCount > 0 ? "待估算" : "\(review.knownWorkoutKcal) kcal")
                    Text("\(review.workoutCount) 次训练 · \(review.completedSetCount) 组")
                    if review.workoutCount == 0 { Text("无训练记录，消耗仅采用日常基线。") }
                    if let target = review.targetKcal { LabeledContent("摄入目标", value: "\(target.description) kcal") }
                    if let goal = review.goal { LabeledContent("阶段", value: goal.goal.title) }
                    ForEach(review.missingReasons, id: \.self) { Text($0) }
                }
                .font(PixelTheme.font(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
            Button(review.confirmed ? "撤销已记全" : "确认这天已记全") {
                if review.confirmed { Task { await submit(false) } } else { confirming = true }
            }
            .buttonStyle(PixelButtonStyle())
            .disabled(busy || review.mealCount == 0)
            .accessibilityIdentifier("day.confirm")
        }
        .confirmationDialog("这天的饮食和训练已全部记录？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认已记全") { Task { await submit(true) } }
        } message: { Text("待估算项目不会按零值计入。之后新增、修改、删除或恢复记录，都需要重新确认。") }
    }

    private var intake: String {
        if review.mealCount == 0 { return "—" }
        if review.pendingMeals == review.mealCount { return "待估算" }
        return review.knownIntakeKcal.description + " kcal"
    }

    private func metric(_ label: String, value: String) -> some View {
        metricLayout {
            Text(label).foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 16) }
            Text(value).font(PixelTheme.font(22, relativeTo: .title2)).monospacedDigit()
        }
    }

    private var metricLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
    }

    private func kcal(_ value: Int?) -> String { value.map { "\($0) kcal" } ?? "—" }
    private func submit(_ value: Bool) async { busy = true; defer { busy = false }; await onConfirmation(value) }
}
