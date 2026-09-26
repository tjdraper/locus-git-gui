import CoreGraphics
import Foundation
import ImageIO

/// One side of an image file's change, decoded only as large as it's shown, so a huge image costs
/// no more memory than a small one.
nonisolated struct DiffImage: Sendable {
    /// Past this, an image isn't read at all.
    static let byteLimit = 64 * 1024 * 1024
    private static let thumbnailPixels = 1600

    let image: CGImage?
    /// Nil when the image couldn't be read.
    let pixelSize: CGSize?
    let byteCount: Int

    /// Away from the main actor. No data means it was too large to read.
    @concurrent
    static func decode(_ data: Data?, byteCount: Int) async -> DiffImage {
        guard let data, byteCount <= byteLimit, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return DiffImage(image: nil, pixelSize: nil, byteCount: byteCount)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return DiffImage(image: image, pixelSize: CGSize(width: width, height: height), byteCount: byteCount)
    }
}
