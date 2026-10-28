import SwiftUI
import BojiDomain
import BojiEstimation

struct AISettingsView: View {
    let workspace: WorkspaceModel
    @State private var token = ""
    @State private var connecting = false
    @State private var confirming = false
    @State private var revoking = false
    @FocusState private var focused: Bool
    private var settings: AISettings { workspace.snapshot?.aiSettings ?? AISettings() }
    private var authorized: Bool { settings.cachedPolicy.map { settings.acceptedPolicy == $0.version } ?? false }
    var body: some View {
        MinePage {
            MineSection("连接与密钥") {
                Text("千问识别 · 个人直连").font(.footnote).foregroundStyle(PixelTheme.subtle)
                if settings.cachedPolicy == nil { LabeledContent("模型", value: QwenDirectClient.model).font(.subheadline) }
                SecureField("千问 API Key（留空沿用已存密钥）", text: $token,
                            prompt: Text(settings.serviceURL == nil ? "输入千问 API Key" : "留空沿用已存密钥").foregroundStyle(PixelTheme.subtle))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    .padding(12).frame(minHeight: 44).background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("ai.token")
                Text("密钥保存在本机 Keychain，不进入导出或备份。记录与人工热量可离线使用。")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
                Button(connecting ? "正在保存" : "保存密钥并查看授权") {
                    focused = false; connecting = true
                    Task { if await workspace.connectAI(urlText: QwenDirectClient.endpoint.absoluteString, token: token) { token = "" }; connecting = false }
                }.buttonStyle(MineActionStyle(prominent: settings.cachedPolicy == nil || !token.isEmpty)).disabled(connecting)
                if let error = workspace.aiError { Text(error).font(.footnote).accessibilityIdentifier("ai.error") }
            }
            if let policy = settings.cachedPolicy {
                MineSection(authorized ? "授权" : "发送前请确认") {
                    if authorized {
                        Text(policy.available ? "已授权当前政策" : "已授权 · 服务暂不可用").accessibilityIdentifier("ai.authorized")
                        MineDisclosure("授权详情") { policyDetails(policy).padding(.top, 8) }.frame(minHeight: 44)
                    } else {
                        policyDetails(policy)
                        Text(policy.available ? "尚未授权，照片和备注仅保存在本机。" : "服务暂不可用，仍可记录和人工填写热量。")
                            .font(.footnote).foregroundStyle(PixelTheme.subtle)
                        Button("授权千问处理饮食照片和备注") { confirming = true }
                            .buttonStyle(MineActionStyle(prominent: token.isEmpty)).disabled(!policy.available)
                    }
                }
            } else {
                Text("未配置千问，照片和备注保存在本机，热量可人工填写。").font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            MineSection("自动估算") {
                Toggle("保存带照片餐食后自动估算", isOn: Binding(get: { settings.automatic }, set: { value in Task { await workspace.setAutomaticAI(value) } })).frame(minHeight: 44)
                Text("开关不能代替授权。关闭后停止新自动任务，仍可在有效授权下手动识别。")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
                MineDisclosure("离线识别说明") {
                    Text("离线任务会等到联网且 App 获得执行机会。").font(.footnote).foregroundStyle(PixelTheme.subtle).padding(.top, 8)
                }.frame(minHeight: 44)
            }
            if settings.serviceURL != nil {
                MineSection {
                    Button("撤回资料发送授权", role: .destructive) { revoking = true }.buttonStyle(MineActionStyle())
                    Button("断开并移除本机密钥", role: .destructive) { Task { await workspace.disconnectAI(); token = "" } }.buttonStyle(MineActionStyle())
                }
            }
        }
        .navigationTitle("AI 估算").recordingKeyboard { focused = false }.disabled(workspace.isDemo)
        .confirmationDialog("授权发送到千问？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认授权") { Task { await workspace.acceptAI() } }
        } message: { Text("仅发送发起识别的饮食照片和备注。供应商、保留方式和费用如上；模型或政策变化需要重新确认。") }
        .confirmationDialog("撤回授权？", isPresented: $revoking, titleVisibility: .visible) {
            Button("确认撤回", role: .destructive) { Task { await workspace.revokeAI() } }
        } message: { Text("停止全部新发送，取消未完成任务。已经发送给千问的资料无法保证追回。") }
    }
    private func policyDetails(_ policy: AIServicePolicy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("供应商", value: policy.provider ?? "未配置")
            LabeledContent("模型", value: policy.model ?? "未配置")
            Text("发送范围：" + policy.sentData.joined(separator: "、"))
            if settings.serviceURL != QwenDirectClient.endpoint {
                Text("服务原始资料最多保留 \(policy.rawRetentionHours) 小时；无原文元数据最多 \(policy.metadataRetentionDays) 天。")
            }
            Text("供应商保留政策：" + policy.providerRetention)
            if settings.serviceURL == QwenDirectClient.endpoint {
                Link("阅读千问AI平台隐私政策", destination: URL(string: "https://terms.alicdn.com/legal-agreement/terms/common_product_agreement/20260423150805928/20260423150805928.html")!).frame(minHeight: 44)
            }
            Text(policy.feePayer)
            Text("每 UTC 日最多 \(policy.dailyAttempts) 次尝试，不是金额预算。结果未知时不自动重试；主动重试可能再次计费。")
                .font(.footnote)
            Text("政策版本：" + policy.version).font(.footnote).foregroundStyle(PixelTheme.subtle)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Error {
    var estimationMessage: String {
        if self is URLError { return "暂时无法连接千问。原始记录仍在；若请求已发出，再试可能产生费用。" }
        if let error = self as? ServiceFailure { return error.code.estimationErrorMessage }
        if let error = self as? DomainError, error == .notConfigured { return "请先在「我的—AI 估算」配置千问并确认发送授权。" }
        return userMessage
    }
}
extension String {
    var estimationErrorMessage: String {
        switch self {
        case "unauthorized": "这台 iPhone 尚未保存千问 API Key，请在「我的—AI 估算」填写。"
        case "invalid_token": "密钥格式未通过本机检查，请确认完整复制，且没有空格或换行。"
        case "credentials_unavailable": "暂时无法从 iPhone Keychain 读取密钥，请解锁手机后重试。"
        case "provider_unauthorized": "千问服务拒绝了请求（401/403）。请核对密钥所属平台、API Host 和模型权限；原始餐食仍保留。"
        case "https_required": "请使用不带账号、查询参数或片段的 HTTPS 服务地址。"
        case "not_configured": "尚未配置千问，可先人工填写热量。"
        case "policy_changed": "服务政策已变化，请重新读取并确认授权。"
        case "quota_exceeded": "今天的模型尝试额度已用完，原始记录仍保留。"
        case "rate_limited": "千问暂时限流；本机不会自动重发这次请求。"
        case "network_unavailable": "待联网，将在 App 恢复执行时继续。"
        case "provider_timeout", "upstream_outcome_unknown": "供应商结果超时或未知。再次尝试可能重复产生费用，可改用人工填写。"
        case "invalid_model_output", "invalid_response": "识别结果未通过校验，未计入热量，可重试或人工填写。"
        case "cannot_recognize": "无法辨认食物，请补充照片或备注，也可人工填写。"
        case "expired": "这次请求已过期，请明确重新发起；原始记录仍在。"
        case "input_changed": "输入已变化，旧结果不会覆盖当前记录。"
        case "consent_revoked": "已撤回授权，停止新发送。"
        case "automatic_disabled": "已关闭自动估算，未发送任务已取消。"
        case "cancelled", "draft_discarded", "record_deleted": "任务已取消。"
        default: "识别未完成，原始记录仍在。可检查千问配置或人工填写热量。"
        }
    }
}
