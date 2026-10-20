import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
import BojiDomain
import BojiPersistence

func imageFixture(orientation: Int = 1, type: UTType = .jpeg) throws -> Data {
    let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.5, green: 0.8, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation, kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.34, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test(arguments: [UTType.jpeg, .png, .heic])
func supportedPhotoFormatsNormalizeToIndependentReadableFiles(type: UTType) throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let vault = MediaVault(root: root)
    let photo = try vault.ingest(imageFixture(orientation: 6, type: type))
    #expect(photo.width == 10 && photo.height == 20)
    #expect(photo.mimeType == (type == .png ? "image/png" : "image/jpeg"))
    #expect(CGImageSourceCreateWithData(try vault.read(photo) as CFData, nil) != nil)
}

private struct RefuseWrites: FileAccess {
    func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    func writeAtomically(_ data: Data, to url: URL) throws { throw CocoaError(.fileWriteOutOfSpace) }
}

@Test func failureBeforePhotoWriteDoesNotPublishAFile() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = MediaVault(root: root, files: RefuseWrites())
    #expect(throws: CocoaError.self) { try vault.ingest(imageFixture()) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("media").path).isEmpty)
}

@Test func normalizesDirectionStripsGPSAndKeepsIndependentCopy() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original.jpg")
    try imageFixture(orientation: 6).write(to: original)
    let vault = MediaVault(root: root)
    let asset = try vault.ingest(Data(contentsOf: original))
    try FileManager.default.removeItem(at: original)
    let data = try vault.read(asset)
    #expect(asset.width == 10 && asset.height == 20)
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("thumbnails/\(asset.sha256).jpg").path))
    #expect(throws: DomainError.self) { try vault.ingest(Data("not an image".utf8)) }
}

@Test(arguments: [MediaPoint.afterStaging, .afterPublishing])
func interruptedPhotoWritesAreOrphansUntilCommitted(point: MediaPoint) throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = MediaVault(root: root, fault: { at in
        if at == point { throw CocoaError(.fileWriteOutOfSpace) }
    })
    #expect(throws: CocoaError.self) { try vault.ingest(imageFixture()) }
    try MediaVault(root: root).collectOrphans(keeping: [])
    for folder in ["media", "staging"] {
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path).isEmpty)
    }
}

@Test func missingImageCannotBecomeCommittedReferenceAndRestartCollectsOrphans() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try await LocalRepository.open(at: root)
    let photo = try await store.preparePhoto(imageFixture())
    try FileManager.default.removeItem(at: root.appendingPathComponent(photo.relativePath))
    var meal = Meal(time: RecordTime(clock: FixedClock("2026-10-17T12:00:00Z"))); meal.photoIDs = [photo.id]
    let value = meal
    await #expect(throws: DomainError.missingPhoto(photo.id)) { try await store.commit(id: UUID()) { $0.photos = [photo]; $0.meals = [value] } }
    #expect(try await store.snapshot().meals.isEmpty)
    let orphan = try await store.preparePhoto(imageFixture())
    let reopened = try await LocalRepository.open(at: root)
    #expect(try await reopened.snapshot().meals.isEmpty)
    await #expect(throws: DomainError.missingPhoto(orphan.id)) { try await reopened.readPhoto(orphan) }
}

@Test func photoCommitFailureAndSnapshotLeaseProtectFiles() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fault = FailOnce()
    let store = try await LocalRepository.open(at: root, fault: { try fault.check($0) })
    let photo = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: FixedClock("2026-10-17T12:00:00Z"))); meal.photoIDs = [photo.id]
    let value = meal, operation = UUID()
    await #expect(throws: CocoaError.self) { try await store.commit(id: operation) { $0.photos = [photo]; $0.meals = [value] } }
    #expect(try await store.snapshot().meals.isEmpty)
    try await store.collectOrphanPhotos()
    #expect(try await store.readPhoto(photo).count == photo.byteCount)
    try await store.commit(id: operation) { $0.photos = [photo]; $0.meals = [value] }
    let lease = try await store.acquireSnapshot()
    try await store.commit(id: UUID()) { $0.meals.removeAll(); $0.photos.removeAll() }
    try await store.collectOrphanPhotos()
    #expect(lease.value.meals == [value])
    #expect(try await store.readPhoto(photo).count == photo.byteCount)
    await store.releaseSnapshot(lease.id)
    try await store.collectOrphanPhotos()
    await #expect(throws: DomainError.missingPhoto(photo.id)) { try await store.readPhoto(photo) }
}
