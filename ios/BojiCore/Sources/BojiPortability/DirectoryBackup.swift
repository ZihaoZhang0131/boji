import Foundation
import BojiDomain
import BojiPersistence

public enum BackupPoint:Sendable,CaseIterable { case afterSnapshot,afterFile,beforePointer,afterPointer }
public enum DirectoryBackupError:Error,LocalizedError,Sendable {
    case conflict,authorization,unknownDirectory
    public var errorDescription:String? { switch self {
    case .conflict:"备份位置被外部修改或最新指针不完整。已保留所有版本，请核对目录，或选择新的空目录；恢复须使用导入预览。"
    case .authorization:"目录授权已失效，请重新选择目录。本机记录不受影响。"
    case .unknownDirectory:"该位置的薄记子目录含未识别内容，不会覆盖。请选择另一个目录。"
    } }
}
public struct BackupPointer:Codable,Equatable,Sendable {
    public let schemaVersion:Int
    public let datasetID:UUID
    public let exportID:UUID
    public let revision:Int64
    public let package:String
    public let manifestSHA256:String
    init(_ value:PublishedPackage) {
        schemaVersion=1;datasetID=value.manifest.datasetID;exportID=value.manifest.exportID;revision=value.manifest.revision
        package=exportID.uuidString+".boji";manifestSHA256=value.manifestSHA256
    }
}
public struct UploadEvidence:Sendable {
    public var ubiquitous:Bool?
    public var uploaded:Bool?
    public var uploading:Bool?
    public init(ubiquitous:Bool?,uploaded:Bool?,uploading:Bool?) { self.ubiquitous=ubiquitous;self.uploaded=uploaded;self.uploading=uploading }
}
public enum BackupUploadRules {
    public static func status(_ evidence:[UploadEvidence]) -> BackupStatus {
        guard !evidence.isEmpty else { return .unknown }
        if evidence.allSatisfy({$0.ubiquitous == false}) { return .written }
        guard evidence.allSatisfy({$0.ubiquitous == true}) else { return .unknown }
        if evidence.allSatisfy({$0.uploaded == true}) { return .uploadConfirmed }
        if evidence.contains(where:{$0.uploading == true || $0.uploaded == false}) { return .pendingUpload }
        return .unknown
    }
}
/// One-way, append-only publication. No directory file can automatically become local application data.
public actor DirectoryBackup {
    private let repository:LocalRepository
    private let cache:URL
    private let clock:any AppClock
    private let fault:@Sendable(BackupPoint)throws->Void
    private let afterSnapshot:@Sendable()async throws->Void
    private let uploadEvidence:@Sendable(URL)throws->UploadEvidence
    private var running=false
    private var observedRevision:Int64?
    private var observedAt:Date?
    private var lastProbe:Date?
    public init(repository:LocalRepository,cache:URL,clock:any AppClock=SystemClock(),afterSnapshot:@escaping @Sendable()async throws->Void={},fault:@escaping @Sendable(BackupPoint)throws->Void={_ in},uploadEvidence:@escaping @Sendable(URL)throws->UploadEvidence=DirectoryBackup.systemUploadEvidence) {
        self.repository=repository;self.cache=cache;self.clock=clock;self.afterSnapshot=afterSnapshot;self.fault=fault;self.uploadEvidence=uploadEvidence
    }
    public func connect(_ directory:URL) async throws {
        guard !running else { throw DomainError.conflict }
        let state=try await repository.snapshot();try ExportPolicy.requirePersonalDataset(state)
        let scoped=directory.startAccessingSecurityScopedResource();defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let bookmark=try directory.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)
        // A valid existing same-dataset backup is explicitly adopted only when the user chooses its directory.
        let existing=try coordinated(directory,write:true) { root -> (BackupPointer,String)? in
            let managed=try self.managedDirectory(root,datasetID:state.dataset.id)
            return try self.readPointer(managed,datasetID:state.dataset.id)
        }
        let label=directory.lastPathComponent
        try await repository.updateBackup(expectedBookmark:state.backup.directoryBookmark) { backup in
            backup=BackupState();backup.directoryBookmark=bookmark;backup.directoryLabel=label;backup.dirty=true;backup.status = .dirty
            backup.pointerSHA256=existing?.1
        }
        observedRevision=nil;lastProbe=nil
    }
    public func disconnect() async throws {
        guard !running else { throw DomainError.conflict }
        let state=try await repository.snapshot()
        try await repository.updateBackup(expectedBookmark:state.backup.directoryBookmark) { $0=BackupState();$0.dirty=true }
        observedRevision=nil;lastProbe=nil
    }
    public func resume() async throws {
        let state=try await repository.snapshot()
        guard state.backup.directoryBookmark != nil else { return }
        try await repository.updateBackup(expectedBookmark:state.backup.directoryBookmark) { $0.retryCount=0;$0.nextRetryAt=nil }
        observedRevision=nil
    }
    public func run(immediate:Bool=false) async {
        guard !running else { return };running=true;defer { running=false }
        var bookmark:Data?
        do {
            var state=try await repository.snapshot();try ExportPolicy.requirePersonalDataset(state)
            guard let token=state.backup.directoryBookmark else { return };bookmark=token
            if !immediate,let retry=state.backup.nextRetryAt,retry>clock.now { return }
            if !immediate,(state.backup.retryCount ?? 0)>=3 { return }
            if !immediate,state.backup.dirty {
                if observedRevision != state.dataset.revision { observedRevision=state.dataset.revision;observedAt=clock.now;return }
                if let observedAt,clock.now.timeIntervalSince(observedAt)<6 { return }
            }
            if !immediate,!state.backup.dirty,let lastProbe,clock.now.timeIntervalSince(lastProbe)<30 { return }
            let directory=try resolve(token),scoped=directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            let managed=try coordinated(directory,write:true) { try self.managedDirectory($0,datasetID:state.dataset.id) }
            let observed=try coordinated(managed,write:false) { try self.readPointer($0,datasetID:state.dataset.id) }
            if observed?.1 != state.backup.pointerSHA256 {
                guard let observed,observed.0.exportID==state.backup.activeExportID,observed.1==state.backup.activePointerSHA256 else { throw DirectoryBackupError.conflict }
                try await recordPublished(observed.0,digest:observed.1,bookmark:token)
                state=try await repository.snapshot()
            }
            if !state.backup.dirty {
                if immediate || lastProbe.map({clock.now.timeIntervalSince($0)>=30}) ?? true { try await probe(managed,bookmark:token);lastProbe=clock.now }
                return
            }
            try await repository.updateBackup(expectedBookmark:token) { $0.status = .writing;$0.lastError=nil }
            let published=try await PackageExporter().export(repository:repository,to:cache,at:clock.now)
            defer { try? FileManager.default.removeItem(at:published.url) }
            try await afterSnapshot();try fault(.afterSnapshot)
            let pointer=BackupPointer(published),bytes=try PackageCodec.encode(pointer),digest=PackageHash.sha256(bytes)
            try await repository.updateBackup(expectedBookmark:token) { $0.activeExportID=pointer.exportID;$0.activePointerSHA256=digest }
            let expected=state.backup.pointerSHA256
            try coordinated(managed,write:true) { folder in
                guard try self.pointerDigest(folder)==expected else { throw DirectoryBackupError.conflict }
                let partial=folder.appendingPathComponent(".incomplete-"+pointer.exportID.uuidString),final=folder.appendingPathComponent(pointer.package)
                guard !FileManager.default.fileExists(atPath:partial.path),!FileManager.default.fileExists(atPath:final.path) else { throw DirectoryBackupError.conflict }
                try FileManager.default.createDirectory(at:partial.appendingPathComponent("media"),withIntermediateDirectories:true)
                defer { try? FileManager.default.removeItem(at:partial) }
                let source=PackageFiles(root:published.url),writer=LocalFileAccess()
                for file in published.manifest.files {
                    try Task.checkCancellation()
                    try writer.writeAtomically(source.read(file.path,maxBytes:file.byteCount),to:partial.appendingPathComponent(file.path));try self.fault(.afterFile)
                }
                try writer.writeAtomically(source.read("manifest.json",maxBytes:4*1024*1024),to:partial.appendingPathComponent("manifest.json"))
                _ = try PackageReader().read(partial)
                try FileManager.default.moveItem(at:partial,to:final)
                try self.fault(.beforePointer)
                guard try self.pointerDigest(folder)==expected else { throw DirectoryBackupError.conflict }
                try writer.writeAtomically(bytes,to:folder.appendingPathComponent("latest.json"));try self.fault(.afterPointer)
            }
            try await recordPublished(pointer,digest:digest,bookmark:token)
            try await probe(managed,bookmark:token);lastProbe=clock.now
        } catch {
            guard let bookmark else { return }
            let now=clock.now,message=error.localizedDescription
            try? await repository.updateBackup(expectedBookmark:bookmark) {
                $0.dirty=true;$0.status = .failed;$0.lastError=message
                let count=min(($0.retryCount ?? 0)+1,3);$0.retryCount=count;$0.nextRetryAt=now.addingTimeInterval([15.0,60.0,300.0][count-1])
            }
        }
    }
    private func recordPublished(_ pointer:BackupPointer,digest:String,bookmark:Data) async throws {
        try await repository.recordBackupPublication(pointerRevision:pointer.revision,digest:digest,at:clock.now,expectedBookmark:bookmark)
    }
    private func probe(_ folder:URL,bookmark:Data) async throws {
        let current=try await repository.snapshot()
        let status=try coordinated(folder,write:false) { location -> BackupStatus in
            guard let pointer=try self.readPointer(location,datasetID:current.dataset.id),pointer.1==current.backup.pointerSHA256 else { throw DirectoryBackupError.conflict }
            let root=location.appendingPathComponent(pointer.0.package),package=try PackageReader().read(root)
            let urls=[location.appendingPathComponent("latest.json"),root.appendingPathComponent("manifest.json")]+package.manifest.files.map{root.appendingPathComponent($0.path)}
            return BackupUploadRules.status(urls.map { (try? self.uploadEvidence($0)) ?? UploadEvidence(ubiquitous:nil,uploaded:nil,uploading:nil) })
        }
        try await repository.updateBackup(expectedBookmark:bookmark) { if !$0.dirty { $0.status=status } }
    }
    public static func systemUploadEvidence(_ url:URL) throws -> UploadEvidence {
        let value=try url.resourceValues(forKeys:[.isUbiquitousItemKey,.ubiquitousItemIsUploadedKey,.ubiquitousItemIsUploadingKey])
        return UploadEvidence(ubiquitous:value.isUbiquitousItem,uploaded:value.ubiquitousItemIsUploaded,uploading:value.ubiquitousItemIsUploading)
    }
    private func resolve(_ bookmark:Data) throws -> URL {
        var stale=false
        let url=try URL(resolvingBookmarkData:bookmark,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale)
        guard !stale else { throw DirectoryBackupError.authorization };return url
    }
    private struct Owner:Codable,Equatable { let app:String;let datasetID:UUID }
    private func managedDirectory(_ root:URL,datasetID:UUID) throws -> URL {
        func directory(_ url:URL) throws {
            if !FileManager.default.fileExists(atPath:url.path) { try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false) }
            let values=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory==true,values.isSymbolicLink != true else { throw DirectoryBackupError.unknownDirectory }
        }
        let values=try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory==true,values.isSymbolicLink != true else { throw DirectoryBackupError.authorization }
        let container=root.appendingPathComponent("Boji"),managed=container.appendingPathComponent(datasetID.uuidString)
        try directory(container);try directory(managed)
        let owner=Owner(app:"boji-directory-backup-v1",datasetID:datasetID),file=managed.appendingPathComponent("owner.json")
        if FileManager.default.fileExists(atPath:file.path) {
            guard try PackageCodec.decode(Owner.self,from:PackageFiles(root:managed).read("owner.json",maxBytes:4096))==owner else { throw DirectoryBackupError.unknownDirectory }
        } else {
            guard try FileManager.default.contentsOfDirectory(atPath:managed.path).isEmpty else { throw DirectoryBackupError.unknownDirectory }
            try LocalFileAccess().writeAtomically(PackageCodec.encode(owner),to:file)
        }
        return managed
    }
    private func pointerDigest(_ folder:URL) throws -> String? {
        guard try FileManager.default.contentsOfDirectory(atPath:folder.path).contains("latest.json") else { return nil }
        return PackageHash.sha256(try PackageFiles(root:folder).read("latest.json",maxBytes:16*1024))
    }
    private func readPointer(_ folder:URL,datasetID:UUID) throws -> (BackupPointer,String)? {
        guard let digest=try pointerDigest(folder) else { return nil }
        let pointer=try PackageCodec.decode(BackupPointer.self,from:PackageFiles(root:folder).read("latest.json",maxBytes:16*1024))
        guard pointer.schemaVersion==1,pointer.datasetID==datasetID,pointer.revision>=0,pointer.package==pointer.exportID.uuidString+".boji" else { throw DirectoryBackupError.conflict }
        let root=folder.appendingPathComponent(pointer.package),package=try PackageReader().read(root)
        let manifest=try PackageFiles(root:root).read("manifest.json",maxBytes:4*1024*1024)
        guard PackageHash.sha256(manifest)==pointer.manifestSHA256,package.manifest.exportID==pointer.exportID,package.manifest.datasetID==datasetID,package.manifest.revision==pointer.revision else { throw DirectoryBackupError.conflict }
        return (pointer,digest)
    }
    private func coordinated<T>(_ url:URL,write:Bool,operation:(URL)throws->T) throws -> T {
        var error:NSError?,result:Result<T,Error>?
        let coordinator=NSFileCoordinator()
        if write { coordinator.coordinate(writingItemAt:url,options:[],error:&error) { location in result=Result { try operation(location) } } }
        else { coordinator.coordinate(readingItemAt:url,options:[],error:&error) { location in result=Result { try operation(location) } } }
        if let error { throw error };guard let result else { throw DirectoryBackupError.authorization };return try result.get()
    }
}
