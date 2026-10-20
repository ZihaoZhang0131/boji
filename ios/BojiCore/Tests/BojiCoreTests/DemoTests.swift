import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiEstimation
import BojiPortability

@Test func demoCannotUploadOrExportAndLeavesPersonalDraftUntouched() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = FixedClock("2026-10-17T12:00:00Z")
    let repository = try await LocalRepository.open(at: root)
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "个人草稿"
    let draft = RecordDraft(content: .meal(meal), savedAt: clock.now)
    try await repository.commit(id: UUID()) { $0.drafts = [draft] }
    let before = try await repository.snapshot()
    let session = WorkspaceSession(personal: repository, clock: clock)
    try await session.enterDemo()
    let demo = try await session.activeRepository().snapshot()
    #expect(demo.dataset.id != before.dataset.id)
    #expect(demo.dataset.mode == .demo && demo.meals.count == 1)
    #expect(throws: DomainError.demoOperationDisabled) { try ExportPolicy.requirePersonalDataset(demo) }
    await #expect(throws: DomainError.demoOperationDisabled) { try await DemoDisabledEstimationService().configuration() }
    await session.leaveDemo()
    #expect(try await session.activeRepository().snapshot() == before)
    try await session.enterDemo()
    #expect(try await session.activeRepository().snapshot().dataset.id != demo.dataset.id)
    await session.leaveDemo()
    #expect(try await session.activeRepository().snapshot() == before)
}
