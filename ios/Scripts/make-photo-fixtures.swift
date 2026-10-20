// Synthetic fixtures only. No user photos or remote files are read.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/boji-test-photos", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (index, format) in [UTType.jpeg, .png, .heic].enumerated() {
    let canvas = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 1280, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    canvas.setFillColor(CGColor(gray: CGFloat(index + 1) / 4, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
    canvas.setFillColor(CGColor(gray: 1, alpha: 1)); canvas.fill(CGRect(x: 20, y: 20, width: 40 * (index + 1), height: 40))
    let url = directory.appendingPathComponent("synthetic-\(index)." + format.preferredFilenameExtension!)
    guard let output = CGImageDestinationCreateWithURL(url as CFURL, format.identifier as CFString, 1, nil) else { fatalError("Encoder unavailable for \(format)") }
    CGImageDestinationAddImage(output, canvas.makeImage()!, [kCGImagePropertyOrientation: index == 2 ? 6 : 1] as CFDictionary)
    guard CGImageDestinationFinalize(output) else { fatalError("Fixture write failed") }
    print(url.path)
}
