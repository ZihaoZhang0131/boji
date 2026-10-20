import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import BojiDomain

public enum MediaPoint: Equatable, Sendable { case afterStaging, afterPublishing }

public struct MediaVault: Sendable {
    public let root: URL
    private let files: any FileAccess
    private let fault: @Sendable (MediaPoint) throws -> Void
    public init(root: URL, files: any FileAccess = LocalFileAccess(), fault: @escaping @Sendable (MediaPoint) throws -> Void = { _ in }) {
        self.root = root; self.files = files; self.fault = fault
    }

    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    public func ingest(_ input: Data) throws -> PhotoAsset {
        guard !input.isEmpty, input.count <= 50 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(input as CFData, nil),
              let sourceType = CGImageSourceGetType(source) as String?,
              ["public.jpeg", "public.png", "public.heic", "public.heif"].contains(sourceType),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 50_000_000 / height else { throw DomainError.invalidValue("照片格式、尺寸或大小不支持") }
        // Decoding into a fresh image and writing only our properties strips EXIF/GPS.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw DomainError.invalidValue("照片无法解码") }
        let isPNG = sourceType == "public.png"
        let content = try encode(image, type: isPNG ? UTType.png.identifier : UTType.jpeg.identifier)
        let hash = Self.sha256(content)
        let ext = isPNG ? "png" : "jpg"
        let asset = PhotoAsset(sha256: hash, relativePath: "media/\(hash).\(ext)", mimeType: isPNG ? "image/png" : "image/jpeg", byteCount: content.count, width: image.width, height: image.height)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let media = root.appendingPathComponent("media", isDirectory: true)
        let thumbnails = root.appendingPathComponent("thumbnails", isDirectory: true)
        for directory in [staging, media, thumbnails] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let temporary = staging.appendingPathComponent(UUID().uuidString)
        try files.writeAtomically(content, to: temporary)
        try fault(.afterStaging)
        let destination = try url(for: asset)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard Self.sha256(try files.read(destination)) == hash else { throw DomainError.corruptStore }
            try FileManager.default.removeItem(at: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        try fault(.afterPublishing)
        try createThumbnail(from: content, hash: hash)
        return asset
    }

    private func encode(_ image: CGImage, type: String) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { throw DomainError.invalidValue("照片编码失败") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DomainError.invalidValue("照片编码失败") }
        return data as Data
    }

    private func createThumbnail(from data: Data, hash: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("thumbnails"), withIntermediateDirectories: true)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) else { throw DomainError.invalidValue("缩略图生成失败") }
        try files.writeAtomically(try encode(image, type: UTType.jpeg.identifier), to: root.appendingPathComponent("thumbnails/\(hash).jpg"))
    }

    public func url(for asset: PhotoAsset) throws -> URL {
        let expected = asset.mimeType == "image/png" ? "png" : "jpg"
        guard asset.sha256.count == 64, asset.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              ["image/jpeg", "image/png"].contains(asset.mimeType),
              asset.relativePath == "media/\(asset.sha256).\(expected)" else { throw DomainError.invalidValue("照片路径无效") }
        let url = root.appendingPathComponent(asset.relativePath)
        guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw DomainError.invalidValue("照片路径越界") }
        return url
    }

    public func read(_ asset: PhotoAsset) throws -> Data {
        let location = try url(for: asset)
        guard FileManager.default.fileExists(atPath: location.path) else { throw DomainError.missingPhoto(asset.id) }
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == asset.byteCount, asset.byteCount <= 50 * 1024 * 1024 else { throw DomainError.invalidValue("照片大小校验失败") }
        let data = try files.read(location)
        guard Self.sha256(data) == asset.sha256 else { throw DomainError.invalidValue("照片校验失败") }
        return data
    }

    public func thumbnail(_ asset: PhotoAsset) throws -> Data {
        _ = try url(for: asset)
        let location = root.appendingPathComponent("thumbnails/\(asset.sha256).jpg")
        if let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 10 * 1024 * 1024,
           let data = try? files.read(location), CGImageSourceCreateWithData(data as CFData, nil) != nil { return data }
        try createThumbnail(from: read(asset), hash: asset.sha256)
        return try files.read(location)
    }

    public func collectOrphans(keeping paths: Set<String>) throws {
        let manager = FileManager.default
        for folder in ["media", "thumbnails", "staging"] {
            let directory = root.appendingPathComponent(folder)
            guard manager.fileExists(atPath: directory.path) else { continue }
            let keep = folder == "thumbnails" ? Set(paths.map { "thumbnails/" + URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent + ".jpg" }) : paths
            for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                guard !keep.contains(folder + "/" + file.lastPathComponent) else { continue }
                try manager.removeItem(at: file)
            }
        }
    }
}
