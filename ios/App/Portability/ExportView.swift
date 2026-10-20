import SwiftUI
import UniformTypeIdentifiers
import BojiPortability

struct ExportView: View {
    let workspace: WorkspaceModel
    @State private var busy = false
    @State private var confirming = false
    @State private var package: PublishedPackage?
    @State private var showPicker = false
    @State private var message: String?
    @State private var error: String?
    var body: some View {
        Form {
            Section("完整资料包") {
                Text("导出正式记录、草稿、回收站、身体资料、照片及估算历史。包内含私人资料，请只交给你信任的接收方。")
                Text("Mac 可直接读取 JSON 和照片；文件大小及 SHA-256 清单用于核验完整性。")
                Button(busy ? "正在生成完整资料包" : "生成资料包") { confirming = true }
                    .frame(minHeight: 44).disabled(busy || workspace.isDemo).accessibilityIdentifier("export.prepare")
                if let package {
                    Text("资料包已完整生成 · 修订 \(package.manifest.revision)").accessibilityIdentifier("export.ready")
                    Text("\(package.manifest.counts["meals"] ?? 0) 餐 · \(package.manifest.counts["workouts"] ?? 0) 次训练 · \(package.manifest.counts["photos"] ?? 0) 张照片")
                    Button("存储到文件") { showPicker = true }.frame(minHeight: 44).accessibilityIdentifier("export.save")
                    Text("生成和存储到目录是两步；系统文件选择器取消不会删除本机记录。")
                }
                if let message { Text(message) }
                if let error { Text(error).accessibilityIdentifier("export.error") }
            }
            Section("交给 Agent") {
                Text("先把完整资料包下载到 Mac，核验清单，再自行交给 Agent。复制提示词不会发送资料。")
                Button("复制复盘提示词") { UIPasteboard.general.string = PackageReadingGuide.agentPrompt; message = "提示词已复制，请自行选择接收方。" }.frame(minHeight: 44)
                DisclosureGroup("查看读取说明") { Text(PackageReadingGuide.readme).textSelection(.enabled) }
            }
        }
        .navigationTitle("导出与 Agent")
        .confirmationDialog("生成含照片和身体资料的完整包？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认生成") { Task { await prepare() } }
        } message: { Text("只在本机生成，不会自动上传到 AI 或发送给任何人。") }
        .sheet(isPresented: $showPicker) {
            if let package { PackageSavePicker(url: package.url) { saved in message = saved ? "系统已完成存储到所选位置；云端上传状态请以文件提供者为准。" : "已取消存储，本机资料包仍可再次导出。" } }
        }
    }
    private func prepare() async {
        guard !busy else { return }; busy = true; error = nil; message = nil; defer { busy = false }
        do {
            let parent = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("BojiExports")
            package = try await PackageExporter().export(repository: workspace.activeRepository(), to: parent, at: workspace.clock.now)
        } catch { self.error = error.localizedDescription }
    }
}
private struct PackageSavePicker: UIViewControllerRepresentable {
    let url: URL
    let completed: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: PackageSavePicker
        init(parent: PackageSavePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { parent.completed(!urls.isEmpty); parent.dismiss() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.completed(false); parent.dismiss() }
    }
}
