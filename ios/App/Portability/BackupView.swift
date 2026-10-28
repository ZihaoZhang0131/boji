import SwiftUI
import UniformTypeIdentifiers
import BojiDomain

enum BackupPresentation {
    // The compact status also appears on the data-management navigation row.
    static func automaticStatus(_ backup: BackupState) -> String {
        guard backup.directoryBookmark != nil else { return "未设置" }
        switch backup.automaticEnabled {
        case true: return "已开启"
        case false: return "已停止"
        case nil: return "待启用"
        }
    }
    static func heading(_ backup: BackupState) -> String {
        guard backup.directoryBookmark != nil else { return "尚未开启备份" }
        switch backup.automaticEnabled {
        case true: return "自动备份已开启"
        case false: return "自动备份已停止"
        case nil: return "自动备份待启用"
        }
    }
    static func lastWritten(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
    static func uploadStatus(_ backup: BackupState) -> String? {
        guard backup.lastWrittenAt != nil else { return nil }
        let status = backup.lastUploadStatus ?? backup.status
        switch status {
        case .uploadConfirmed: return "系统已确认上传"
        case .pendingUpload: return "等待系统上传"
        case .written: return "已写入目录"
        default: return "上传状态未知"
        }
    }
    static func activity(_ backup: BackupState) -> String? {
        guard backup.directoryBookmark != nil else { return nil }
        if backup.status == .failed { return "备份未完成，请重试或更换目录。" }
        if backup.automaticEnabled == true && backup.dirty { return "有新内容待备份" }
        return nil
    }
}

struct BackupView: View {
    let workspace: WorkspaceModel
    @State private var picker = false
    @State private var more = false
    @State private var chooseAfterMenu = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var backup: BackupState { workspace.snapshot?.backup ?? BackupState() }
    private var connected: Bool { backup.directoryBookmark != nil }
    private var busy: Bool { workspace.backupUserActionInProgress }
    private var needsEnable: Bool { connected && backup.automaticEnabled == nil }
    private var primaryTitle: String {
        if busy { return "备份中…" }
        if !connected { return "选择目录并开启" }
        return needsEnable ? "启用自动备份" : "立即备份"
    }
    private var primaryID: String { !connected ? "backup.choose" : needsEnable ? "backup.enable" : "backup.now" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(BackupPresentation.heading(backup))
                        .font(.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("backup.status")
                    if connected {
                        VStack(alignment: .leading, spacing: 6) {
                            if let date = backup.lastWrittenAt {
                                Text("最近备份  " + BackupPresentation.lastWritten(date, timeZone: workspace.clock.timeZone))
                                    .monospacedDigit().accessibilityIdentifier("backup.lastWritten")
                                if let status = BackupPresentation.uploadStatus(backup) {
                                    Text(status).accessibilityIdentifier("backup.upload")
                                }
                            } else {
                                Text("尚无备份").accessibilityIdentifier("backup.lastWritten")
                            }
                        }.font(.footnote).foregroundStyle(PixelTheme.subtle)
                    } else {
                        Text("备份记录、照片、身体资料及历史")
                            .font(.footnote).foregroundStyle(PixelTheme.subtle)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if !connected { picker = true }
                        else if needsEnable { Task { await workspace.setAutomaticBackup(true) } }
                        else { Task { await workspace.backupNow() } }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(PixelTheme.canvas).accessibilityHidden(true) }
                            Text(primaryTitle).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(MineActionStyle(prominent: true)).accessibilityIdentifier(primaryID)
                    .disabled(busy || workspace.isDemo)
                    if let message = workspace.backupError ?? backup.lastError {
                        Text(message).font(.footnote).accessibilityIdentifier("backup.error")
                    } else if !busy, let message = BackupPresentation.activity(backup) {
                        Text(message).font(.footnote).foregroundStyle(PixelTheme.subtle)
                            .accessibilityIdentifier("backup.activity")
                    }
                }
                if connected {
                    Divider()
                    directory
                    MineDisclosure("备份说明") {
                        Text("App 在前台时自动备份，离开后未完成的工作会在下次打开时继续。")
                        Text("停止自动备份后，已有文件和目录授权仍保留，也可立即备份。已经开始的备份和系统上传可能继续。")
                        Text("历史备份不会自动删除，请自行管理空间。恢复资料请前往“数据管理 → 导入与恢复”预览并确认。")
                    }.font(.subheadline).accessibilityIdentifier("backup.help")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .background(PixelTheme.canvas).font(.body).tint(.primary)
        .navigationTitle("iCloud 备份").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if connected {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        moreButton
                    }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        moreButton
                    }
                }
            }
        }
        .sheet(isPresented: $picker) { BackupDirectoryPicker { url in Task { await workspace.connectBackup(url) } } }
    }

    private var moreButton: some View {
        BackupMoreButton { more = true }.frame(width: 68, height: 44)
            .popover(isPresented: $more, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                VStack(spacing: 0) {
                    if needsEnable {
                        menuAction("立即备份", disabled: busy || workspace.isDemo) { Task { await workspace.backupNow() } }
                    } else if backup.automaticEnabled == false {
                        menuAction("启用自动备份", disabled: busy || workspace.isDemo) { Task { await workspace.setAutomaticBackup(true) } }
                    }
                    if backup.automaticEnabled != true { Divider() }
                    menuAction("更换目录", disabled: busy || workspace.isDemo) { chooseAfterMenu = true }
                    if backup.automaticEnabled == true {
                        Divider()
                        menuAction("停止自动备份", disabled: workspace.isDemo) { Task { await workspace.setAutomaticBackup(false) } }
                    }
                }
                .padding(.vertical, 4).frame(width: typeSize.isAccessibilitySize ? 280 : 240)
                .font(.body).foregroundStyle(.primary).tint(.primary)
                .presentationCompactAdaptation(.popover)
                .onDisappear {
                    // Present Files after the menu has closed, avoiding competing presentations.
                    if chooseAfterMenu { chooseAfterMenu = false; picker = true }
                }
            }
    }

    private func menuAction(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            more = false
            action()
        } label: {
            Text(title).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled)
    }

    private var directory: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text("备份位置").foregroundStyle(PixelTheme.subtle).fixedSize()
            Text(backup.directoryLabel ?? "所选目录").fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("backup.directory")
        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
// The system popover supplies presentation/dismissal; explicit rows preserve 44pt targets.
private struct BackupMoreButton: UIViewRepresentable {
    let action: () -> Void
    final class Coordinator { var action: (() -> Void)? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("更多", for: .normal)
        button.tintColor = .label
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .systemFont(ofSize: 17), maximumPointSize: 23)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "backup.more"
        button.accessibilityLabel = "更多备份操作"
        let coordinator = context.coordinator
        button.addAction(UIAction { _ in coordinator.action?() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) { context.coordinator.action = action }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 68, height: 44)
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
