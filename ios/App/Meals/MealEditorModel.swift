import Foundation
import Observation
import UIKit
import BojiDomain
import BojiPersistence

@MainActor @Observable
final class MealEditorModel: Identifiable {
    let id: UUID
    private(set) var meal: Meal
    private(set) var photos: [PhotoAsset]
    private(set) var images: [UUID: UIImage] = [:]
    private(set) var unreadablePhotos: Set<UUID> = []
    var error: String?
    var busy = false
    private(set) var pendingImports = 0
    var saveStatus: DraftSaveStatus = .idle
    private var draft: RecordDraft
    private let repository: LocalRepository
    private let autosaver: DraftAutosaver
    private let clock: any AppClock
    private let operationID = UUID()
    private var closed = false

    private init(meal: Meal, draft: RecordDraft, photos: [PhotoAsset], repository: LocalRepository, clock: any AppClock) {
        self.id = draft.id; self.meal = meal; self.draft = draft; self.photos = photos
        self.repository = repository; self.clock = clock
        autosaver = DraftAutosaver(repository: repository, clock: clock)
    }

    static func open(repository: LocalRepository, clock: any AppClock, selectedDay: LocalDay, editing: Meal? = nil) async throws -> MealEditorModel {
        let state = try await repository.snapshot()
        let existing = state.drafts.filter { $0.content.kind == .meal && $0.editingRecordID == editing?.id }.max { $0.savedAt < $1.savedAt }
        let draft: RecordDraft
        let meal: Meal
        if let existing, case .meal(let value) = existing.content { draft = existing; meal = value }
        else {
            meal = editing ?? Meal(time: RecordTime(clock: clock, selectedDay: selectedDay))
            draft = RecordDraft(editingRecordID: editing?.id, content: .meal(meal), savedAt: clock.now)
        }
        let model = MealEditorModel(meal: meal, draft: draft, photos: state.photos.filter { meal.photoIDs.contains($0.id) }, repository: repository, clock: clock)
        await model.loadImages()
        return model
    }

    var isEditing: Bool { draft.editingRecordID != nil }
    var statusText: String {
        switch saveStatus {
        case .idle: "尚未修改"
        case .saving: "草稿保存中"
        case .saved: "草稿已保存"
        case .failed(let message): message
        }
    }

    func observeStatus() async {
        while !Task.isCancelled {
            let latest = await autosaver.status
            if saveStatus != latest { saveStatus = latest }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        }
    }
    func refreshEstimate() async {
        guard !closed, let state = try? await repository.snapshot(),
              let stored = state.drafts.first(where: { $0.id == id }), case .meal(let latest) = stored.content,
              latest.inputRevision == meal.inputRevision, latest.lifecycleEpoch == meal.lifecycleEpoch,
              latest.manualRevision >= meal.manualRevision else { return }
        meal.currentEstimateID = latest.currentEstimateID; meal.manualRevision = latest.manualRevision
    }

    func setNote(_ note: String) {
        guard meal.note != note else { return }
        meal.note = note; changedInput(); schedule()
    }
    func setSlot(_ slot: String) { meal.slot = slot.isEmpty ? nil : slot; schedule() }
    func setTags(_ text: String) { meal.tags = text.split(separator: "，").flatMap { $0.split(separator: ",") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; schedule() }

    var selectedDate: Date {
        get {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: meal.time.timeZoneIdentifier) ?? clock.timeZone
            return calendar.date(from: DateComponents(year: meal.time.localDay.year, month: meal.time.localDay.month, day: meal.time.localDay.day, hour: meal.time.hour, minute: meal.time.minute)) ?? clock.now
        }
        set {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: meal.time.timeZoneIdentifier) ?? clock.timeZone
            meal.time.localDay = LocalDay(newValue, timeZone: calendar.timeZone)
            meal.time.hour = calendar.component(.hour, from: newValue); meal.time.minute = calendar.component(.minute, from: newValue)
            meal.time.instant = newValue; schedule()
        }
    }

    func addPhoto(_ data: Data) async {
        guard !closed else { return }
        guard meal.photoIDs.count + pendingImports < 9 else { error = "每餐最多九张照片，已有内容已保留。"; return }
        pendingImports += 1
        defer { pendingImports -= 1 }
        do {
            let photo = try await repository.preparePhoto(data)
            guard !closed else { await repository.releasePreparedPhoto(photo.id); try? await repository.collectOrphanPhotos(); return }
            photos.append(photo); meal.photoIDs.append(photo.id)
            changedInput(); schedule()
            do { images[photo.id] = UIImage(data: try await repository.thumbnail(photo)) }
            catch { unreadablePhotos.insert(photo.id); self.error = "照片预览无法读取，请重新选择。其他内容仍保留。" }
        } catch { self.error = "这张照片未能读取，已添加的照片和文字仍保留。" }
    }
    func removePhoto(_ id: UUID) {
        meal.photoIDs.removeAll { $0 == id }; photos.removeAll { $0.id == id }; images.removeValue(forKey: id); unreadablePhotos.remove(id)
        changedInput(); schedule()
        Task { await repository.releasePreparedPhoto(id) }
    }
    func movePhoto(_ id: UUID, earlier: Bool) {
        guard let index = meal.photoIDs.firstIndex(of: id) else { return }
        let destination = earlier ? index - 1 : index + 1
        guard meal.photoIDs.indices.contains(destination) else { return }
        meal.photoIDs.swapAt(index, destination); changedInput(); schedule()
    }

    func flush() async throws {
        guard !closed else { return }
        draft.content = .meal(meal)
        await autosaver.changed(draft, photos: photos)
        try await autosaver.flush()
        saveStatus = await autosaver.status
    }
    func save() async -> Bool {
        guard !busy, pendingImports == 0 else { return false }
        busy = true; defer { busy = false }
        do {
            try MealRules.validate(meal)
            guard unreadablePhotos.isEmpty else { throw DomainError.invalidValue("请移除或重新选择无法读取的照片") }
            try await flush()
            // Fetch draft identity/estimate changes committed while this form was open.
            let state = try await repository.snapshot()
            if let stored = state.drafts.first(where: { $0.id == id }), case .meal(let value) = stored.content { meal = value }
            try await repository.saveMeal(meal, draftID: id, photos: photos, at: clock.now, operationID: operationID)
            closed = true
            return true
        } catch { self.error = error.userMessage; return false }
    }
    func discard() async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            try await autosaver.discard(draftID: id)
            closed = true
            for photo in photos { await repository.releasePreparedPhoto(photo.id) }
            try? await repository.collectOrphanPhotos()
            return true
        } catch { self.error = error.userMessage; return false }
    }

    private func loadImages() async {
        for photo in photos {
            do {
                guard let image = UIImage(data: try await repository.thumbnail(photo)) else { throw DomainError.missingPhoto(photo.id) }
                images[photo.id] = image
            } catch { unreadablePhotos.insert(photo.id) }
        }
    }
    private func changedInput() { meal.inputRevision += 1; meal.currentEstimateID = nil }
    private func schedule() {
        guard !closed else { return }
        draft.revision += 1; draft.content = .meal(meal); draft.savedAt = clock.now
        let pending = draft, assets = photos
        saveStatus = .saving
        Task { await autosaver.changed(pending, photos: assets) }
    }
}
