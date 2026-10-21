import SwiftUI
import BojiDomain

struct AIRecordControls: View {
    let workspace: WorkspaceModel
    let meal: Meal
    var draftID: UUID?
    var prepare: (() async throws -> Void)?
    @State private var retryConfirmation = false
    @State private var busy = false
    @State private var error: String?
    private var job: EstimateJob? {
        workspace.snapshot?.jobs.filter { $0.recordID == meal.id && $0.inputRevision == meal.inputRevision && $0.lifecycleEpoch == meal.lifecycleEpoch }.max { $0.queuedAt < $1.queuedAt }
    }
    private var authorized: Bool { workspace.snapshot?.aiSettings.acceptedPolicy != nil && !workspace.isDemo }
    var body: some View {
        if workspace.isDemo { Text("演示空间不发送识别请求。") }
        else if !authorized { Text("AI 未配置或未授权。前往「我的—AI 估算」设置，仍可人工填写。") }
        else {
            if let job {
                Text(title(job)).accessibilityIdentifier("ai.job.status")
                if let code = job.errorCode { Text(code.estimationErrorMessage) }
                if job.remoteCancellationPending == true { Text("正在尝试取消远程任务；已发送的资料无法保证追回。") }
            }
            if let job, !job.status.isTerminal {
                Button("取消这次识别") { Task { await workspace.cancelEstimate(job.id) } }.frame(minHeight: 44)
            } else {
                Button(job == nil && meal.currentEstimateID == nil ? "识别这餐" : "重新识别（可能再次计费）") {
                    if job != nil || meal.currentEstimateID != nil { retryConfirmation = true }
                    else { Task { await request() } }
                }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("ai.request")
            }
        }
        if let error { Text(error) }
        if let message = workspace.aiError { Text(message) }
        Text("AI 结果为估算，未知克数不代表零。")
            .font(.footnote).foregroundStyle(.secondary)
            .confirmationDialog("重新请求模型？", isPresented: $retryConfirmation, titleVisibility: .visible) {
                Button("确认重新请求") { Task { await request() } }
            } message: { Text("会创建新尝试，可能再次产生费用。旧估算和人工修正保留在历史中。") }
    }
    private func title(_ job: EstimateJob) -> String {
        switch job.status {
        case .pendingNetwork: workspace.network.isOnline ? "等待发送或重试" : "待联网"
        case .queued: "识别排队中"
        case .running: "识别中"
        case .succeeded: "识别完成"
        case .failed: "识别未完成"
        case .cancelled: "识别已取消"
        }
    }
    private func request() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try await prepare?()
            await workspace.requestEstimate(recordID: meal.id, draftID: draftID, retryOf: job?.remoteJobID)
            error = nil
        } catch { self.error = error.estimationMessage }
    }
}
