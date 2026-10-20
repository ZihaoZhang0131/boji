import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiPortability

private func legacyFixture(photo:String? = nil) throws -> Data {
    let image = try photo ?? "data:image/png;base64," + imageFixture().base64EncodedString()
    let profile:[String:Any] = ["sex":"male","age":28,"height":175,"weight":70,"activity":1.2,"effectiveDate":"2026-10-17","updatedAt":"2026-10-17T09:00:00.000Z"]
    let demo:[String:Any] = ["status":"ready","source":"demo-ai","kcal":200,"model":"演示数据 · 非模型推理","items":[["name":"fixture","grams":100,"kcal":200]]]
    let manual:[String:Any] = ["status":"manual","source":"manual","kcal":300,"items":[["name":"fixture","grams":150,"kcal":300]],"originalEstimate":demo,"updatedAt":"2026-10-17T10:00:00Z"]
    let exercise:[String:Any] = ["name":"bodyweight","type":"body","unit":"自重","sets":[["reps":8,"done":true],["reps":7,"done":false]]]
    return try JSONSerialization.data(withJSONObject:[
        "schema_version":1,"prototype":true,"exported_at":"2026-10-17T12:00:00Z",
        "meals":[["id":"real-a","date":"2026-10-17","time":"12:30","note":"Synthetic prototype","photos":[image],"energy":manual],
                 ["id":"real-demo-energy","date":"2026-10-18","time":"08:00","note":"Real meal with simulated energy","photos":[],"energy":demo],
                 ["id":"sample","date":"2026-10-18","time":"12:00","note":"Demo","demo":true,"photos":[]]],
        "workouts":[["id":"real-workout","date":"2026-10-17","time":"18:00","name":"Training","exercises":[exercise],"energy":["activeKcal":138,"weight":70,"minutes":45,"met":3.5,"method":"MET-net-v1"]]],
        "draft":["id":"active-draft","date":"2026-10-19","time":"18:00","name":"Draft","exercises":[exercise],"duration":20,"met":3.5],
        "profile":profile,"profileHistory":[profile],"plan":["goal":"保持状态","start":"2026-10-17","note":"Fixture"],"planHistory":[],
        "complete":["2026-10-17","2026-10-18"],"energySettings":["consent":true,"autoEstimate":true],"secret":"never-copy-unknown-field"
    ],options:[.sortedKeys])
}
private func legacyOptions() throws -> PrototypeOptions {
    var value=PrototypeOptions(timeZoneIdentifier:"Asia/Shanghai",undatedProfileDay:try LocalDay(year:2026,month:10,day:17))
    value.confirmedUnitsAndProvenance=true;value.confirmedAmbiguousHistory=true;return value
}

@Test func prototypeMigrationPreservesFactsAndIsRepeatableWithoutInheritingDemoOrAuthorization() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let importer=PrototypeImporter(),data=try legacyFixture(),options=try legacyOptions()
    let conversion=try await importer.convert(data,options:options,to:root),first=conversion.package.snapshot
    #expect(first.meals.count==2 && first.photos.count==1 && first.workouts.count==1 && first.profiles.count==1 && first.goals.count==1 && first.drafts.count==1)
    #expect(first.workouts[0].exercises[0].sets.count==1 && first.workouts[0].energyHistory[0].kcal==138)
    if case .workout(let draft)=first.drafts[0].content { #expect(draft.exercises[0].sets.count==2 && !draft.exercises[0].sets[1].completed) } else { Issue.record("Expected training draft") }
    let manual=try #require(first.estimates.first{$0.source == .manual})
    #expect(manual.totalKcal==300 && first.estimates.first{$0.id==manual.previousRevisionID}?.source == .demo)
    #expect(first.meals.first{$0.note.contains("simulated")}?.currentEstimateID==nil)
    #expect(first.confirmations.count==1 && first.aiSettings==AISettings() && first.jobs.isEmpty)
    #expect(first.meals[0].time.timeZoneIdentifier=="Asia/Shanghai" && first.meals[0].time.instant==nil)
    let again=try await importer.convert(data,options:options,to:root)
    #expect(again.package.snapshot==first)
    let manager=ManagedStore(root:root.appendingPathComponent("target")),empty=try await manager.open()
    let plan=try ImportPlanner.plan(package:conversion.package,local:await empty.snapshot())
    let store=try await PackageImporter().apply(plan,package:conversion.package,manager:manager)
    #expect(try !ImportPlanner.plan(package:again.package,local:await store.snapshot()).hasChanges)
    for entry in conversion.package.manifest.files where entry.path.hasSuffix(".json") {
        #expect(try !String(contentsOf:conversion.package.url.appendingPathComponent(entry.path),encoding:.utf8).contains("never-copy-unknown-field"))
    }
}

@Test(arguments:["assets/meal.jpg","https://example.invalid/image.jpg","data:image/png;base64,not-image"])
func prototypeIncompletePhotosCannotBeSilentlyReplaced(photo:String) async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    await #expect(throws:(any Error).self) { try await PrototypeImporter().convert(legacyFixture(photo:photo),options:legacyOptions(),to:root) }
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
}

@Test func prototypeRequiresExplicitTimezoneUnitsAndAmbiguousHistoryConfirmation() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let importer=PrototypeImporter(),data=try legacyFixture()
    var object=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
    object["profileHistory"]=[["sex":"male","age":28,"height":175,"weight":70,"activity":1.2]];object.removeValue(forKey:"profile")
    let ambiguous=try JSONSerialization.data(withJSONObject:object)
    #expect(try await importer.inspect(ambiguous).needsHistoryConfirmation)
    let noConsent=PrototypeOptions(timeZoneIdentifier:"Asia/Shanghai",undatedProfileDay:try LocalDay(year:2026,month:10,day:17))
    await #expect(throws:PackageError.self) { try await importer.convert(ambiguous,options:noConsent,to:root) }
    var options=try legacyOptions();options.confirmedAmbiguousHistory=false
    let missingHistory=options
    await #expect(throws:PackageError.self) { try await importer.convert(ambiguous,options:missingHistory,to:root) }
    options.confirmedAmbiguousHistory=true
    let converted=try await importer.convert(ambiguous,options:options,to:root)
    #expect(converted.package.snapshot.profiles[0].effectiveDay==options.undatedProfileDay)
}
