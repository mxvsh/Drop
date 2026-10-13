import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum MediaEngine {
    /// GIFs are capped at this length so a long recording doesn't produce a huge file.
    static let maxGIFSeconds: Double = 60

    @concurrent
    static func compressVideo(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let preset = switch options.videoResolution {
        case .p720: AVAssetExportPreset1280x720
        case .p1080: AVAssetExportPresetHEVC1920x1080
        case .p2160: AVAssetExportPresetHEVC3840x2160
        }
        return try await eachFile(files, progress: progress) { file, report in
            let dest = options.output.file(for: file.url, suffix: " (compressed)", ext: "mp4")
            try await export(file.url, preset: preset, as: .mp4, to: dest, progress: report)
            return dest
        }
    }

    @concurrent
    static func convertToMP4(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try await eachFile(files, progress: progress) { file, report in
            let dest = options.output.file(for: file.url, ext: "mp4")
            try await export(file.url, preset: AVAssetExportPresetHighestQuality, as: .mp4, to: dest, progress: report)
            return dest
        }
    }

    @concurrent
    static func convertToM4A(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try await eachFile(files, progress: progress) { file, report in
            let audioTracks = try await AVURLAsset(url: file.url).loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty else {
                throw DropError.unsupported("“\(file.url.lastPathComponent)” has no audio track.")
            }
            let dest = options.output.file(for: file.url, ext: "m4a")
            try await export(file.url, preset: AVAssetExportPresetAppleM4A, as: .m4a, to: dest, progress: report)
            return dest
        }
    }

    @concurrent
    static func makeGIF(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try await eachFile(files, progress: progress) { file, report in
            let dest = options.output.file(for: file.url, ext: "gif")
            try await gif(from: file.url, to: dest, fps: options.gifFPS, width: options.gifWidth, progress: report)
            return dest
        }
    }

    // MARK: Primitives

    private static func eachFile(
        _ files: [DroppedFile],
        progress: @escaping @Sendable (Double) -> Void,
        _ body: (DroppedFile, @escaping @Sendable (Double) -> Void) async throws -> URL
    ) async throws -> [URL] {
        var results: [URL] = []
        let count = Double(files.count)
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let base = Double(index)
            results.append(try await body(file) { fraction in progress((base + fraction) / count) })
        }
        return results
    }

    private static func export(_ source: URL, preset: String, as fileType: AVFileType, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw DropError.unsupported("This file can't be exported with that setting.")
        }
        let monitor = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        do {
            try await session.export(to: dest, as: fileType)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    private static func gif(from source: URL, to dest: URL, fps: Int, width: Int, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw DropError.unreadable(source.lastPathComponent) }

        let frameCount = max(1, Int(min(duration, maxGIFSeconds) * Double(fps)))
        let delay = 1.0 / Double(fps)
        let times = (0..<frameCount).map { CMTime(seconds: Double($0) * delay, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: width * 4)
        let tolerance = CMTime(seconds: delay / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw DropError.failed("Couldn't create the GIF.")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary

        // The declared frame count must match, so a frame that fails to decode repeats the last one.
        var written = 0
        var lastFrame: CGImage?
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            guard let frame = (try? result.image) ?? lastFrame else { continue }
            CGImageDestinationAddImage(destination, frame, frameProperties)
            lastFrame = frame
            written += 1
            progress(Double(written) / Double(frameCount))
        }
        while written < frameCount, let lastFrame {
            CGImageDestinationAddImage(destination, lastFrame, frameProperties)
            written += 1
        }
        guard written > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: dest)
            throw DropError.failed("Couldn't create the GIF.")
        }
    }
}
