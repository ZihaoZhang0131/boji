import SwiftUI
import UniformTypeIdentifiers
import BojiDomain
import BojiPortability

struct ImportView: View {
    let workspace: WorkspaceModel
    @State private var showPicker = false
    @State private var busy = false
    @State private var confirming = false
    @State private var confirmingRestore = false
    @State private var prototypeData: Data?
    @State private var prototypePreview: PrototypePreview?
    @State private var originalTimeZone = TimeZone.current.identifier
    @State private var fallbackProfileDate = Date()
    @State private var confirmedPrototype = false
    @State private var confirmedHistory = false
    @State private var previewGeneration = 0
    @State private var package: ValidatedPackage?
    @State private var preview: ImportPlan?
    @State private var policy: ImportConflictPolicy = .keepLocal
    @State private var restored: Set<String> = []
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Text("选择完整 .boji 资料包或原型导出的版本 1 JSON，校验和预览之后再写入。导入不会恢复外部令牌、发送授权或识别任务。")
                Button(busy ? "正在下载、校验或导入" : "选择资料包") { showPicker = true }.frame(minHeight:44).disabled(busy || workspace.isDemo).accessibilityIdentifier("import.select")
                if let error { Text(error).accessibilityIdentifier("import.error") }
                if let message { Text(message).accessibilityIdentifier("import.result") }
            }
            if let prototypePreview {
                Section("原型迁移确认") {
                    Text("待迁移 \(prototypePreview.meals) 餐、\(prototypePreview.workouts) 次训练；默认排除 \(prototypePreview.excludedDemo) 项示例资料。")
                    ForEach(prototypePreview.notices,id:\.self) { Text($0) }
                    TextField("原始时区，例如 Asia/Shanghai",text:$originalTimeZone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("确认原始时区，单位为 kg、cm、分钟、kcal；未标记的记录是我的真实内容",isOn:$confirmedPrototype)
                    if prototypePreview.needsHistoryConfirmation {
                        DatePicker("缺少生效日的身体资料采用",selection:$fallbackProfileDate,displayedComponents:.date)
                        Toggle("确认缺少提交时间的历史按生效日及原文件顺序识别",isOn:$confirmedHistory)
                    }
                    Button("转换并生成导入预览") { Task { await convertPrototype() } }
                        .frame(minHeight:44).disabled(busy || !confirmedPrototype || (prototypePreview.needsHistoryConfirmation && !confirmedHistory))
                }
            }
            if let preview {
                Section("导入预览") {
                    Text("新增 \(preview.added) · 替换 \(preview.replaced) · 相同 \(preview.duplicates) · 跳过 \(preview.skipped)").accessibilityIdentifier("import.preview")
                    Text("排除演示内容 \(preview.excludedDemo) 项。")
                    ForEach(preview.notices,id:\.self) { Text($0) }
                    if !preview.conflicts.isEmpty {
                        Picker("内容冲突",selection:$policy) {
                            Text("保留本机（默认）").tag(ImportConflictPolicy.keepLocal)
                            Text("采用导入版本").tag(ImportConflictPolicy.useImported)
                        }
                        .disabled(busy)
                        ForEach(preview.conflicts) { conflict in
                            if conflict.restoration {
                                Toggle(conflict.title,isOn:Binding(get:{restored.contains(conflict.id)},set:{ value in
                                    if value { restored.insert(conflict.id) } else { restored.remove(conflict.id) }
                                    Task { await updatePreview() }
                                }))
                            } else { Text(conflict.title) }
                        }
                    }
                    Text("同日身体资料、重叠阶段或活动草稿会显示冲突。旧包的已删除记录必须单独选择恢复；采用导入版本不会自动撤销永久删除。")
                    Button(preview.hasChanges ? "确认导入预览中的变更" : "没有需要导入的变更") { confirming = true }
                        .frame(minHeight:44).disabled(busy || !preview.hasChanges).accessibilityIdentifier("import.apply")
                }
            }
            Section("恢复") {
                Text("激活新库前保留完整旧库。若需要回退，请核对导入后的新增记录，再恢复导入前版本。")
                Button("恢复上次导入或升级前资料") { confirmingRestore = true }
                    .frame(minHeight:44).disabled(busy || workspace.isDemo)
            }
        }
        .navigationTitle("导入与恢复")
        .onChange(of:policy) { _,_ in Task { await updatePreview() } }
        .sheet(isPresented:$showPicker) { PackageOpenPicker { url in Task { await stage(url) } } }
        .confirmationDialog("恢复上次完整资料版本？",isPresented:$confirmingRestore,titleVisibility:.visible) {
            Button("确认恢复",role:.destructive) { message = nil;Task { await workspace.restorePreviousStore();error = workspace.errorMessage;if error == nil { message = "已恢复上次完整资料版本。";preview = nil } } }
        } message: { Text("当前版本中的新记录不会合并进旧版本。请先导出当前资料；原当前版本仍作为回退版本保留。") }
        .confirmationDialog("按当前预览导入？",isPresented:$confirming,titleVisibility:.visible) {
            Button("确认导入") { Task { await apply() } }
        } message: { Text("会新建完整影子库再激活；内容冲突按当前选择处理，旧库保留可回退。") }
    }
    private func stage(_ url:URL) async {
        busy = true;error = nil;message = nil;preview = nil;package = nil;prototypeData = nil;prototypePreview = nil;confirmedPrototype = false;confirmedHistory = false;restored = [];policy = .keepLocal;previewGeneration += 1
        defer { busy = false }
        do {
            let parent = try FileManager.default.url(for:.cachesDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("BojiImports")
            if url.pathExtension.lowercased() == "json" {
                let importer = PrototypeImporter()
                let data = try await importer.readSelection(url)
                prototypePreview = try await importer.inspect(data);prototypeData = data
            } else {
                package = try await PackageStager().stage(url,in:parent)
                await updatePreview()
            }
        } catch { self.error = error.localizedDescription }
    }
    private func convertPrototype() async {
        guard let prototypeData else { return };busy = true;error = nil;defer { busy = false }
        do {
            var options = PrototypeOptions(timeZoneIdentifier:originalTimeZone,undatedProfileDay:LocalDay(fallbackProfileDate,timeZone:.current))
            options.confirmedUnitsAndProvenance = confirmedPrototype;options.confirmedAmbiguousHistory = confirmedHistory
            let parent = try FileManager.default.url(for:.cachesDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("BojiImports")
            let conversion = try await PrototypeImporter().convert(prototypeData,options:options,to:parent)
            package = conversion.package;prototypePreview = conversion.preview
            await updatePreview()
        } catch { preview = nil;self.error = error.localizedDescription }
    }
    private func updatePreview() async {
        guard let package else { return };previewGeneration += 1;let generation = previewGeneration
        do {
            var options = ImportOptions();options.conflicts = policy;options.restoreDeleted = restored
            let state = try await workspace.activeRepository().snapshot()
            guard generation == previewGeneration else { return }
            preview = try ImportPlanner.plan(package:package,local:state,options:options);error = nil
        } catch { preview = nil;self.error = error.localizedDescription }
    }
    private func apply() async {
        guard let preview,let package else { return };busy = true;error = nil;defer { busy = false }
        do { try await workspace.importPackage(preview,package:package);message = "导入已保存。没有创建识别任务，原资料版本可回退。";await updatePreview() }
        catch { self.error = error is DomainError ? "本机资料可能已变化，请重新选择并预览；原有资料仍可读取。" : error.localizedDescription }
    }
}
private struct PackageOpenPicker:UIViewControllerRepresentable {
    let selected:(URL)->Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator()->Coordinator { Coordinator(parent:self) }
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes:[UTType(importedAs:"com.boji.package"),.folder,.json],asCopy:false)
        picker.delegate = context.coordinator;picker.allowsMultipleSelection = false;return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
    @MainActor final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let parent:PackageOpenPicker
        init(parent:PackageOpenPicker) { self.parent = parent }
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) { if let url=urls.first { parent.selected(url) };parent.dismiss() }
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) { parent.dismiss() }
    }
}
