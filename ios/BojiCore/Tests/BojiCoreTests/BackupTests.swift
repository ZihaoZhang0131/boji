import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiPortability

private func destination(_ root:URL,_ name:String="chosen") throws -> URL {
    let directory=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);return directory
}
private func backupFolder(_ root:URL,_ state:DatasetSnapshot)->URL { root.appendingPathComponent("Boji/"+state.dataset.id.uuidString) }
private func pointer(_ folder:URL) throws -> BackupPointer { try PackageCodec.decode(BackupPointer.self,from:Data(contentsOf:folder.appendingPathComponent("latest.json"))) }

@Test func directoryBackupPublishesCompleteSnapshotsAndNeverDirtiesItself() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root)
    let before=try await store.snapshot(),backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"))
    try await backup.connect(chosen);await backup.run(immediate:true)
    let saved=try await store.snapshot(),folder=backupFolder(chosen,saved)
    #expect(saved.backup.lastError==nil && !saved.backup.dirty && [.written,.unknown].contains(saved.backup.status))
    #expect(saved.dataset.revision==before.dataset.revision && saved.backup.lastPublishedRevision==before.dataset.revision)
    let latest=try pointer(folder),package=try PackageReader().read(folder.appendingPathComponent(latest.package))
    #expect(package.snapshot.meals.count==2 && package.snapshot.photos.count==1)
    await backup.run(immediate:true)
    #expect(try pointer(folder)==latest)
    try await store.commit(id:UUID()) { $0.meals[0].tags=["next revision"] }
    await backup.run(immediate:true)
    #expect(try pointer(folder).revision==saved.dataset.revision+1)
    #expect(try PackageReader().read(folder.appendingPathComponent(latest.package)).manifest.exportID==latest.exportID)
    try await backup.disconnect();try await store.commit(id:UUID()) { $0.aiSettings.automatic=true }
    #expect(try await store.snapshot().backup.status == .disconnected)
    #expect(FileManager.default.fileExists(atPath:folder.appendingPathComponent(latest.package).path))
}

@Test(arguments:BackupPoint.allCases)
func interruptedBackupKeepsPreviousCompletePackageAndRecoversOwnPublishedPointer(point:BackupPoint) async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),cache=root.appendingPathComponent("cache")
    let backup=DirectoryBackup(repository:store,cache:cache);try await backup.connect(chosen);await backup.run(immediate:true)
    let state=try await store.snapshot(),folder=backupFolder(chosen,state),old=try pointer(folder)
    try await store.commit(id:UUID()) { $0.meals[0].tags=["changed"] }
    let failing=DirectoryBackup(repository:store,cache:cache,fault:{ if String(describing:$0)==String(describing:point) { throw CocoaError(.fileWriteOutOfSpace) } })
    await failing.run(immediate:true)
    #expect(try await store.snapshot().backup.dirty)
    #expect(try PackageReader().read(folder.appendingPathComponent(old.package)).manifest.exportID==old.exportID)
    if case .afterPointer=point { #expect(try pointer(folder).revision>old.revision) }
    else { #expect(try pointer(folder)==old) }
    let restarted=DirectoryBackup(repository:store,cache:cache);await restarted.run(immediate:true)
    #expect(try await store.snapshot().backup.lastError==nil)
    #expect(try await !store.snapshot().backup.dirty)
}

@Test func backupDetectsExternalModificationAndDoesNotOverwriteUnknownFilesOrReimportData() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"))
    let unrelated=chosen.appendingPathComponent("private.txt"),bytes=Data("not a Boji file".utf8)
    try bytes.write(to:unrelated);try await backup.connect(chosen);await backup.run(immediate:true)
    let before=try await store.snapshot(),folder=backupFolder(chosen,before),old=try pointer(folder)
    try Data("external pointer edit".utf8).write(to:folder.appendingPathComponent("latest.json"))
    try await store.commit(id:UUID()) { $0.meals[0].tags=["still saves locally"] }
    await backup.run(immediate:true)
    #expect(try await store.snapshot().backup.status == .failed)
    #expect(try Data(contentsOf:folder.appendingPathComponent("latest.json"))==Data("external pointer edit".utf8))
    #expect(try Data(contentsOf:unrelated)==bytes)
    #expect(try PackageReader().read(folder.appendingPathComponent(old.package)).snapshot.meals.count==before.meals.count)
    let replacement=try destination(root,"new-folder");try await backup.connect(replacement);await backup.run(immediate:true)
    #expect(try await [.written,.unknown].contains(store.snapshot().backup.status))
    let unknown=try destination(root,"unknown"),occupied=backupFolder(unknown,before)
    try FileManager.default.createDirectory(at:occupied,withIntermediateDirectories:true);try bytes.write(to:occupied.appendingPathComponent("mine.txt"))
    await #expect(throws:DirectoryBackupError.self) { try await backup.connect(unknown) }
    #expect(try Data(contentsOf:occupied.appendingPathComponent("mine.txt"))==bytes)
}

@Test func uploadStatusRequiresEveryFileAndNeverClaimsMacDelivery() {
    let uploaded=UploadEvidence(ubiquitous:true,uploaded:true,uploading:false)
    #expect(BackupUploadRules.status([uploaded,uploaded]) == .uploadConfirmed)
    #expect(BackupUploadRules.status([uploaded,UploadEvidence(ubiquitous:true,uploaded:false,uploading:false)]) == .pendingUpload)
    #expect(BackupUploadRules.status([uploaded,UploadEvidence(ubiquitous:nil,uploaded:nil,uploading:nil)]) == .unknown)
    #expect(BackupUploadRules.status([UploadEvidence(ubiquitous:false,uploaded:nil,uploading:nil)]) == .written)
    #expect(BackupUploadRules.status([]) == .unknown)
}

private final class BackupTestClock:AppClock,@unchecked Sendable {
    private let lock=NSLock();private var instant=Date(timeIntervalSince1970:1_790_000_000)
    var now:Date { lock.withLock { instant } }
    var timeZone:TimeZone { TimeZone(secondsFromGMT:0)! }
    func advance(_ seconds:TimeInterval) { lock.withLock { instant=instant.addingTimeInterval(seconds) } }
}

@Test func backupCoalescesEditsAndOnlyMarksItsActualSnapshotRevisionWritten() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),clock=BackupTestClock(),cache=root.appendingPathComponent("cache")
    let backup=DirectoryBackup(repository:store,cache:cache,clock:clock)
    try await backup.connect(chosen);await backup.run();clock.advance(5);await backup.run()
    #expect(try await store.snapshot().backup.lastPublishedRevision==nil)
    try await store.commit(id:UUID()) { $0.meals[0].tags=["latest before snapshot"] };await backup.run();clock.advance(6)
    await backup.run();let first=try await store.snapshot()
    #expect(first.backup.lastPublishedRevision==first.dataset.revision && !first.backup.dirty)
    try await store.commit(id:UUID()) { $0.meals[0].tags=["starts export"] }
    let racing=DirectoryBackup(repository:store,cache:cache,clock:clock,afterSnapshot:{
        try await store.commit(id:UUID()) { $0.meals[0].tags=["committed during export"] }
    })
    await racing.run(immediate:true);let after=try await store.snapshot()
    #expect(after.backup.dirty && after.backup.lastPublishedRevision==after.dataset.revision-1)
    #expect(after.backup.status == .dirty)
    await backup.run(immediate:true)
    #expect(try await !store.snapshot().backup.dirty)
}

@Test func directoryFailureKeepsLocalWritesAndLimitsAutomaticRetryUntilResume() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),clock=BackupTestClock(),backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),clock:clock)
    let before=try await store.snapshot()
    try await store.updateBackup(expectedBookmark:before.backup.directoryBookmark) { $0.directoryBookmark=Data("invalid-bookmark".utf8);$0.dirty=true }
    for _ in 0..<3 { await backup.run(immediate:true) }
    #expect(try await store.snapshot().backup.retryCount==3)
    try await store.commit(id:UUID()) { $0.meals[0].note="Local facts still save" }
    clock.advance(1000);await backup.run()
    #expect(try await store.snapshot().backup.retryCount==3)
    try await backup.resume();await backup.run();clock.advance(6);await backup.run()
    #expect(try await store.snapshot().backup.retryCount==1)
    #expect(try await store.snapshot().meals[0].note=="Local facts still save")
    let chosen=try destination(root);try await backup.connect(chosen);await backup.run(immediate:true)
    #expect(try await store.snapshot().backup.lastError==nil)
}

@Test func externalPointerEditDuringPublicationRemainsUntouched() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),cache=root.appendingPathComponent("cache")
    let backup=DirectoryBackup(repository:store,cache:cache);try await backup.connect(chosen);await backup.run(immediate:true)
    let before=try await store.snapshot(),folder=backupFolder(chosen,before),old=try pointer(folder),foreign=Data("external during export".utf8)
    try await store.commit(id:UUID()) { $0.meals[0].tags=["new"] }
    let concurrent=DirectoryBackup(repository:store,cache:cache,fault:{ point in
        if case .beforePointer=point { try foreign.write(to:folder.appendingPathComponent("latest.json")) }
    })
    await concurrent.run(immediate:true)
    #expect(try Data(contentsOf:folder.appendingPathComponent("latest.json"))==foreign)
    #expect(try await store.snapshot().backup.status == .failed)
    #expect(try PackageReader().read(folder.appendingPathComponent(old.package)).manifest.exportID==old.exportID)
}
