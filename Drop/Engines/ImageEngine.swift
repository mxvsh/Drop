import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, webp

    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .webp: .webP
        }
    }

    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    var label: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .webp: "WebP"
        }
    }

    var hint: String {
        switch self {
        case .png: "Lossless"
        case .jpeg: "Universal"
        case .heic: "Efficient"
        case .webp: "For the web"
        }
    }

    var isLossy: Bool { self != .png }
    var supportsAlpha: Bool { self != .jpeg }
    /// WebP is always writable: when ImageIO can't encode it, libwebp does.
    var canWrite: Bool { self == .webp || ImageEngine.writableTypes.contains(type.identifier) }

    static func of(_ file: DroppedFile) -> ImageFormat? {
        allCases.first { file.conforms(to: $0.type) }
    }
}

/// Multi-resolution icon files: one image per standard size, inside a single file.
nonisolated enum IconFormat: String, CaseIterable, Sendable {
    case icns, ico

    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
    var typeIdentifier: String { self == .icns ? "com.apple.icns" : "com.microsoft.ico" }
    var hint: String { self == .icns ? "macOS app icon" : "Windows icon and favicon" }
    /// ICNS is built from a full iconset; ImageIO writes at most 6 ICO images.
    var sizes: [Int] { self == .icns ? [16, 32, 64, 128, 256, 512, 1024] : [16, 32, 48, 64, 128, 256] }
    var canWrite: Bool { ImageEngine.writableTypes.contains(typeIdentifier) }
}

/// Image work on ImageIO. Every decode applies EXIF orientation, so output is upright
/// regardless of whether the target format keeps the orientation tag.
nonisolated enum ImageEngine {
    static let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    struct Decoded {
        let image: CGImage
        let properties: [CFString: Any]
    }

    // MARK: Actions

    @concurrent
    static func convert(_ files: [DroppedFile], to format: ImageFormat, options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try Batch.map(files, progress: progress) { file in
            let decoded = try decode(file.url)
            let dest = options.output.file(for: file.url, ext: format.fileExtension)
            try write(decoded.image, to: dest, format: format, quality: options.imageQuality, properties: decoded.properties)
            return dest
        }
    }

    @concurrent
    static func compress(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try Batch.map(files, progress: progress) { file in
            let format = ImageFormat.of(file).flatMap { $0.isLossy && $0.canWrite ? $0 : nil } ?? .jpeg
            let decoded = try decode(file.url)
            let dest = options.output.file(for: file.url, suffix: " (compressed)", ext: format.fileExtension)
            try write(decoded.image, to: dest, format: format, quality: options.imageQuality, properties: decoded.properties)
            return dest
        }
    }

    @concurrent
    static func resize(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try Batch.map(files, progress: progress) { file in
            let format = ImageFormat.of(file).flatMap { $0.canWrite ? $0 : nil } ?? .png
            let decoded = try decode(file.url)
            let size = targetSize(for: decoded.image, request: options.resize)
            let resized = try scaled(decoded.image, to: size)
            let suffix: String
            if case .scale(let factor) = options.resize {
                suffix = " (\(Int((factor * 100).rounded()))%)"
            } else {
                suffix = " (\(size.width)×\(size.height))"
            }
            let dest = options.output.file(for: file.url, suffix: suffix, ext: format.fileExtension)
            try write(resized, to: dest, format: format, quality: max(options.imageQuality, 0.9), properties: decoded.properties)
            return dest
        }
    }

    @concurrent
    static func makeIcon(_ files: [DroppedFile], format: IconFormat, options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var results: [URL] = []
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let square = try squared(decode(file.url).image)
            let dest = options.output.file(for: file.url, ext: format.fileExtension)
            switch format {
            case .icns: try await writeICNS(square, to: dest)
            case .ico: try writeICO(square, to: dest)
            }
            results.append(dest)
            progress(Double(index + 1) / Double(files.count))
        }
        return results
    }

    /// A full iconset, 1x and 2x, compiled by Apple's `iconutil` so Finder and the Dock pick the right size.
    private static func writeICNS(_ square: CGImage, to dest: URL) async throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("Drop-\(UUID().uuidString).iconset", isDirectory: true)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        for point in [16, 32, 128, 256, 512] {
            try write(scaled(square, to: (point, point)), to: iconset.appendingPathComponent("icon_\(point)x\(point).png"), format: .png, quality: 1, properties: nil)
            try write(scaled(square, to: (point * 2, point * 2)), to: iconset.appendingPathComponent("icon_\(point)x\(point)@2x.png"), format: .png, quality: 1, properties: nil)
        }
        try await FileEngine.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", dest.path])
    }

    private static func writeICO(_ square: CGImage, to dest: URL) throws {
        let sizes = IconFormat.ico.sizes
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, IconFormat.ico.typeIdentifier as CFString, sizes.count, nil) else {
            throw DropError.unsupported("ICO isn't supported on this Mac.")
        }
        for size in sizes {
            CGImageDestinationAddImage(destination, try scaled(square, to: (size, size)), nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: dest)
            throw DropError.failed("Couldn't write \(dest.lastPathComponent).")
        }
    }

    /// Centers the image on a transparent square so icons are never stretched.
    static func squared(_ image: CGImage) throws -> CGImage {
        let side = max(image.width, image.height)
        if image.width == image.height && image.hasAlpha { return image }
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw DropError.failed("Couldn't prepare the icon.") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (side - image.width) / 2, y: (side - image.height) / 2, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw DropError.failed("Couldn't prepare the icon.") }
        return result
    }

    static func targetSize(for image: CGImage, request: ResizeRequest) -> (width: Int, height: Int) {
        let width = Double(image.width)
        let height = Double(image.height)
        switch request {
        case .scale(let factor):
            return (max(1, Int((width * factor).rounded())), max(1, Int((height * factor).rounded())))
        case .fit(let maxWidth, let maxHeight):
            let factor = min(Double(maxWidth) / width, Double(maxHeight) / height)
            return (max(1, Int((width * factor).rounded())), max(1, Int((height * factor).rounded())))
        case .exact(let w, let h):
            return (max(1, w), max(1, h))
        }
    }

    /// High-quality redraw at a new pixel size, keeping the colour space and alpha.
    static func scaled(_ image: CGImage, to size: (width: Int, height: Int)) throws -> CGImage {
        if size.width == image.width && size.height == image.height { return image }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: (image.hasAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue
        ) else { throw DropError.failed("Couldn't resize the image.") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let result = context.makeImage() else { throw DropError.failed("Couldn't resize the image.") }
        return result
    }

    /// Upright pixel size without decoding, for prefilling the Resize form.
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }

    @concurrent
    static func stripMetadata(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try Batch.map(files, progress: progress) { file in
            let format = ImageFormat.of(file).flatMap { $0.canWrite ? $0 : nil } ?? .png
            let decoded = try decode(file.url)
            let dest = options.output.file(for: file.url, suffix: " (clean)", ext: format.fileExtension)
            try write(decoded.image, to: dest, format: format, quality: 0.95, properties: nil)
            return dest
        }
    }

    // MARK: Primitives

    static func decode(_ url: URL, maxPixel: Int? = nil) throws -> Decoded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw DropError.unreadable(url.lastPathComponent) }

        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)

        if longest > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? longest, longest),
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return Decoded(image: image, properties: properties)
            }
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DropError.unreadable(url.lastPathComponent)
        }
        return Decoded(image: image, properties: properties)
    }

    static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double, properties: [CFString: Any]?) throws {
        if format == .webp && !writableTypes.contains(format.type.identifier) {
            try WebPEncoder.write(image, to: url, quality: quality)
            return
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw DropError.unsupported("\(format.label) isn't supported on this Mac.")
        }
        var options = sanitized(properties ?? [:])
        if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
        let output = !format.supportsAlpha && image.hasAlpha ? flattened(image) : image
        CGImageDestinationAddImage(destination, output, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw DropError.failed("Couldn't write \(url.lastPathComponent).")
        }
    }

    /// Drops size and orientation keys: pixels are already upright and sized.
    private static func sanitized(_ properties: [CFString: Any]) -> [CFString: Any] {
        var result = properties
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation] {
            result.removeValue(forKey: key)
        }
        if var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        result[kCGImagePropertyOrientation] = 1
        return result
    }

    /// Composites onto white for formats without transparency.
    static func flattened(_ image: CGImage) -> CGImage {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }
}

nonisolated extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}

/// Runs a per-file step with cancellation checks and overall progress.
nonisolated enum Batch {
    static func map<T>(_ files: [DroppedFile], progress: (Double) -> Void, _ body: (DroppedFile) throws -> T) throws -> [T] {
        var results: [T] = []
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            results.append(try body(file))
            progress(Double(index + 1) / Double(files.count))
        }
        return results
    }
}
