import Foundation
import BojiDomain
import BojiPersistence

/// Copies a coordinated, verified selection into private staging before any preview or database mutation.
public actor PackageStager {
    public init() {}
    public func stage(_ selected: URL, in parent: URL) async throws -> ValidatedPackage {
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        try await materialize(selected)
        let destination = parent.appendingPathComponent(UUID().uuidString + ".boji")
        var coordinationError: NSError?, result: Result<ValidatedPackage, Error>?
        NSFileCoordinator().coordinate(readingItemAt:selected,options:[],error:&coordinationError) { coordinated in
            result = Result {
                let checked = try PackageReader().read(coordinated)
                let capacity = try parent.deletingLastPathComponent().resourceValues(forKeys:[.volumeAvailableCapacityKey]).volumeAvailableCapacity
                let size = checked.manifest.files.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
                if let capacity, Int64(capacity) < size * 2 + 32 * 1024 * 1024 { throw CocoaError(.fileWriteOutOfSpace) }
                try FileManager.default.createDirectory(at:destination.appendingPathComponent("media"),withIntermediateDirectories:true)
                let source = PackageFiles(root:coordinated), files = LocalFileAccess()
                for entry in checked.manifest.files {
                    try Task.checkCancellation()
                    let data = try source.read(entry.path,maxBytes:entry.byteCount)
                    guard PackageHash.sha256(data) == entry.sha256 else { throw PackageError.incomplete(entry.path) }
                    try files.writeAtomically(data,to:destination.appendingPathComponent(entry.path))
                }
                try files.writeAtomically(PackageCodec.encode(checked.manifest),to:destination.appendingPathComponent("manifest.json"))
                return try PackageReader().read(destination)
            }
        }
        do {
            if let coordinationError { throw coordinationError }
            guard let result else { throw PackageError.incomplete("系统文件提供者没有返回资料") }
            return try result.get()
        } catch { try? FileManager.default.removeItem(at:destination);throw error }
    }
    private func materialize(_ selected: URL) async throws {
        let root = try selected.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey])
        guard root.isSymbolicLink != true, root.isDirectory == true else { throw PackageError.invalid("请选择资料包目录") }
        try await download([selected.appendingPathComponent("manifest.json")])
        let manifest = try PackageCodec.decode(PackageManifest.self,from:PackageFiles(root:selected).read("manifest.json",maxBytes:4 * 1024 * 1024))
        guard manifest.schemaVersion == 2, manifest.files.count <= PackageLimits.photos + 10 else { throw PackageError.invalid("清单版本或大小") }
        var urls:[URL] = [], total = 0, json = 0
        let required:Set<String> = ["records.json","profiles.json","goals.json","estimates.json","drafts.json","trash.json","README.md","agent-prompt.txt"]
        guard Set(manifest.files.map(\.path)).count == manifest.files.count else { throw PackageError.invalid("重复清单路径") }
        for entry in manifest.files {
            try PackageFiles.validatePath(entry.path)
            let limit = entry.path.hasPrefix("media/") ? PackageLimits.imageBytes : (entry.path.hasSuffix(".json") ? PackageLimits.jsonBytes : 1024 * 1024)
            guard required.contains(entry.path) || (entry.path.hasPrefix("media/") && entry.path.split(separator:"/").count == 2), entry.byteCount >= 0, entry.byteCount <= limit, entry.byteCount <= PackageLimits.totalBytes - total else { throw PackageError.limit("清单文件大小或路径") }
            total += entry.byteCount
            if entry.path.hasSuffix(".json") { guard entry.byteCount <= PackageLimits.jsonBytes - json else { throw PackageError.limit("128 MiB JSON") };json += entry.byteCount }
            var url = selected
            for part in entry.path.split(separator:"/") {
                url.appendPathComponent(String(part))
                guard try url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw PackageError.invalid("符号链接") }
            }
            urls.append(url)
        }
        try await download(urls)
    }
    private func download(_ urls:[URL]) async throws {
        let keys:Set<URLResourceKey> = [.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey,.isSymbolicLinkKey]
        var pending:[URL] = []
        for url in urls {
            let values = try url.resourceValues(forKeys:keys)
            guard values.isSymbolicLink != true else { throw PackageError.invalid("符号链接") }
            if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current && values.ubiquitousItemDownloadingStatus != .downloaded {
                try FileManager.default.startDownloadingUbiquitousItem(at:url);pending.append(url)
            }
        }
        for _ in 0..<120 {
            guard !pending.isEmpty else { return };try Task.checkCancellation()
            pending = try pending.filter { url in
                let value = try url.resourceValues(forKeys:keys)
                return value.ubiquitousItemDownloadingStatus != .current && value.ubiquitousItemDownloadingStatus != .downloaded
            }
            if !pending.isEmpty { try await Task.sleep(for:.milliseconds(500)) }
        }
        if !pending.isEmpty { throw PackageError.incomplete("等待系统下载，请在文件 App 中下载完整后重试") }
    }
}
