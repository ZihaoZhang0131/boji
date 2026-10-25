import SwiftUI
import UniformTypeIdentifiers
import BojiDomain

struct BackupView:View {
    let workspace:WorkspaceModel
    @State private var picker=false
    @State private var disconnect=false
    private var backup:BackupState { workspace.snapshot?.backup ?? BackupState() }
    var body:some View {
        Form {
            Section("备份目录") {
                Text(backup.directoryLabel ?? "尚未连接目录").accessibilityIdentifier("backup.directory")
                Text("可选 iCloud Drive 或其他可写目录，完整备份存入 Boji／资料集子目录。")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
                Button(backup.directoryBookmark == nil ? "选择备份目录" : "更换备份目录") { picker=true }.frame(minHeight:44)
                if backup.directoryBookmark != nil {
                    Button("立即备份") { Task { await workspace.backupNow() } }.frame(minHeight:44).accessibilityIdentifier("backup.now")
                    Button("断开目录",role:.destructive) { disconnect=true }.frame(minHeight:44)
                }
            }
            Section("备份状态") {
                Text(status).accessibilityIdentifier("backup.status")
                if let date=backup.lastWrittenAt { LabeledContent("上次目录写入",value:date.formatted(date:.abbreviated,time:.shortened)) }
                if let message=workspace.backupError ?? backup.lastError { Text(message).accessibilityIdentifier("backup.error") }
                Text("写入目录后由系统上传；Mac 是否已下载需在 Mac 确认。")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
            Section {
                DisclosureGroup("在 Mac 上读取") {
                    Text("打开所选目录中的 Boji／资料集子目录，按 latest.json 定位完整 .boji 包。下载全部文件并核验 manifest 后，再交给 Agent。")
                    Text("Mac 修改不会自动写回手机。外部改动或不完整指针会停止后续发布；可选择新空目录，或从完整包走导入预览。")
                }
                DisclosureGroup("备份方式与技术状态") {
                    if let revision=backup.lastPublishedRevision { Text("完整备份修订：\(revision)；本机当前修订：\(workspace.snapshot?.dataset.revision ?? 0)") }
                    Text("只有所有必要文件的系统状态均为已上传时才显示确认；这不代表 Mac 已下载。")
                    Text("薄记只管理 Boji／资料集子目录，保留每份完整备份。连续编辑会合并备份；App 被暂停时不能保证后台完成，重新打开后继续，也可点立即备份。")
                }
                Text("手机删除不会撤回旧备份，请自行管理目录空间。")
                    .font(.footnote).foregroundStyle(PixelTheme.subtle)
            }
        }
        .bojiForm()
        .navigationTitle("目录备份")
        .disabled(workspace.backupBusy || workspace.isDemo)
        .sheet(isPresented:$picker) { BackupDirectoryPicker { url in Task { await workspace.connectBackup(url) } } }
        .confirmationDialog("断开备份目录？",isPresented:$disconnect,titleVisibility:.visible) {
            Button("确认断开",role:.destructive) { Task { await workspace.disconnectBackup() } }
        } message: { Text("后续记录只保存在本机；已发布的目录备份会保留。") }
    }
    private var status:String {
        switch backup.status {
        case .disconnected:"未连接 · 本机记录正常保存"
        case .dirty:"待写入目录 · 本机已保存"
        case .writing:"正在生成并写入完整快照"
        case .written:"已写入目录 · 未取得云端上传确认"
        case .pendingUpload:"已写入目录 · 等待系统上传全部文件"
        case .uploadConfirmed:"系统已确认全部文件上传 · Mac 下载状态未知"
        case .failed:"目录备份失败 · 本机记录仍已保存"
        case .unknown:"目录已写入 · 系统上传状态未知"
        }
    }
}
private struct BackupDirectoryPicker:UIViewControllerRepresentable {
    let selected:(URL)->Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator()->Coordinator { Coordinator(parent:self) }
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false)
        picker.delegate=context.coordinator;picker.allowsMultipleSelection=false;return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
    @MainActor final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let parent:BackupDirectoryPicker
        init(parent:BackupDirectoryPicker) { self.parent=parent }
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) { if let url=urls.first { parent.selected(url) };parent.dismiss() }
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) { parent.dismiss() }
    }
}
