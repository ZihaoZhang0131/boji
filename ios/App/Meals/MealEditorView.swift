import SwiftUI
import PhotosUI
import AVFoundation
import BojiDomain

struct MealEditorView: View {
    @Bindable var model: MealEditorModel
    let workspace: WorkspaceModel
    let onSaved: (LocalDay) async -> Void
    let onClosed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selections: [PhotosPickerItem] = []
    @State private var tagsText: String
    @State private var showingCamera = false
    @State private var confirmingDiscard = false
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @State private var showingManual = false
    @FocusState private var focusedField: String?

    init(model: MealEditorModel, workspace: WorkspaceModel, onSaved: @escaping (LocalDay) async -> Void, onClosed: @escaping () async -> Void) {
        self.model = model; self.workspace = workspace; self.onSaved = onSaved; self.onClosed = onClosed
        _tagsText = State(initialValue: model.meal.tags.joined(separator: "，"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片 · \(model.meal.photoIDs.count)/9") {
                    ForEach(Array(model.meal.photoIDs.enumerated()), id: \.element) { index, id in
                        VStack(alignment: .leading, spacing: 8) {
                            if let image = model.images[id] {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("饮食照片 \(index + 1)")
                            } else { Text("照片无法读取，请移除或重新选择。") }
                            ViewThatFits(in: .horizontal) {
                                HStack { photoActions(id, index: index) }
                                VStack(alignment: .leading) { photoActions(id, index: index) }
                            }.buttonStyle(PixelButtonStyle())
                        }
                    }
                    PhotosPicker(selection: $selections, maxSelectionCount: max(1, 9 - model.meal.photoIDs.count), selectionBehavior: .ordered, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle").frame(minHeight: 44)
                    }.disabled(model.meal.photoIDs.count >= 9 || importing)
                    Button { Task { await openCamera() } } label: { Label("拍照", systemImage: "camera").frame(minHeight: 44) }
                        .disabled(model.meal.photoIDs.count >= 9 || importing)
                    if importing {
                        HStack { ProgressView(); Text("正在读取照片") }
                        Button("取消剩余导入") { importTask?.cancel() }.frame(minHeight: 44)
                    }
                    if let error = model.error { Text(error).accessibilityIdentifier("meal.photoImportError") }
                }
                Section {
                    TextField("吃了什么、份量或补充说明", text: Binding(get: { model.meal.note }, set: { model.setNote($0) }), axis: .vertical)
                        .lineLimit(3...8).accessibilityIdentifier("meal.note")
                        .focused($focusedField, equals: "note")
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { focusedField = "note" })
                } footer: {
                    Text("照片或文字至少填写一项。")
                }
                Section {
                    DisclosureGroup("更多信息") {
                        DatePicker("进食日期和时间", selection: Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 }))
                        LabeledContent("时区", value: model.meal.time.timeZoneIdentifier)
                            .font(.footnote).foregroundStyle(.secondary)
                        Picker("餐次", selection: Binding(get: { model.meal.slot ?? "" }, set: { model.setSlot($0) })) {
                            Text("未分类").tag("")
                            ForEach(["早餐", "午餐", "晚餐", "加餐", "下午茶"], id: \.self) { Text($0).tag($0) }
                        }
                        TextField("标签，以逗号分隔（可选）", text: $tagsText).accessibilityLabel("饮食标签")
                            .focused($focusedField, equals: "tags")
                            .onChange(of: tagsText) { _, value in model.setTags(value) }
                    }
                }
                Section("热量") {
                    if let revision = workspace.snapshot?.estimates.first(where: { $0.id == model.meal.currentEstimateID && $0.inputRevision == model.meal.inputRevision }) { EstimateContents(revision: revision) }
                    Button("人工填写热量") {
                        Task { do { try MealRules.validate(model.meal); try await model.flush(); try await workspace.refresh(); showingManual = true } catch { model.error = error.userMessage } }
                    }.frame(minHeight: 44)
                    AIRecordControls(workspace: workspace, meal: model.meal, draftID: model.id, prepare: { try await model.flush() })
                }
                Section {
                    Text(model.statusText).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("meal.draftStatus")
                    if case .failed = model.saveStatus { Button("重试保存草稿") { Task { await close(flushOnly: true) } } }
                    if let error = model.error { Text(error).accessibilityIdentifier("meal.error") }
                    Button(model.busy ? "正在保存" : "保存饮食") {
                        Task {
                            if await model.save() { await onSaved(model.meal.time.localDay); dismiss() }
                        }
                    }.frame(minHeight: 44).accessibilityIdentifier("meal.save").disabled(importing || model.pendingImports > 0)
                    Button(model.isEditing ? "放弃修改" : "放弃草稿", role: .destructive) { confirmingDiscard = true }
                        .frame(minHeight: 44)
                }
            }
            .bojiForm()
            .disabled(model.busy)
            .scrollDismissesKeyboard(.interactively)
            .recordingKeyboard { focusedField = nil }
            .navigationTitle(model.isEditing ? "编辑饮食" : "记一餐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("收起") { Task { await close() } }.disabled(model.busy) } }
            .confirmationDialog("确定放弃？", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("确认放弃", role: .destructive) { Task { if await model.discard() { await onClosed(); dismiss() } } }
            } message: { Text(model.isEditing ? "正式记录仍保留原来的内容。" : "未保存为正式饮食的草稿将被移除。") }
        }
        .interactiveDismissDisabled()
        .font(PixelTheme.font()).tint(.primary)
        .task { await model.observeStatus() }
        .onChange(of: workspace.snapshot?.dataset.revision) { _, _ in Task { await model.refreshEstimate() } }
        .sheet(isPresented: $showingManual, onDismiss: { Task { await model.refreshEstimate() } }) {
            ManualEstimateView(meal: model.meal, initial: workspace.snapshot?.estimates.first { $0.id == model.meal.currentEstimateID }, workspace: workspace, clock: workspace.clock, draftID: model.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { do { try await model.flush() } catch { model.error = error.userMessage } } }
        }
        .onChange(of: selections) { _, values in
            guard !values.isEmpty else { return }
            importTask?.cancel(); importing = true
            importTask = Task {
                defer { importing = false; selections = [] }
                for item in values {
                    guard !Task.isCancelled else { break }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw DomainError.invalidValue("照片无法读取") }
                        guard !Task.isCancelled else { break }
                        await model.addPhoto(data)
                    } catch { model.error = "部分照片未能读取，已经添加的内容已保留。" }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(onCapture: { data in Task { await model.addPhoto(data) } }, onError: { model.error = $0 })
        }
    }
    @ViewBuilder private func photoActions(_ id: UUID, index: Int) -> some View {
        Button("前移") { model.movePhoto(id, earlier: true) }.disabled(index == 0)
        Button("后移") { model.movePhoto(id, earlier: false) }.disabled(index == model.meal.photoIDs.count - 1)
        Button("移除", role: .destructive) { model.removePhoto(id) }
    }
    private func close(flushOnly: Bool = false) async {
        importTask?.cancel()
        do { try await model.flush(); if !flushOnly { await onClosed(); dismiss() } }
        catch { model.error = error.userMessage }
    }
    private func openCamera() async {
        let access = await CameraAccess.authorize(using: SystemCameraDevice())
        if access == .authorized { showingCamera = true }
        else { model.error = access.message }
    }
}

private struct CameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(parent: CameraView) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, image.size.width * image.size.height <= 50_000_000 {
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
                if let data = upright.jpegData(compressionQuality: 0.95) { parent.onCapture(data) }
                else { parent.onError("拍摄图片未能读取，原有内容已保留。") }
            } else { parent.onError("拍摄图片无法读取或尺寸过大，原有内容已保留。") }
            parent.dismiss()
        }
    }
}
