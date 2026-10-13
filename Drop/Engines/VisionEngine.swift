import CoreImage
import Foundation
import PDFKit
import Vision

nonisolated enum VisionEngine {
    /// Lifts the foreground subject onto a transparent PNG.
    @concurrent
    static func removeBackground(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let context = CIContext()
        return try Batch.map(files, progress: progress) { file in
            let image = try ImageEngine.decode(file.url).image
            let handler = VNImageRequestHandler(cgImage: image)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                throw DropError.noSubject
            }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false
            )
            let masked = CIImage(cvPixelBuffer: buffer)
            guard let cutout = context.createCGImage(masked, from: masked.extent) else {
                throw DropError.failed("Couldn't render the cutout.")
            }
            let dest = options.output.file(for: file.url, suffix: " (cutout)", ext: "png")
            try ImageEngine.write(cutout, to: dest, format: .png, quality: 1, properties: nil)
            return dest
        }
    }

    /// Text from images via OCR; from PDFs via their text layer, falling back to OCR for scans.
    @concurrent
    static func recognizeText(_ files: [DroppedFile], progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let chunks = try Batch.map(files, progress: progress) { file -> String in
            if file.kind == .pdf {
                guard let document = PDFDocument(url: file.url) else { throw DropError.unreadable(file.url.lastPathComponent) }
                if let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                return try (0..<min(document.pageCount, 30)).compactMap { index in
                    guard let page = document.page(at: index), let image = PDFEngine.render(page, scale: 2) else { return nil }
                    return try ocr(image)
                }.joined(separator: "\n\n")
            }
            return try ocr(ImageEngine.decode(file.url, maxPixel: 4096).image)
        }
        let text = chunks.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DropError.noText }
        return text
    }

    private static func ocr(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
