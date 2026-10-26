import Foundation
import UniformTypeIdentifiers

/// Every built-in action. The panel shows only the ones that fit what's being dragged.
/// Order matters: it's the order tiles appear in, so the most useful come first.
nonisolated enum ActionCatalog {
    static let all: [ActionSpec] = conversions + tools

    static func available(for selection: DropSelection, disabled: Set<String>) -> [ActionSpec] {
        all.filter { !disabled.contains($0.id) && selection.count >= $0.minCount && $0.isAvailable(selection) }
    }

    // MARK: Conversions (shown as format chips)

    private static let conversions: [ActionSpec] = imageConversions + iconConversions + [
        ActionSpec(
            id: "images.pdf", title: "PDF", name: "Make a PDF", detail: "One page per image", symbol: "doc.richtext",
            group: .convert, verb: "Making a PDF", done: "Created PDF",
            isAvailable: { $0.all(.image) },
            run: { .files(try await PDFEngine.imagesToPDF($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "pdf.png", title: "PNG", name: "Export pages as PNG", detail: "One image per page", symbol: "photo",
            group: .convert, verb: "Exporting pages", done: "Exported pages",
            isAvailable: { $0.all(.pdf) },
            run: { .files(try await PDFEngine.exportPages($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "video.mp4", title: "MP4", name: "Convert to MP4", detail: "H.264, plays anywhere", symbol: "film",
            group: .convert, verb: "Converting to MP4", done: "Converted to MP4", replacesOriginals: true,
            isAvailable: { $0.all(.video) && !$0.all(conformTo: .mpeg4Movie) },
            run: { .files(try await MediaEngine.convertToMP4($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "video.gif", title: "GIF", name: "Make a GIF", detail: "Choose size and frame rate", symbol: "film", configuration: .gif,
            group: .convert, verb: "Making a GIF", done: "Created GIF",
            isAvailable: { $0.all(.video) },
            run: { .files(try await MediaEngine.makeGIF($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "audio.m4a", title: "M4A", name: "Convert to M4A", detail: "AAC audio", symbol: "waveform",
            group: .convert, verb: "Converting to M4A", done: "Converted to M4A", replacesOriginals: true,
            isAvailable: { $0.all(.audio) && !$0.all(conformTo: .mpeg4Audio) },
            run: { .files(try await MediaEngine.convertToM4A($0.files, options: $0.options, progress: $0.progress)) }
        ),
    ]

    private static var imageConversions: [ActionSpec] {
        ImageFormat.allCases.filter(\.canWrite).map { format in
            ActionSpec(
                id: "image.\(format.rawValue)", title: format.label, name: "Convert to \(format.label)", detail: format.hint,
                symbol: "photo", group: .convert,
                verb: "Converting to \(format.label)", done: "Converted to \(format.label)", replacesOriginals: true,
                // Hide the format everything already is.
                isAvailable: { $0.all(.image) && !$0.files.allSatisfy { ImageFormat.of($0) == format } },
                run: { .files(try await ImageEngine.convert($0.files, to: format, options: $0.options, progress: $0.progress)) }
            )
        }
    }

    private static var iconConversions: [ActionSpec] {
        IconFormat.allCases.filter(\.canWrite).map { format in
            ActionSpec(
                id: "image.\(format.rawValue)", title: format.label, name: "Make \(format.label) icon",
                detail: "\(format.hint), \(format.sizes.first!)–\(format.sizes.last!) px",
                symbol: "app.dashed", group: .convert, verb: "Making \(format.label) icon", done: "Created \(format.label) icon",
                isAvailable: { $0.all(.image) && !$0.all(conformTo: UTType(importedAs: format.typeIdentifier)) },
                run: { .files(try await ImageEngine.makeIcon($0.files, format: format, options: $0.options, progress: $0.progress)) }
            )
        }
    }

    // MARK: Tools (shown as icon tiles)

    private static let tools: [ActionSpec] = [
        ActionSpec(
            id: "image.compress", title: "Compress", name: "Compress", detail: "Choose quality",
            symbol: "arrow.down.right.and.arrow.up.left", configuration: .quality,
            group: .optimize, verb: "Compressing", done: "Compressed", replacesOriginals: true, reportsSavings: true,
            isAvailable: { selection in
                selection.all(.image) && selection.files.allSatisfy { file in
                    guard let format = ImageFormat.of(file) else { return !file.conforms(to: .gif) }
                    return format.isLossy
                }
            },
            run: { .files(try await ImageEngine.compress($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "pdf.merge", title: "Merge", name: "Merge into one PDF", detail: "In the order dragged", symbol: "doc.on.doc",
            group: .create, verb: "Merging PDFs", done: "Merged", minCount: 2,
            isAvailable: { $0.all(.pdf) },
            run: { .files(try await PDFEngine.merge($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "pdf.compress", title: "Compress", name: "Compress", detail: "Downsamples images", symbol: "arrow.down.right.and.arrow.up.left",
            group: .optimize, verb: "Compressing", done: "Compressed", replacesOriginals: true, reportsSavings: true,
            isAvailable: { $0.all(.pdf) },
            run: { .files(try await PDFEngine.compress($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "video.compress", title: "Compress", name: "Compress", detail: "Choose resolution",
            symbol: "arrow.down.right.and.arrow.up.left", configuration: .videoResolution,
            group: .optimize, verb: "Compressing video", done: "Compressed", replacesOriginals: true, reportsSavings: true,
            isAvailable: { $0.all(.video) },
            run: { .files(try await MediaEngine.compressVideo($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "image.resize", title: "Resize", name: "Resize", detail: "Choose a size",
            symbol: "arrow.up.left.and.arrow.down.right", configuration: .resize,
            group: .optimize, verb: "Resizing", done: "Resized", replacesOriginals: true, reportsSavings: true,
            isAvailable: { $0.all(.image) },
            run: { .files(try await ImageEngine.resize($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "image.cutout", title: "Cut Out", name: "Remove background", detail: "Transparent PNG", symbol: "person.and.background.dotted",
            group: .create, verb: "Removing background", done: "Removed background",
            isAvailable: { $0.all(.image) },
            run: { .files(try await VisionEngine.removeBackground($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "video.audio", title: "Audio", name: "Extract audio", detail: "Saved as M4A", symbol: "waveform",
            group: .create, verb: "Extracting audio", done: "Extracted audio",
            isAvailable: { $0.all(.video) },
            run: { .files(try await MediaEngine.convertToM4A($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "text.recognize", title: "Copy Text", name: "Copy text", detail: "Reads text, even in scans", symbol: "text.viewfinder",
            group: .create, verb: "Reading text", done: "Copied text",
            isAvailable: { $0.all(.image) || $0.all(.pdf) },
            run: { input in
                let text = try await VisionEngine.recognizeText(input.files, progress: input.progress)
                let words = text.split(whereSeparator: \.isWhitespace).count
                return .text(text, summary: "\(words) words on the clipboard")
            }
        ),
        ActionSpec(
            id: "files.unzip", title: "Unzip", name: "Unzip", detail: "Extracts next to the archive", symbol: "archivebox",
            group: .utilities, verb: "Extracting", done: "Extracted",
            isAvailable: { $0.all(conformTo: .zip) },
            run: { .files(try await FileEngine.unzip($0.files, options: $0.options)) }
        ),
        ActionSpec(
            id: "image.strip", title: "Clean", name: "Strip metadata", detail: "Removes EXIF and location", symbol: "location.slash",
            group: .optimize, verb: "Removing metadata", done: "Removed metadata", replacesOriginals: true,
            isAvailable: { $0.all(.image) },
            run: { .files(try await ImageEngine.stripMetadata($0.files, options: $0.options, progress: $0.progress)) }
        ),
        ActionSpec(
            id: "image.info", title: "Info", name: "Show info", detail: "Size, dimensions and metadata", symbol: "info.circle",
            group: .utilities, verb: "Reading", done: "Image info",
            isAvailable: { $0.count == 1 && $0.all(.image) },
            run: { input in
                let rows = try await ImageEngine.info(input.files[0])
                let summary = rows.first { $0.label == "Dimensions" }?.value ?? ByteCountFormatter.string(fromByteCount: input.files[0].size, countStyle: .file)
                return .details(rows, summary: summary)
            }
        ),
        ActionSpec(
            id: "files.zip", title: "Zip", name: "Zip", detail: "Compressed archive", symbol: "doc.zipper",
            group: .utilities, verb: "Zipping", done: "Zipped",
            isAvailable: { !$0.isEmpty },
            run: { .files(try await FileEngine.zip($0.files, options: $0.options)) }
        ),
        ActionSpec(
            id: "copy.path", title: "Copy Path", name: "Copy path", detail: "Full path to the clipboard", symbol: "link",
            group: .utilities, verb: "Copying", done: "Copied path",
            isAvailable: { !$0.isEmpty },
            run: { input in
                let paths = input.files.map(\.url.path)
                return .text(paths.joined(separator: "\n"), summary: paths.count == 1 ? "On the clipboard" : "\(paths.count) paths on the clipboard")
            }
        ),
        ActionSpec(
            id: "copy.base64", title: "Base64", name: "Copy as Base64", detail: "Data URI for images", symbol: "chevron.left.forwardslash.chevron.right",
            group: .utilities, verb: "Encoding", done: "Copied Base64",
            isAvailable: { $0.count == 1 && !$0.hasFolders && $0.totalSize <= 20_000_000 },
            run: { input in
                let encoded = try await FileEngine.base64(input.files[0])
                let size = ByteCountFormatter.string(fromByteCount: Int64(encoded.utf8.count), countStyle: .memory)
                return .text(encoded, summary: "\(size) on the clipboard")
            }
        ),
        ActionSpec(
            id: "copy.sha256", title: "Checksum", name: "Copy SHA-256", detail: "Checksum to the clipboard", symbol: "number",
            group: .utilities, verb: "Hashing", done: "Copied checksum",
            isAvailable: { !$0.isEmpty && !$0.hasFolders },
            run: { input in
                let hash = try await FileEngine.sha256(input.files, progress: input.progress)
                return .text(hash, summary: input.files.count == 1 ? "On the clipboard" : "\(input.files.count) checksums on the clipboard")
            }
        ),
    ]
}
