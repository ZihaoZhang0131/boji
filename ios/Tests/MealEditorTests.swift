import XCTest
import UIKit
import BojiDomain
import BojiPersistence
@testable import Boji

@MainActor
final class MealEditorTests: XCTestCase {
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

    func testEditorRestoresDraftAndSavesSameIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = SystemClock()
        let repository = try await LocalRepository.open(at: root)
        let day = LocalDay(clock.now, timeZone: clock.timeZone).adding(days: -1)
        let first = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day)
        let emptySaved = await first.save(); XCTAssertFalse(emptySaved)
        first.setNote("只写一句话"); first.setSlot("午餐"); first.setTags("补记，外食")
        try await first.flush()
        let restored = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day)
        XCTAssertEqual(first.id, restored.id)
        XCTAssertEqual(restored.meal.note, "只写一句话")
        let saved = await restored.save(); XCTAssertTrue(saved)
        let state = try await repository.snapshot()
        XCTAssertEqual(state.meals.count, 1); XCTAssertTrue(state.drafts.isEmpty)
        XCTAssertEqual(state.meals[0].time.localDay, day)
        XCTAssertEqual(state.meals[0].slot, "午餐")
        XCTAssertEqual(state.meals[0].tags, ["补记", "外食"])
        let editor = try await MealEditorModel.open(repository: repository, clock: clock, selectedDay: day, editing: state.meals[0])
        editor.setNote("不应提交"); try await editor.flush()
        let discarded = await editor.discard(); XCTAssertTrue(discarded)
        let after = try await repository.snapshot()
        XCTAssertEqual(after.meals[0].note, "只写一句话")
    }
}
