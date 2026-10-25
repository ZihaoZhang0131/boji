import XCTest
import UIKit
import BojiDomain
import BojiPersistence
@testable import Boji

@MainActor
final class MealEditorTests: XCTestCase {
    func testTrashDiscardsEditsPreservesPhotosAndRetriesAfterFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = SystemClock(), failure = MealDeleteFailure()
        let repository = try await LocalRepository.open(at: root, fault: { try failure.check($0) })
        let day = LocalDay(clock.now, timeZone: clock.timeZone)
        let first = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day)
        first.setNote("保存的原记录")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try XCTUnwrap(image.pngData())
        await first.addPhoto(data)
        let saved = await first.save(); XCTAssertTrue(saved)
        let savedState = try await repository.snapshot()
        let original = try XCTUnwrap(savedState.meals.first)
        let viewing = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day, editing: original)
        let returned = await viewing.discard(); XCTAssertTrue(returned)
        let afterViewing = try await repository.snapshot()
        XCTAssertEqual(afterViewing.meals.first, original)
        XCTAssertTrue(afterViewing.jobs.isEmpty)

        let editor = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day, editing: original)
        editor.setNote("不应保存的输入"); editor.removePhoto(original.photoIDs[0])
        await editor.addPhoto(data); try await editor.flush()
        failure.arm()
        let failed = await editor.trash(); XCTAssertFalse(failed)
        XCTAssertEqual(editor.meal.note, "不应保存的输入"); XCTAssertNotNil(editor.error)
        let unchanged = try await repository.snapshot()
        XCTAssertEqual(unchanged.activeMeals.first, original)
        XCTAssertEqual(unchanged.drafts.count, 1)

        let trashed = await editor.trash(); XCTAssertTrue(trashed)
        let removed = try await repository.snapshot()
        XCTAssertTrue(removed.activeMeals.isEmpty); XCTAssertTrue(removed.drafts.isEmpty)
        XCTAssertEqual(removed.meals.first?.note, original.note)
        XCTAssertEqual(removed.meals.first?.photoIDs, original.photoIDs)
        let photo = try XCTUnwrap(removed.photos.first { $0.id == original.photoIDs[0] })
        let restoredBytes = try await repository.readPhoto(photo); XCTAssertFalse(restoredBytes.isEmpty)
        try await repository.restore(kind: .meal, id: original.id, at: clock.now, operationID: UUID())
        let lateSave = await editor.save(); XCTAssertFalse(lateSave)
        await editor.addPhoto(data)
        let restored = try await repository.snapshot()
        XCTAssertEqual(restored.activeMeals.first?.note, original.note)
        XCTAssertEqual(restored.activeMeals.first?.photoIDs, original.photoIDs)
        XCTAssertTrue(restored.drafts.isEmpty)
    }
    func testPhotoPartialFailureLimitAndDiscardProtectFormalCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await LocalRepository.open(at: root), clock = SystemClock()
        let day = LocalDay(clock.now, timeZone: clock.timeZone)
        let model = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        let data = try XCTUnwrap(image.pngData())
        await model.addPhoto(data); await model.addPhoto(Data("broken image".utf8))
        XCTAssertEqual(model.meal.photoIDs.count, 1); XCTAssertNotNil(model.error)
        for _ in 0..<9 { await model.addPhoto(data) }
        XCTAssertEqual(model.meal.photoIDs.count, 9)
        let saved = await model.save(); XCTAssertTrue(saved)
        let original = try await repository.snapshot().meals[0]
        let edit = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day, editing: original)
        edit.removePhoto(original.photoIDs[0]); try await edit.flush()
        let discarded = await edit.discard(); XCTAssertTrue(discarded)
        await edit.addPhoto(data)
        let after = try await repository.snapshot()
        XCTAssertEqual(after.meals[0].photoIDs, original.photoIDs); XCTAssertTrue(after.drafts.isEmpty)
        for photo in after.photos where original.photoIDs.contains(photo.id) { let copy = try await repository.readPhoto(photo); XCTAssertFalse(copy.isEmpty) }
    }
    func testFormPortionChangesKeepReferenceAndUnknownIsNotZero() throws {
        XCTAssertNil(DecimalInput.parse("1,000"))
        var row = FoodItemInput(FoodItem(name: "米饭", grams: 100, kcal: 200))
        row.setGrams("150"); XCTAssertEqual(try row.value().kcal, 300)
        row.setGrams("33.333"); row.setGrams("100"); XCTAssertEqual(try row.value().kcal, 200)
        row.setCalories("250"); row.setGrams("200"); XCTAssertEqual(try row.value().kcal, 500)
        var unknown = FoodItemInput.empty(name: "整餐")
        XCTAssertThrowsError(try unknown.value())
        unknown.setCalories("600"); unknown.setGrams("150")
        XCTAssertEqual(try unknown.value().kcal, 600)
        unknown.setCalories("NaN"); XCTAssertThrowsError(try unknown.value())
    }

    func testEditorStartsFreshAfterDiscardAndSavesSameIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = SystemClock()
        let repository = try await LocalRepository.open(at: root)
        let day = LocalDay(clock.now, timeZone: clock.timeZone).adding(days: -1)
        let first = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day)
        let emptySaved = await first.save(); XCTAssertFalse(emptySaved)
        first.setNote("只写一句话"); first.setSlot("午餐"); first.setTags("补记，外食")
        try await first.flush()
        let discarded = await first.discard(); XCTAssertTrue(discarded)
        let restored = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day)
        XCTAssertNotEqual(first.id, restored.id)
        XCTAssertEqual(restored.meal.note, "")
        restored.setNote("只写一句话"); restored.setSlot("午餐"); restored.setTags("补记，外食")
        let saved = await restored.save(); XCTAssertTrue(saved)
        let state = try await repository.snapshot()
        XCTAssertEqual(state.meals.count, 1); XCTAssertTrue(state.drafts.isEmpty)
        XCTAssertEqual(state.meals[0].time.localDay, day)
        XCTAssertEqual(state.meals[0].slot, "午餐")
        XCTAssertEqual(state.meals[0].tags, ["补记", "外食"])
        let editor = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day, editing: state.meals[0])
        editor.setNote("不应提交"); try await editor.flush()
        let editDiscarded = await editor.discard(); XCTAssertTrue(editDiscarded)
        let after = try await repository.snapshot()
        XCTAssertEqual(after.meals[0].note, "只写一句话")
    }
}

private final class MealDeleteFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    func arm() { lock.withLock { armed = true } }
    func check(_ point: CommitPoint) throws {
        if case .beforeSave = point {
            let shouldFail = lock.withLock { let value = armed; armed = false; return value }
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        }
    }
}
