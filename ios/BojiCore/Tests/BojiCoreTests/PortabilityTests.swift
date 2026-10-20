import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiPortability

func portableFixture(at root: URL) async throws -> LocalRepository {
    let store = try await LocalRepository.open(at: root), clock = FixedClock("2026-10-17T12:00:00Z")
    let photo = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "Synthetic meal for package verification"; meal.photoIDs = [photo.id]
    let first = EstimateRevision(recordID: meal.id, inputRevision: 0, source: .manual, items: [FoodItem(name:"fixture", grams:100, kcal:200)], totalKcal:200, createdAt:clock.now)
    var second = first; second.id = UUID(); second.previousRevisionID = first.id; second.items = [try FoodEstimateRules.changingGrams(first.items[0], to: 150)]; second.totalKcal = 300
    meal.currentEstimateID = second.id; meal.manualRevision = 2
    var trash = Meal(time: meal.time); trash.note = "Synthetic trash"; trash.deletedAt = clock.now; trash.photoIDs = [photo.id]
    var workout = Workout(time: meal.time); workout.name = "Synthetic training"
    workout.exercises = [Exercise(name:"Bodyweight fixture",kind:.bodyweight,sets:[WorkoutSet(reps:8,completed:true)])]
    let profile = ProfileVersion(effectiveDay:meal.time.localDay,sequence:1,profile:BodyProfile(sex:.male,age:28,heightCM:175,weightKG:70,activityFactor:1.2),createdAt:clock.now)
    let energy = try EnergyRules.workoutSnapshot(weightKG:70,minutes:45,intensity:.regular,profileID:profile.id,at:clock.now)
    workout.energyHistory = [energy]; workout.currentEnergyID = energy.id
    var draftMeal = Meal(time: meal.time); draftMeal.note = "Synthetic draft"; draftMeal.photoIDs = [photo.id]
    let draft = RecordDraft(content:.meal(draftMeal),savedAt:clock.now)
    let inputMeal = meal, inputTrash = trash, inputWorkout = workout, corrected = second
    try await store.commit(id:UUID()) { state in
        state.meals = [inputMeal,inputTrash]; state.workouts = [inputWorkout]; state.photos = [photo]; state.estimates = [first,corrected]
        state.profiles = [profile]; state.goals = [GoalStage(startDay:inputMeal.time.localDay,goal:.maintain,sequence:1)]
        state.drafts = [draft]; state.confirmations = [DayConfirmation(day:inputMeal.time.localDay,confirmedAt:clock.now,factsRevision:1)]
        state.aiSettings.serviceURL = URL(string:"https://private-service-marker.invalid")
        state.aiSettings.acceptedPolicy = "private-consent-marker"; state.aiSettings.automatic = true
        state.backup.directoryBookmark = Data("private-bookmark-marker".utf8)
    }
    return store
}

@Test func portablePackageRoundTripsAllEntitiesAndExcludesRuntimeCapabilities() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:root) }
    let store = try await portableFixture(at:root.appendingPathComponent("source")), before = try await store.snapshot()
    let published = try await PackageExporter().export(repository:store,to:root.appendingPathComponent("exports"))
    let read = try PackageReader().read(published.url)
    #expect(read.snapshot.meals.sorted { $0.id.uuidString < $1.id.uuidString } == before.meals.sorted { $0.id.uuidString < $1.id.uuidString } && read.snapshot.workouts == before.workouts)
    #expect(read.snapshot.drafts == before.drafts && read.snapshot.profiles == before.profiles && read.snapshot.goals == before.goals)
    #expect(read.snapshot.estimates == before.estimates && read.snapshot.confirmations == before.confirmations)
    #expect(read.snapshot.aiSettings == AISettings() && read.snapshot.backup == BackupState() && read.snapshot.jobs.isEmpty)
    #expect(read.contents.records.daySummaries.first?.knownIntakeKcal == 300)
    #expect(read.contents.records.daySummaries.first?.complete == true)
    #expect(read.contents.records.daySummaries.first?.knownWorkoutKcal == 138)
    #expect(read.manifest.files.count == 9 && read.manifest.files.filter { $0.path.hasPrefix("media/") }.count == 1)
    for file in read.manifest.files where !file.path.hasPrefix("media/") {
        let text = try String(contentsOf:published.url.appendingPathComponent(file.path),encoding:.utf8)
        for secret in ["private-service-marker", "private-consent-marker", "private-bookmark-marker", "requestCreatedAt"] { #expect(!text.contains(secret)) }
    }
    if let output = ProcessInfo.processInfo.environment["BOJI_WRITE_SAMPLE_PACKAGE"] {
        let destination = URL(fileURLWithPath:output)
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw PackageError.invalid("样例输出目录已存在") }
        try FileManager.default.copyItem(at:published.url,to:destination)
    }
}

@Test func exportLeaseKeepsOneRevisionWhileRecordsAreEditedAndPurged() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:root) }
    let store = try await portableFixture(at:root.appendingPathComponent("source")), before = try await store.snapshot()
    let exporter = PackageExporter(fault: { point in
        if case .afterJSON = point {
            for meal in before.activeMeals {
                try await store.moveToTrash(kind:.meal,id:meal.id,at:Date(),operationID:UUID())
                try await store.permanentlyDelete(kind:.meal,id:meal.id,confirmed:true,at:Date(),operationID:UUID())
            }
            try await store.collectOrphanPhotos()
        }
    })
    let output = try await exporter.export(repository:store,to:root.appendingPathComponent("exports"))
    let restored = try PackageReader().read(output.url)
    #expect(restored.manifest.revision == before.dataset.revision && restored.snapshot.meals.sorted { $0.id.uuidString < $1.id.uuidString } == before.meals.sorted { $0.id.uuidString < $1.id.uuidString })
    #expect(try await store.snapshot().activeMeals.isEmpty)
}

@Test(arguments: [ExportPoint.afterJSON,.afterPhoto,.beforeManifest,.beforePublish])
func failedExportDoesNotPublishOrDamageLastCompletePackage(point: ExportPoint) async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:root) }
    let store = try await portableFixture(at:root.appendingPathComponent("source")), exports = root.appendingPathComponent("exports")
    let good = try await PackageExporter().export(repository:store,to:exports)
    let failing = PackageExporter(fault: { here in
        let match: Bool
        switch (here,point) { case (.afterJSON,.afterJSON),(.afterPhoto,.afterPhoto),(.beforeManifest,.beforeManifest),(.beforePublish,.beforePublish): match = true; default:match = false }
        if match { throw CocoaError(.fileWriteOutOfSpace) }
    })
    await #expect(throws:CocoaError.self) { try await failing.export(repository:store,to:exports) }
    #expect(try FileManager.default.contentsOfDirectory(atPath:exports.path).count == 1)
    #expect(try PackageReader().read(good.url).manifest == good.manifest)
}

@Test func missingLocalMediaFailsExportWithoutAFalseSuccess() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:root) }
    let source = root.appendingPathComponent("source"), store = try await portableFixture(at:source)
    let photo = try #require(await store.snapshot().photos.first)
    try FileManager.default.removeItem(at:source.appendingPathComponent(photo.relativePath))
    await #expect(throws:DomainError.missingPhoto(photo.id)) { try await PackageExporter().export(repository:store,to:root.appendingPathComponent("exports")) }
}

@Test(arguments:["unknownVersion","badHash","missingPhoto","absolute","parent","symlink","oversize","corruptImage","badNumber"])
func packagePreflightRejectsUntrustedFilesBeforeAnyDatabaseWrite(attack:String) async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at:root) }
    let store = try await portableFixture(at:root.appendingPathComponent("source"))
    let output = try await PackageExporter().export(repository:store,to:root.appendingPathComponent("exports"))
    let before = try await store.snapshot(), package = output.url
    var manifest = output.manifest
    let photo = try #require(before.photos.first), location = package.appendingPathComponent(photo.relativePath)
    switch attack {
    case "unknownVersion": manifest.schemaVersion = 999
    case "badHash": manifest.files[0].sha256 = String(repeating:"0",count:64)
    case "missingPhoto": try FileManager.default.removeItem(at:location)
    case "absolute": manifest.files[0].path = "/etc/passwd"
    case "parent": manifest.files[0].path = "../outside"
    case "symlink":
        try FileManager.default.removeItem(at:location)
        try FileManager.default.createSymbolicLink(at:location,withDestinationURL:root.appendingPathComponent("source").appendingPathComponent(photo.relativePath))
    case "oversize":
        let extra = package.appendingPathComponent("huge.json"); FileManager.default.createFile(atPath:extra.path,contents:nil)
        let handle = try FileHandle(forWritingTo:extra);try handle.truncate(atOffset:UInt64(PackageLimits.totalBytes + 1));try handle.close()
    case "corruptImage":
        let data = Data("Not an image".utf8); try data.write(to:location)
        let i = try #require(manifest.files.firstIndex { $0.path == photo.relativePath })
        manifest.files[i].sha256 = PackageHash.sha256(data); manifest.files[i].byteCount = data.count
    case "badNumber":
        let url = package.appendingPathComponent("records.json")
        var json = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        var meals = json["meals"] as! [[String:Any]]; meals[0]["inputRevision"] = -1; json["meals"] = meals
        let data = try JSONSerialization.data(withJSONObject:json);try data.write(to:url)
        let i = try #require(manifest.files.firstIndex { $0.path == "records.json" }); manifest.files[i].sha256 = PackageHash.sha256(data);manifest.files[i].byteCount = data.count
    default: break
    }
    try PackageCodec.encode(manifest).write(to:package.appendingPathComponent("manifest.json"))
    #expect(throws:(any Error).self) { try PackageReader().read(package) }
    #expect(try await store.snapshot() == before)
}
