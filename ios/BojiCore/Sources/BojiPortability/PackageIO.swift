import Foundation
import Darwin
import CryptoKit
import ImageIO
import BojiDomain
import BojiPersistence

public enum PackageError: Error, Equatable, Sendable, LocalizedError {
    case invalid(String), limit(String), incomplete(String), interrupted
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): "资料包无效：" + reason
        case .limit(let reason): "资料超出导入上限：" + reason
        case .incomplete(let path): "资料包缺失或校验不符：" + path
        case .interrupted: "操作中断，原资料仍保留。"
        }
    }
}
public enum PackageLimits {
    public static let totalBytes = 2 * 1024 * 1024 * 1024
    public static let jsonBytes = 128 * 1024 * 1024
    public static let records = 20_000
    public static let photos = 10_000
    public static let imageBytes = 50 * 1024 * 1024
    public static let pixels = 50_000_000
}
public enum PackageHash {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
/// Walk using O_NOFOLLOW for every component; a path swap cannot make us read outside the selected root.
struct PackageFiles {
    let root: URL
    static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 300, !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw PackageError.invalid("路径越界") }
    }
    func read(_ path: String, maxBytes: Int) throws -> Data {
        try Self.validatePath(path)
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PackageError.invalid("目录或符号链接") }
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() {
            let next = openat(descriptor, part, O_RDONLY | O_NOFOLLOW | (index == parts.count - 1 ? 0 : O_DIRECTORY))
            close(descriptor); descriptor = next
            guard descriptor >= 0 else { throw PackageError.incomplete(path) }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0,
              info.st_size <= maxBytes else { throw PackageError.limit(path) }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count == info.st_size, data.count <= maxBytes else { throw PackageError.incomplete(path) }
        return data
    }
    func inventory() throws -> Set<String> {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey,.fileSizeKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isSymbolicLink != true, rootValues.isDirectory == true else { throw PackageError.invalid("目录或符号链接") }
        var result: Set<String> = [], total = 0, jsonTotal = 0
        func visit(_ directory: URL, prefix: String) throws {
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            guard children.count <= PackageLimits.photos + 20 else { throw PackageError.limit("文件数") }
            for child in children {
                let path = prefix + child.lastPathComponent; try Self.validatePath(path)
                let values = try child.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true else { throw PackageError.invalid("不接受符号链接") }
                if values.isDirectory == true {
                    guard path == "media" else { throw PackageError.invalid("未知子目录") }
                    try visit(child, prefix: "media/")
                } else {
                    guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else { throw PackageError.invalid("不是普通文件") }
                    guard size <= PackageLimits.totalBytes - total else { throw PackageError.limit("2 GiB 总量") }
                    total += size
                    if path.hasSuffix(".json") {
                        guard size <= PackageLimits.jsonBytes - jsonTotal else { throw PackageError.limit("128 MiB JSON") }
                        jsonTotal += size
                    }
                    guard total <= PackageLimits.totalBytes, jsonTotal <= PackageLimits.jsonBytes else { throw PackageError.limit("2 GiB 总量或 128 MiB JSON") }
                    result.insert(path)
                }
            }
        }
        try visit(root, prefix: ""); return result
    }
}

public enum ExportPoint: Sendable { case afterJSON, afterPhoto, beforeManifest, beforePublish }
public struct PublishedPackage: Sendable {
    public let url: URL
    public let manifest: PackageManifest
    public let manifestSHA256: String
}
public actor PackageExporter {
    private let files: any FileAccess
    private let fault: @Sendable (ExportPoint) async throws -> Void
    public init(files: any FileAccess = LocalFileAccess(), fault: @escaping @Sendable (ExportPoint) async throws -> Void = { _ in }) { self.files = files; self.fault = fault }
    public func export(repository: LocalRepository, to parent: URL, at now: Date = Date()) async throws -> PublishedPackage {
        let lease = try await repository.acquireSnapshot()
        let id = UUID(), manager = FileManager.default
        let stage = parent.appendingPathComponent(".incomplete-" + id.uuidString)
        let final = parent.appendingPathComponent(id.uuidString + ".boji", isDirectory: true)
        do {
            let contents = try PackageContents(snapshot: lease.value)
            try manager.createDirectory(at: stage.appendingPathComponent("media"), withIntermediateDirectories: true)
            var entries: [PackageFile] = []
            func write(_ data: Data, _ path: String) throws {
                try files.writeAtomically(data, to: stage.appendingPathComponent(path))
                entries.append(PackageFile(path: path, byteCount: data.count, sha256: PackageHash.sha256(data)))
            }
            for (path, data) in try contents.dataFiles().sorted(by: { $0.key < $1.key }) { try write(data, path) }
            try await fault(.afterJSON)
            var paths: Set<String> = []
            for asset in contents.records.photos {
                guard paths.insert(asset.relativePath).inserted else { continue }
                let data = try await repository.readPhoto(asset)
                try write(data, asset.relativePath); try await fault(.afterPhoto)
            }
            var manifest = PackageManifest(datasetID: lease.value.dataset.id, exportID: id, createdAt: now, revision: lease.value.dataset.revision, counts: contents.counts, files: entries.sorted { $0.path < $1.path })
            manifest.schemaVersion = PackageVersion.current
            try await fault(.beforeManifest)
            let manifestData = try PackageCodec.encode(manifest)
            try files.writeAtomically(manifestData, to: stage.appendingPathComponent("manifest.json"))
            let checked = try PackageReader().read(stage)
            try await fault(.beforePublish)
            try manager.moveItem(at: stage, to: final)
            await repository.releaseSnapshot(lease.id)
            return PublishedPackage(url: final, manifest: checked.manifest, manifestSHA256: PackageHash.sha256(manifestData))
        } catch {
            try? manager.removeItem(at: stage)
            await repository.releaseSnapshot(lease.id)
            throw error
        }
    }
}

public struct ValidatedPackage: Sendable {
    public let url: URL
    public let manifest: PackageManifest
    public let contents: PackageContents
    public let snapshot: DatasetSnapshot
}
public struct PackageReader: Sendable {
    public init() {}
    public func read(_ root: URL) throws -> ValidatedPackage {
        let files = PackageFiles(root: root), inventory = try files.inventory()
        let manifest = try PackageCodec.decode(PackageManifest.self, from: files.read("manifest.json", maxBytes: 4 * 1024 * 1024))
        guard manifest.schemaVersion == PackageVersion.current else { throw DomainError.unsupportedSchema(manifest.schemaVersion) }
        guard manifest.revision >= 0, manifest.createdAt.timeIntervalSince1970.isFinite, manifest.files.count <= PackageLimits.photos + 10,
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              Set(manifest.files.map(\.path)).union(["manifest.json"]) == inventory else { throw PackageError.invalid("清单或文件数") }
        let required: Set<String> = ["records.json","profiles.json","goals.json","estimates.json","drafts.json","trash.json","README.md","agent-prompt.txt"]
        guard required.isSubset(of: inventory) else { throw PackageError.invalid("缺少必需文件") }
        var payloads: [String: Data] = [:]
        for entry in manifest.files {
            try PackageFiles.validatePath(entry.path)
            guard entry.byteCount >= 0, entry.sha256.count == 64, entry.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  required.contains(entry.path) || entry.path.hasPrefix("media/") else { throw PackageError.invalid("未知文件或摘要") }
            let limit = entry.path.hasPrefix("media/") ? PackageLimits.imageBytes : (entry.path.hasSuffix(".json") ? PackageLimits.jsonBytes : 1024 * 1024)
            guard entry.byteCount <= limit else { throw PackageError.limit(entry.path) }
            let data = try files.read(entry.path, maxBytes: limit)
            guard data.count == entry.byteCount, PackageHash.sha256(data) == entry.sha256 else { throw PackageError.incomplete(entry.path) }
            if entry.path.hasSuffix(".json") { payloads[entry.path] = data }
        }
        func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T { try PackageCodec.decode(type, from: payloads[path] ?? Data()) }
        var contents = try PackageContents(snapshot: DatasetSnapshot())
        contents.records = try decode(PackageRecords.self, "records.json")
        contents.profiles = try decode([ProfileVersion].self, "profiles.json")
        contents.goals = try decode([GoalStage].self, "goals.json")
        contents.estimates = try decode([EstimateRevision].self, "estimates.json")
        contents.drafts = try decode([PackageDraft].self, "drafts.json")
        contents.trash = try decode(PackageTrash.self, "trash.json")
        guard contents.counts == manifest.counts, contents.counts.values.allSatisfy({ $0 >= 0 }),
              contents.records.photos.count <= PackageLimits.photos,
              contents.counts.filter({ $0.key != "photos" }).values.reduce(0,+) <= PackageLimits.records else { throw PackageError.limit("实体数量或清单计数") }
        let snapshot = try contents.snapshot(manifest: manifest)
        try PackageValidation.validate(snapshot)
        guard contents.records.meals.allSatisfy({ $0.deletedAt == nil }), contents.records.workouts.allSatisfy({ $0.deletedAt == nil }),
              contents.trash.meals.allSatisfy({ $0.deletedAt != nil }), contents.trash.workouts.allSatisfy({ $0.deletedAt != nil }) else { throw PackageError.invalid("回收站归属") }
        let mediaPaths = Set(contents.records.photos.map(\.relativePath))
        guard Set(manifest.files.filter { $0.path.hasPrefix("media/") }.map(\.path)) == mediaPaths else { throw PackageError.invalid("照片关联") }
        for asset in contents.records.photos {
            _ = try MediaVault(root: root).url(for: asset)
            guard let entry = manifest.files.first(where: { $0.path == asset.relativePath }), entry.byteCount == asset.byteCount, entry.sha256 == asset.sha256 else { throw PackageError.incomplete(asset.relativePath) }
            let data = try files.read(asset.relativePath, maxBytes: PackageLimits.imageBytes)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= PackageLimits.pixels / height, width == asset.width, height == asset.height,
                  CGImageSourceGetType(source) as String? == (asset.mimeType == "image/png" ? "public.png" : "public.jpeg"),
                  CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately:true] as CFDictionary) != nil else { throw PackageError.invalid("照片无法完整解码") }
        }
        let calculated = try PackageContents(snapshot: snapshot).records.daySummaries
        guard calculated == contents.records.daySummaries else { throw PackageError.invalid("日汇总与事实不一致") }
        return ValidatedPackage(url: root, manifest: manifest, contents: contents, snapshot: snapshot)
    }
}
