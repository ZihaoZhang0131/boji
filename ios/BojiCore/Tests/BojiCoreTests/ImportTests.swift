import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiPortability

private func exportedFixture(_ root: URL) async throws -> ValidatedPackage {
    let source = try await portableFixture(at:root.appendingPathComponent("source"))
    return try PackageReader().read(await PackageExporter().export(repository:source,to:root.appendingPathComponent("exports")).url)
}

@Test func nativeImportIsAtomicRepeatableAndRetainsExternalIdentityThroughAnotherExport() async throws {
    let root = try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package = try await exportedFixture(root), manager = ManagedStore(root:root.appendingPathComponent("target"))
    let original = try await manager.open(), initial = try await original.snapshot()
    let plan = try ImportPlanner.plan(package:package,local:initial)
    #expect(plan.hasChanges && plan.conflicts.isEmpty)
    let imported = try await PackageImporter().apply(plan,package:package,manager:manager)
    let result = try await imported.snapshot()
    #expect(result.meals.count == 2 && result.workouts.count == 1 && result.photos.count == 1 && result.estimates.count == 2)
    #expect(result.profiles.count == 1 && result.goals.count == 1 && result.drafts.count == 1 && result.confirmations.count == 1)
    #expect(result.dataset.id == initial.dataset.id && result.aiSettings.acceptedPolicy == nil && result.jobs.isEmpty)
    #expect(result.activeMeals[0].source?.datasetID == package.manifest.datasetID)
    for photo in result.photos { #expect(try await imported.readPhoto(photo).count == photo.byteCount) }
    await #expect(throws:DomainError.self) { try await original.commit(id:UUID()) { $0.meals = [] } }
    let repeatPlan = try ImportPlanner.plan(package:package,local:result)
    #expect(!repeatPlan.hasChanges && repeatPlan.conflicts.isEmpty)
    _ = try await PackageImporter().apply(repeatPlan,package:package,manager:manager)
    #expect(try await imported.snapshot().dataset.revision == result.dataset.revision)
    let onward = try PackageReader().read(await PackageExporter().export(repository:imported,to:root.appendingPathComponent("onward")).url)
    let third = ManagedStore(root:root.appendingPathComponent("third")), emptyThird = try await third.open()
    let thirdPlan = try ImportPlanner.plan(package:onward,local:await emptyThird.snapshot())
    let thirdStore = try await PackageImporter().apply(thirdPlan,package:onward,manager:third)
    let last = try await thirdStore.snapshot()
    #expect(Set(last.meals.map(\.id)) == Set(result.meals.map(\.id)))
    #expect(try !ImportPlanner.plan(package:package,local:last).hasChanges)
    let rollback = try await manager.restorePrevious()
    #expect(try await rollback.snapshot().meals.isEmpty)
}

@Test func deletedBackupRecordsRequireSeparateRestoreChoiceAndSamePackageNeverDuplicates() async throws {
    let root = try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package = try await exportedFixture(root), manager = ManagedStore(root:root.appendingPathComponent("target"))
    let empty = try await manager.open(), plan = try ImportPlanner.plan(package:package,local:await empty.snapshot())
    let store = try await PackageImporter().apply(plan,package:package,manager:manager)
    let id = try #require(await store.snapshot().activeMeals.first?.id)
    try await store.moveToTrash(kind:.meal,id:id,at:Date(),operationID:UUID())
    try await store.permanentlyDelete(kind:.meal,id:id,confirmed:true,at:Date(),operationID:UUID())
    let state = try await store.snapshot()
    var options = ImportOptions();options.conflicts = .useImported
    let preview = try ImportPlanner.plan(package:package,local:state,options:options)
    #expect(preview.result.activeMeals.isEmpty)
    let restore = try #require(preview.conflicts.first { $0.restoration })
    options.restoreDeleted = [restore.id]
    let explicit = try ImportPlanner.plan(package:package,local:state,options:options)
    let restored = try await PackageImporter().apply(explicit,package:package,manager:manager)
    #expect(try await restored.snapshot().activeMeals.first?.id == id)
    #expect(try await restored.snapshot().tombstones.isEmpty)
    let repeatPlan = try ImportPlanner.plan(package:package,local:await restored.snapshot())
    #expect(!repeatPlan.hasChanges)
}

@Test func contentConflictsDefaultToLocalAndPreviewRejectsConcurrentChanges() async throws {
    let root = try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package = try await exportedFixture(root), manager = ManagedStore(root:root.appendingPathComponent("target"))
    let empty = try await manager.open(), initial = try ImportPlanner.plan(package:package,local:await empty.snapshot())
    let store = try await PackageImporter().apply(initial,package:package,manager:manager)
    var meal = try #require(await store.snapshot().activeMeals.first);meal.note = "Local correction"
    try await store.saveMeal(meal,draftID:nil,operationID:UUID())
    let preview = try ImportPlanner.plan(package:package,local:await store.snapshot())
    #expect(preview.result.activeMeals.first?.note == "Local correction" && !preview.conflicts.isEmpty)
    var options = ImportOptions();options.conflicts = .useImported
    let replace = try ImportPlanner.plan(package:package,local:await store.snapshot(),options:options)
    try await store.commit(id:UUID()) { $0.aiSettings.automatic = true }
    await #expect(throws:DomainError.conflict) { try await PackageImporter().apply(replace,package:package,manager:manager) }
    #expect(try await store.snapshot().activeMeals.first?.note == "Local correction")
}

@Test(arguments:MigrationPoint.allCases)
func interruptedImportAlwaysReopensOneCompleteGeneration(point:MigrationPoint) async throws {
    let root = try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package = try await exportedFixture(root), target = root.appendingPathComponent("target"), manager = ManagedStore(root:target)
    let empty = try await manager.open(), plan = try ImportPlanner.plan(package:package,local:await empty.snapshot())
    await #expect(throws:CocoaError.self) {
        try await PackageImporter().apply(plan,package:package,manager:manager,fault:{ here in if String(describing:here) == String(describing:point) { throw CocoaError(.fileWriteOutOfSpace) } })
    }
    let reopened = try await ManagedStore(root:target).open(), state = try await reopened.snapshot()
    if case .afterActivation = point { #expect(state.meals.count == 2 && state.workouts.count == 1) }
    else { #expect(state.meals.isEmpty && state.workouts.isEmpty) }
    for photo in state.photos { #expect(try await reopened.readPhoto(photo).count == photo.byteCount) }
}

@Test func sameDayForeignHistoriesArePreviewedAndDependentTrainingDoesNotLoseItsSource() async throws {
    let root = try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package = try await exportedFixture(root), local = try await portableFixture(at:root.appendingPathComponent("local"))
    let state = try await local.snapshot()
    let defaultPlan = try ImportPlanner.plan(package:package,local:state)
    #expect(defaultPlan.conflicts.contains { $0.title.contains("同日身体资料") })
    #expect(defaultPlan.result.profiles == state.profiles)
    #expect(defaultPlan.result.workouts.count == state.workouts.count)
    #expect(defaultPlan.notices.contains { $0.contains("身体资料来源") })
    var options = ImportOptions();options.conflicts = .useImported
    let adopted = try ImportPlanner.plan(package:package,local:state,options:options)
    #expect(adopted.result.profiles.count == 2 && adopted.result.workouts.count == 2)
    #expect(ProfileRules.effective(on:state.profiles[0].effectiveDay,versions:adopted.result.profiles)?.source?.datasetID == package.manifest.datasetID)
}

@Test func discardedImportedDraftNeedsExplicitRestorationAndCannotBeAutosavedLate() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package=try await exportedFixture(root),manager=ManagedStore(root:root.appendingPathComponent("target"))
    let empty=try await manager.open(),plan=try ImportPlanner.plan(package:package,local:await empty.snapshot())
    let store=try await PackageImporter().apply(plan,package:package,manager:manager)
    let draft=try #require(await store.snapshot().drafts.first)
    try await store.discardDraft(id:draft.id,operationID:UUID())
    await #expect(throws:DomainError.conflict) { try await store.saveDraft(draft,operationID:UUID()) }
    var options=ImportOptions();options.conflicts = .useImported
    let preview=try ImportPlanner.plan(package:package,local:await store.snapshot(),options:options)
    #expect(preview.result.drafts.isEmpty)
    let conflict=try #require(preview.conflicts.first { $0.id == "draft/\(draft.id)" && $0.restoration })
    options.restoreDeleted=[conflict.id]
    let restored=try ImportPlanner.plan(package:package,local:await store.snapshot(),options:options)
    #expect(restored.result.drafts.count == 1 && restored.result.tombstones.isEmpty)
}

@Test func confirmationOnlyImportIsPreviewedAndPartialFactsNeverRegainCompleteness() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package=try await exportedFixture(root),manager=ManagedStore(root:root.appendingPathComponent("target"))
    let empty=try await manager.open(),plan=try ImportPlanner.plan(package:package,local:await empty.snapshot())
    let store=try await PackageImporter().apply(plan,package:package,manager:manager)
    try await store.commit(id:UUID()) { $0.confirmations=[] }
    let current=try await store.snapshot()
    let retained=try ImportPlanner.plan(package:package,local:current)
    #expect(!retained.hasChanges && retained.conflicts.contains { $0.id.hasPrefix("confirmation/") })
    var options=ImportOptions();options.conflicts = .useImported
    let restored=try ImportPlanner.plan(package:package,local:current,options:options)
    #expect(restored.hasChanges && restored.result.confirmations.count == 1)
    var extra=Meal(time:current.activeMeals[0].time);extra.note="Additional local fact"
    try await store.saveMeal(extra,draftID:nil,operationID:UUID())
    let mixed=try ImportPlanner.plan(package:package,local:await store.snapshot(),options:options)
    #expect(mixed.result.confirmations.isEmpty && mixed.notices.contains { $0.contains("不完全相同") })
}

@Test func stagingMakesAnIndependentVerifiedCopyBeforePreview() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let package=try await exportedFixture(root)
    let staged=try await PackageStager().stage(package.url,in:root.appendingPathComponent("private"))
    #expect(staged.manifest == package.manifest && staged.url != package.url)
    try FileManager.default.removeItem(at:package.url)
    #expect(try PackageReader().read(staged.url).snapshot == staged.snapshot)
}
