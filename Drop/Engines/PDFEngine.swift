import AppKit
import Foundation
import PDFKit

nonisolated enum PDFEngine {
    @concurrent
    static func merge(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let merged = PDFDocument()
        _ = try Batch.map(files, progress: progress) { file in
            guard let document = PDFDocument(url: file.url) else { throw DropError.unreadable(file.url.lastPathComponent) }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.copy() as? PDFPage {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        let first = files[0].url
        let dest = options.output.unique(in: options.output.folder(for: first), name: "Merged", ext: "pdf")
        guard merged.write(to: dest) else { throw DropError.failed("Couldn't write the merged PDF.") }
        return [dest]
    }

    @concurrent
    static func compress(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try Batch.map(files, progress: progress) { file in
            guard let document = PDFDocument(url: file.url) else { throw DropError.unreadable(file.url.lastPathComponent) }
            let dest = options.output.file(for: file.url, suffix: " (compressed)", ext: "pdf")
            let written = document.write(to: dest, withOptions: [
                .saveImagesAsJPEGOption: true,
                .optimizeImagesForScreenOption: true,
            ])
            guard written else { throw DropError.failed("Couldn't compress \(file.url.lastPathComponent).") }
            return dest
        }
    }

    /// One PNG per page. Multi-page documents get their own folder.
    @concurrent
    static func exportPages(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        try Batch.map(files, progress: progress) { file -> [URL] in
            guard let document = PDFDocument(url: file.url), document.pageCount > 0 else {
                throw DropError.unreadable(file.url.lastPathComponent)
            }
            let stem = file.url.deletingPathExtension().lastPathComponent
            if document.pageCount == 1, let page = document.page(at: 0) {
                let dest = options.output.file(for: file.url, ext: "png")
                try writePNG(page, to: dest)
                return [dest]
            }
            let folder = options.output.unique(in: options.output.folder(for: file.url), name: "\(stem) Pages", ext: "")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                try writePNG(page, to: folder.appendingPathComponent("\(stem) \(index + 1).png"))
            }
            return [folder]
        }.flatMap { $0 }
    }

    @concurrent
    static func imagesToPDF(_ files: [DroppedFile], options: ProcessingOptions, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        let document = PDFDocument()
        _ = try Batch.map(files, progress: progress) { file in
            let image = try ImageEngine.decode(file.url).image
            // Keep full resolution but lay the page out at a printable size (A4 long edge).
            let scale = min(1, 842 / CGFloat(max(image.width, image.height)))
            let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            guard let page = PDFPage(image: NSImage(cgImage: image, size: size)) else {
                throw DropError.failed("Couldn't add \(file.url.lastPathComponent).")
            }
            document.insert(page, at: document.pageCount)
        }
        let first = files[0].url
        let name = files.count == 1 ? first.deletingPathExtension().lastPathComponent : "Images"
        let dest = options.output.unique(in: options.output.folder(for: first), name: name, ext: "pdf")
        guard document.write(to: dest) else { throw DropError.failed("Couldn't write the PDF.") }
        return [dest]
    }

    // MARK: Rendering

    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = NSSize(
            width: (rotated ? bounds.height : bounds.width) * scale,
            height: (rotated ? bounds.width : bounds.height) * scale
        )
        let image = page.thumbnail(of: size, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func writePNG(_ page: PDFPage, to url: URL) throws {
        guard let image = render(page, scale: 2) else { throw DropError.failed("Couldn't render a page.") }
        try ImageEngine.write(image, to: url, format: .png, quality: 1, properties: nil)
    }
}
