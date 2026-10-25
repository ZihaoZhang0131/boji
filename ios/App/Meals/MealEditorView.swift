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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selections: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @State private var showingManual = false
    @State private var confirmingTrash = false
    @FocusState private var focused: Bool

    private var estimate: EstimateRevision? {
        workspace.snapshot?.estimates.first { $0.id == model.meal.currentEstimateID && $0.inputRevision == model.meal.inputRevision }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content
                    mealSlots
                    metadata
                    if let error = model.error { Text(error).font(.footnote).accessibilityIdentifier("meal.error") }
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }
            .background(PixelTheme.canvas).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if model.isEditing { editActions }
                else {
                    RecordingSaveBar(disabled: model.busy || importing || model.pendingImports > 0, identifier: "meal.save", action: save)
                }
            }
            .disabled(model.busy).recordingKeyboard { focused = false }
            .navigationTitle(model.isEditing ? "编辑饮食" : "记饮食").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("放弃", action: close).disabled(model.busy).accessibilityIdentifier("meal.close")
                    }
                }
            }
            .confirmationDialog("将这条饮食移到回收站？", isPresented: $confirmingTrash, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    focused = false
                    Task { if await model.trash() { await onClosed(); dismiss() } }
                }
            } message: { Text("未保存的修改会放弃，原记录可在 30 天内从「我的—数据管理—回收站」恢复。") }
        }
        .font(.body).tint(.primary).interactiveDismissDisabled()
        .onChange(of: workspace.snapshot?.dataset.revision) { _, _ in Task { await model.refreshEstimate() } }
        .sheet(isPresented: $showingManual, onDismiss: { Task { await model.refreshEstimate() } }) {
            ManualEstimateView(meal: model.meal, initial: estimate, workspace: workspace, clock: workspace.clock, draftID: model.id)
        }
        .onChange(of: selections) { _, values in importPhotos(values) }
        .sheet(isPresented: $showingCamera) {
            CameraView(onCapture: { data in Task { await model.addPhoto(data) } }, onError: { model.error = $0 })
        }
    }
    private var editActions: some View {
        HStack(spacing: 8) {
            Button(action: save) { actionLabel("保存", primary: true) }
                .disabled(importing || model.pendingImports > 0).accessibilityIdentifier("meal.save")
            Button(role: .destructive) { focused = false; confirmingTrash = true } label: { actionLabel("删除") }
                .disabled(importing || model.pendingImports > 0).accessibilityIdentifier("meal.delete")
            Button(action: close) { actionLabel("返回") }.accessibilityIdentifier("meal.close")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(PixelTheme.canvas)
    }
    private func actionLabel(_ title: String, primary: Bool = false) -> some View {
        Text(title).font(.body.weight(primary ? .semibold : .regular))
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(primary ? Color.primary : PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(primary ? PixelTheme.canvas : Color.primary)
    }
    private func save() {
        focused = false
        Task { if await model.save() { await onSaved(model.meal.time.localDay); dismiss() } }
    }
    private func close() {
        focused = false; importTask?.cancel()
        Task { if await model.discard() { await onClosed(); dismiss() } }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.meal.photoIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.meal.photoIDs.enumerated()), id: \.element) { index, id in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let image = model.images[id] { Image(uiImage: image).resizable().scaledToFill() }
                                    else { Text("无法读取").font(.caption) }
                                }
                                .frame(width: 112, height: 112).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel("饮食照片 \(index + 1)")
                                Button { model.removePhoto(id) } label: {
                                    Image(systemName: "minus").frame(width: 44, height: 44)
                                        .background(Color.primary).foregroundStyle(PixelTheme.canvas)
                                }.buttonStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 10))
                                    .accessibilityLabel("移除第 \(index + 1) 张照片")
                            }
                        }
                    }
                }
            }
            TextField("吃了什么？", text: Binding(get: { model.meal.note }, set: { model.setNote($0) }), axis: .vertical)
                .lineLimit(3...8).frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                .padding(16).background(PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("meal.note").focused($focused)
            HStack(spacing: 10) {
                Button("拍照") { Task { await openCamera() } }.accessibilityIdentifier("meal.camera")
                PhotosPicker(selection: $selections, maxSelectionCount: max(1, 9 - model.meal.photoIDs.count), selectionBehavior: .ordered, matching: .images) {
                    Text("相册")
                }.accessibilityIdentifier("meal.album")
            }
            .buttonStyle(PixelButtonStyle()).disabled(model.meal.photoIDs.count >= 9 || importing)
            if importing { ProgressView("正在读取照片").font(.footnote) }
        }
    }
    private var mealSlots: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
            ForEach(["早餐", "午餐", "晚餐", "加餐"], id: \.self) { slot in
                let selected = model.meal.slot == slot || (model.meal.slot == "下午茶" && slot == "加餐")
                Button { model.setSlot(selected ? "" : slot) } label: {
                    Text(slot).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? Color.primary : PixelTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(selected ? PixelTheme.canvas : PixelTheme.subtle)
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("餐次")
    }
    private var metadata: some View {
        VStack(spacing: 8) {
            Divider().padding(.bottom, 4)
            RecordingTimePicker(selection: Binding(get: { model.selectedDate }, set: { model.selectedDate = $0 }))
                .datePickerStyle(.compact).frame(minHeight: 44)
            Button {
                focused = false
                Task {
                    do { try MealRules.validate(model.meal); try await model.flush(); try await workspace.refresh(); showingManual = true }
                    catch { model.error = error.userMessage }
                }
            } label: {
                AnyLayout(dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                    Text("热量").foregroundStyle(PixelTheme.subtle)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text(estimate.map { $0.totalKcal.description + " kcal" } ?? "待估算").monospacedDigit()
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("meal.calories").accessibilityHint("填写或修改热量")
        }
    }
    private func importPhotos(_ values: [PhotosPickerItem]) {
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
                } catch { model.error = "部分照片未能读取，请重新选择。" }
            }
        }
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
