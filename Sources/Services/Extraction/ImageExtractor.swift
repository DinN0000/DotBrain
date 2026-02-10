import Foundation
import ImageIO

/// Extracts EXIF metadata from image files
enum ImageExtractor {
    static func extract(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let sizeKB = Double(fileSize) / 1024.0

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return ExtractResult(
                success: true,
                file: ExtractResult.FileInfo(name: fileName, format: ext, sizeKB: round(sizeKB * 10) / 10),
                metadata: ["type": "image"],
                text: nil,
                error: nil
            )
        }

        var metadata: [String: Any] = ["type": "image"]

        // Get image properties
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            if let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
               let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
                metadata["dimensions"] = "\(width)x\(height)"
            }

            if let dpi = properties[kCGImagePropertyDPIWidth as String] as? Int {
                metadata["dpi"] = dpi
            }

            // EXIF data
            if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                    metadata["date_taken"] = dateTime
                }
                if let camera = exif[kCGImagePropertyExifLensMake as String] as? String {
                    metadata["camera"] = camera
                }
            }

            // GPS data
            if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
                   let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
                    metadata["gps"] = "\(lat), \(lon)"
                }
            }
        }

        return ExtractResult(
            success: true,
            file: ExtractResult.FileInfo(name: fileName, format: ext, sizeKB: round(sizeKB * 10) / 10),
            metadata: metadata,
            text: nil,
            error: nil
        )
    }
}
