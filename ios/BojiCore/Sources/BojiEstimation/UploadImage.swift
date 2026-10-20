import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum UploadImage {
    public static func jpeg(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1 else { throw ServiceFailure("invalid_input") }
        for side in [2048, 1536, 1024, 768] {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: side]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ServiceFailure("invalid_input") }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw ServiceFailure("invalid_input") }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            if CGImageDestinationFinalize(destination), output.length <= 2 * 1024 * 1024 { return output as Data }
        }
        throw ServiceFailure("image_too_large")
    }
}
