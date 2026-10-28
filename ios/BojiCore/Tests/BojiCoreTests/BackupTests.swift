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
    try await store.updateBackup(expectedBookmark:before.backup.directoryBookmark) { $0.directoryBookmark=Data("invalid-bookmark".utf8);$0.automaticEnabled=true;$0.dirty=true }
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

@Test func legacyAuthorizationNeedsOptInAndStopPersistsWithoutErasingBackups() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let location=root.appendingPathComponent("store"),store=try await portableFixture(at:location)
    let clock=BackupTestClock(),chosen=try destination(root),cache=root.appendingPathComponent("cache")
    let backup=DirectoryBackup(repository:store,cache:cache,clock:clock)
    try await backup.connect(chosen)
    let configured=try await store.snapshot()
    var json=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(configured.backup)) as? [String:Any])
    json.removeValue(forKey:"automaticEnabled");json.removeValue(forKey:"lastUploadStatus")
    let legacy=try JSONDecoder().decode(BackupState.self,from:JSONSerialization.data(withJSONObject:json))
    #expect(legacy.automaticEnabled==nil)
    try await store.updateBackup(expectedBookmark:configured.backup.directoryBookmark) { $0=legacy }
    await backup.run();clock.advance(60);await backup.run()
    #expect(try await store.snapshot().backup.lastWrittenAt==nil)
    try await backup.setAutomaticEnabled(true);await backup.run(immediate:true)
    let first=try await store.snapshot(),folder=backupFolder(chosen,first),published=try pointer(folder)
    try await backup.setAutomaticEnabled(false)
    try await store.commit(id:UUID()) { $0.meals[0].note="changed while stopped" }
    clock.advance(60);await backup.run();clock.advance(60);await backup.run()
    #expect(try pointer(folder)==published)
    let reopened=try await LocalRepository.open(at:location),stopped=try await reopened.snapshot()
    #expect(stopped.backup.automaticEnabled==false && stopped.backup.lastWrittenAt==first.backup.lastWrittenAt)
    #expect(stopped.backup.directoryBookmark==first.backup.directoryBookmark)
    let restarted=DirectoryBackup(repository:reopened,cache:cache,clock:clock)
    await restarted.run(immediate:true)
    let manual=try await reopened.snapshot()
    #expect(manual.backup.automaticEnabled==false && !manual.backup.dirty)
    #expect(manual.backup.lastWrittenAt != first.backup.lastWrittenAt)
    let package=try PackageReader().read(folder.appendingPathComponent(try pointer(folder).package))
    #expect(package.snapshot.backup.directoryBookmark==nil && package.snapshot.backup.automaticEnabled==nil)
    #expect(FileManager.default.fileExists(atPath:folder.appendingPathComponent(published.package).path))
    try await restarted.setAutomaticEnabled(true)
    let enabled=try await LocalRepository.open(at:location).snapshot()
    #expect(enabled.backup.automaticEnabled==true)
    #expect(enabled.dataset.revision==manual.dataset.revision)
}

private actor BackupGate {
    var started=false, released=false
    var starters:[CheckedContinuation<Void,Never>]=[]
    var waiters:[CheckedContinuation<Void,Never>]=[]
    func pause() async {
        started=true;for waiter in starters { waiter.resume() };starters=[]
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { starters.append($0) } } }
    func open() { released=true;for waiter in waiters { waiter.resume() };waiters=[] }
}

@Test func stoppingDuringPublicationFinishesSnapshotAndSerializesManualRequest() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),gate=BackupGate()
    let backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),afterSnapshot:{ await gate.pause() })
    try await backup.connect(chosen)
    let first=Task { await backup.run(immediate:true) }
    await gate.waitUntilStarted()
    try await backup.setAutomaticEnabled(false)
    let second=Task { await backup.run(immediate:true) }
    await backup.run()
    await gate.open();await first.value;await second.value
    let state=try await store.snapshot(),folder=backupFolder(chosen,state)
    #expect(state.backup.automaticEnabled==false && !state.backup.dirty && state.backup.lastError==nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath:folder.path).filter{$0.hasSuffix(".boji")}.count==1)
}

@Test func lifecycleCancellationKeepsPendingWithoutSpendingRetryAndSuspensionDrainsPublication() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),gate=BackupGate()
    let backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),afterSnapshot:{ await gate.pause() })
    try await backup.connect(chosen)
    let running=Task { await backup.run(immediate:true) };await gate.waitUntilStarted()
    running.cancel();await gate.open();await running.value
    let cancelled=try await store.snapshot()
    #expect(cancelled.backup.dirty && cancelled.backup.status == .dirty)
    #expect(cancelled.backup.lastError==nil && (cancelled.backup.retryCount ?? 0)==0 && cancelled.backup.lastWrittenAt==nil)
    await backup.run(immediate:true)
    #expect(try await !store.snapshot().backup.dirty)
    let nextGate=BackupGate()
    try await store.commit(id:UUID()) { $0.meals[0].note="before switch" }
    let next=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),afterSnapshot:{ await nextGate.pause() })
    let publishing=Task { await next.run(immediate:true) };await nextGate.waitUntilStarted()
    let suspended=Task { await next.suspendAndWait() }
    await nextGate.open();await publishing.value;await suspended.value
    let written=try await store.snapshot()
    try await store.commit(id:UUID()) { $0.meals[0].note="after suspend" }
    await next.run(immediate:true)
    #expect(try await store.snapshot().backup.lastPublishedRevision==written.dataset.revision)
    await next.unsuspend();await next.run(immediate:true)
    #expect(try await !store.snapshot().backup.dirty)
}

private final class EvidenceLog:@unchecked Sendable {
    private let lock=NSLock()
    private var paths:Set<String>=[]
    private var calls=0
    func evidence(_ url:URL) -> UploadEvidence {
        lock.withLock { paths.insert(url.lastPathComponent);calls += 1 }
        return .init(ubiquitous:true,uploaded:url.lastPathComponent != "manifest.json",uploading:false)
    }
    var count:Int { lock.withLock { calls } }
    var names:Set<String> { lock.withLock { paths } }
}
@Test func probesIncludeEveryRequiredFileAndThrottleEvenManualChecksWithoutChangingWriteTime() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),clock=BackupTestClock(),log=EvidenceLog()
    let backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),clock:clock,uploadEvidence:{ log.evidence($0) })
    try await backup.connect(chosen);await backup.run(immediate:true)
    let state=try await store.snapshot(),folder=backupFolder(chosen,state),latest=try pointer(folder)
    let package=try PackageReader().read(folder.appendingPathComponent(latest.package))
    #expect(log.count==package.manifest.files.count+2)
    #expect(log.names.contains("latest.json") && log.names.contains("manifest.json"))
    #expect(state.backup.lastUploadStatus == .pendingUpload)
    let initialCount=log.count
    clock.advance(29);await backup.run(immediate:true)
    #expect(log.count==initialCount)
    clock.advance(1);await backup.run(immediate:true)
    #expect(log.count==initialCount*2)
    #expect(try await store.snapshot().backup.lastWrittenAt==state.backup.lastWrittenAt)
    #expect(try pointer(folder)==latest)
    try await backup.setAutomaticEnabled(false)
    try await store.commit(id:UUID()) { $0.meals[0].note="not backed up" }
    clock.advance(30);await backup.run()
    #expect(try pointer(folder)==latest && log.count==initialCount*3)
    #expect(try await store.snapshot().backup.lastUploadStatus == .pendingUpload)
}

@Test func automaticFailuresRespectBackoffLimitAndManualBypassesCooldownWithoutLosingLastSuccess() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),clock=BackupTestClock(),cache=root.appendingPathComponent("cache")
    let initial=DirectoryBackup(repository:store,cache:cache,clock:clock)
    try await initial.connect(chosen);await initial.run(immediate:true)
    let successful=try await store.snapshot()
    try await store.commit(id:UUID()) { $0.meals[0].note="pending during disk failure" }
    let failing=DirectoryBackup(repository:store,cache:cache,clock:clock,fault:{ if case .afterSnapshot=$0 { throw CocoaError(.fileWriteOutOfSpace) } })
    await failing.run();clock.advance(6);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==1)
    clock.advance(14);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==1)
    clock.advance(1);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==2)
    clock.advance(59);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==2)
    clock.advance(1);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==3)
    clock.advance(1000);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==3)
    #expect(try await store.snapshot().backup.lastWrittenAt==successful.backup.lastWrittenAt)
    try await failing.resume();await failing.run();clock.advance(6);await failing.run()
    #expect(try await store.snapshot().backup.retryCount==1)
    await initial.run(immediate:true)
    let recovered=try await store.snapshot()
    #expect(!recovered.backup.dirty && recovered.backup.retryCount==0 && recovered.backup.lastError==nil)
    #expect(recovered.backup.lastWrittenAt != successful.backup.lastWrittenAt)
}

@Test func stoppedStatusCheckNeverRecreatesRemovedDirectory() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),clock=BackupTestClock()
    let backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),clock:clock)
    try await backup.connect(chosen);await backup.run(immediate:true)
    let written=try await store.snapshot(),folder=backupFolder(chosen,written)
    try await backup.setAutomaticEnabled(false)
    try FileManager.default.removeItem(at:folder)
    clock.advance(30);await backup.run()
    #expect(!FileManager.default.fileExists(atPath:folder.path))
    #expect(try await store.snapshot().backup.automaticEnabled==false)
    #expect(try await store.snapshot().backup.lastWrittenAt==written.backup.lastWrittenAt)
}

@Test func directorySelectionWaitsForPublicationAndLaterStopWinsBeforeFirstBackup() async throws {
    let root=try temporaryDirectory();defer { try? FileManager.default.removeItem(at:root) }
    let store=try await portableFixture(at:root.appendingPathComponent("store")),chosen=try destination(root),replacement=try destination(root,"replacement"),gate=BackupGate()
    let backup=DirectoryBackup(repository:store,cache:root.appendingPathComponent("cache"),afterSnapshot:{ await gate.pause() })
    try await backup.connect(chosen)
    let publishing=Task { await backup.run(immediate:true) };await gate.waitUntilStarted()
    let selecting=Task { try await backup.connect(replacement) }
    // Keep publication in flight while the system picker returns a new selection.
    try await Task.sleep(for:.milliseconds(50))
    try await backup.setAutomaticEnabled(false)
    await gate.open();await publishing.value;try await selecting.value
    let selected=try await store.snapshot()
    #expect(selected.backup.directoryLabel=="replacement" && selected.backup.automaticEnabled==false)
    await backup.run(immediate:true,automaticOnly:true)
    #expect(try await store.snapshot().backup.lastWrittenAt==nil)
    await backup.run(immediate:true)
    #expect(try await store.snapshot().backup.automaticEnabled==false)
    #expect(try await store.snapshot().backup.lastWrittenAt != nil)
}
