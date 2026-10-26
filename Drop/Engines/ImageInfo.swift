import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One line of the info card: "Dimensions", "4032 × 3024 px".
nonisolated struct InfoRow: Hashable, Sendable {
    let label: String
    let value: String
}

nonisolated extension ImageEngine {
    /// Everything worth knowing about an image: size, format, colour, and the camera and location it carries.
    @concurrent
    static func info(_ file: DroppedFile) async throws -> [InfoRow] {
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw DropError.unreadable(file.url.lastPathComponent) }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        var rows: [InfoRow] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append(InfoRow(label: label, value: value)) }
        }

        add("Format", file.type?.localizedDescription ?? file.formatLabel)
        if let size = pixelSize(of: file.url) {
            let megapixels = Double(size.width * size.height) / 1_000_000
            add("Dimensions", "\(size.width) × \(size.height) px" + (megapixels >= 0.1 ? " · \(String(format: "%.1f", megapixels)) MP" : ""))
        }
        add("File size", ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))

        let frames = CGImageSourceGetCount(source)
        if frames > 1 { add("Frames", "\(frames)") }

        var color: [String] = []
        if let model = properties[kCGImagePropertyColorModel] as? String { color.append(model) }
        if let profile = properties[kCGImagePropertyProfileName] as? String { color.append(profile) }
        if let depth = properties[kCGImagePropertyDepth] as? Int { color.append("\(depth)-bit") }
        add("Color", color.joined(separator: " · "))
        if let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool { add("Transparency", hasAlpha ? "Yes" : "No") }
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi > 0 { add("Resolution", "\(Int(dpi.rounded())) dpi") }

        let dates = try? file.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        add("Created", dates?.creationDate.map(formatted))
        add("Modified", dates?.contentModificationDate.map(formatted))

        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        // Models usually repeat the make: "Apple" + "iPhone 15 Pro".
        if let model, let make, !model.lowercased().hasPrefix(make.lowercased()) {
            add("Camera", "\(make) \(model)")
        } else {
            add("Camera", model ?? make)
        }
        add("Lens", exif[kCGImagePropertyExifLensModel] as? String)
        add("Taken", (exif[kCGImagePropertyExifDateTimeOriginal] as? String).map(takenDate))
        add("Exposure", exposure(exif))
        add("Software", tiff[kCGImagePropertyTIFFSoftware] as? String)
        add("Location", location(gps))
        return rows
    }

    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// EXIF dates are "2024:03:09 14:21:07" with no time zone.
    private static func takenDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return parser.date(from: raw).map(formatted) ?? raw
    }

    /// "ISO 100 · ƒ/1.8 · 1/120 s · 26 mm"
    private static func exposure(_ exif: [CFString: Any]) -> String {
        var parts: [String] = []
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { parts.append("ISO \(iso)") }
        if let aperture = exif[kCGImagePropertyExifFNumber] as? Double { parts.append("ƒ/\(trimmed(aperture))") }
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            parts.append(time < 1 ? "1/\(Int((1 / time).rounded())) s" : "\(trimmed(time)) s")
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double { parts.append("\(trimmed(focal)) mm") }
        return parts.joined(separator: " · ")
    }

    private static func trimmed(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func location(_ gps: [CFString: Any]) -> String? {
        guard let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        let north = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let east = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        return String(format: "%.5f° %@, %.5f° %@", latitude, north, longitude, east)
    }
}
