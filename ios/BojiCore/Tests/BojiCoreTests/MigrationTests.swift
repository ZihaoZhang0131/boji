import Foundation
import Testing
import BojiDomain
import BojiPersistence

@Test(arguments: MigrationPoint.allCases)
func interruptedMigrationAlwaysOpensACompleteGeneration(point: MigrationPoint) async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = ManagedStore(root: root)
    let store = try await manager.open()
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let asset = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "迁移前"; meal.photoIDs = [asset.id]
    let value = meal, operation = UUID()
    try await store.commit(id: operation) { $0.meals = [value]; $0.photos = [asset] }
    await #expect(throws: CocoaError.self) {
        try await manager.rebuild(fault: { at in if at == point { throw CocoaError(.fileWriteOutOfSpace) } }) { $0.meals[0].note = "迁移后" }
    }
    let reopened = try await ManagedStore(root: root).open()
    let state = try await reopened.snapshot()
    #expect(state.meals.count == 1 && state.meals[0].id == meal.id)
    #expect(state.meals[0].note == (point == .afterActivation ? "迁移后" : "迁移前"))
    #expect(try await reopened.readPhoto(asset).count == asset.byteCount)
    let retry = try await reopened.commit(id: operation) { $0.meals.append(value) }
    #expect(retry.alreadyCommitted)
}

@Test func unknownSchemaDoesNotClearDataAndPriorGenerationCanBeRestored() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = ManagedStore(root: root)
    let original = try await manager.open()
    let id = try await original.snapshot().dataset.id
    _ = try await manager.rebuild()
    let recovered = try await manager.restorePrevious()
    #expect(try await recovered.snapshot().dataset.id == id)
    #expect(try await recovered.snapshot().dataset.revision == 0)
    let pointer = root.appendingPathComponent("active.json")
    let valid = try Data(contentsOf: pointer)
    var json = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
    json["schemaVersion"] = 99
    let invalid = try JSONSerialization.data(withJSONObject: json)
    try invalid.write(to: pointer, options: .atomic)
    await #expect(throws: DomainError.unsupportedSchema(99)) { try await ManagedStore(root: root).open() }
    #expect(try Data(contentsOf: pointer) == invalid)
    try valid.write(to: pointer, options: .atomic)
    #expect(try await ManagedStore(root: root).open().snapshot().dataset.id == id)
}
