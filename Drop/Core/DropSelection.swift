import Foundation
import UniformTypeIdentifiers

/// What a dragged file is, detected from its content type rather than just its extension.
nonisolated enum FileKind: String, Sendable {
    case image, vector, pdf, video, audio, archive, text, folder, other

    static func detect(_ url: URL, type: UTType?, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        guard let type else { return .other }
        if type.conforms(to: .svg) { return .vector }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return .text }
        return .other
    }
}

nonisolated struct DroppedFile: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: FileKind
    let type: UTType?
    let size: Int64

    var id: URL { url }

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey, .fileSizeKey])
        let isFolder = values?.isDirectory == true && values?.isPackage != true
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        self.url = url
        self.type = type
        self.kind = FileKind.detect(url, type: type, isDirectory: isFolder)
        self.size = Int64(values?.fileSize ?? 0)
    }

    var formatLabel: String {
        if kind == .folder { return "Folder" }
        let ext = url.pathExtension
        if !ext.isEmpty { return ext.uppercased() }
        return type?.localizedDescription ?? "File"
    }

    func conforms(to type: UTType) -> Bool { self.type?.conforms(to: type) ?? false }
}

/// The files of one drag, summarized for the panel header and used to pick relevant actions.
nonisolated struct DropSelection: Equatable, Sendable {
    let files: [DroppedFile]

    init(urls: [URL]) {
        var seen = Set<URL>()
        files = urls.map(\.standardizedFileURL).filter { seen.insert($0).inserted }.map(DroppedFile.init)
    }

    var urls: [URL] { files.map(\.url) }
    var count: Int { files.count }
    var isEmpty: Bool { files.isEmpty }
    var kinds: Set<FileKind> { Set(files.map(\.kind)) }
    var commonKind: FileKind? { kinds.count == 1 ? kinds.first : nil }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func all(_ kind: FileKind) -> Bool { !files.isEmpty && commonKind == kind }
    func all(conformTo type: UTType) -> Bool { !files.isEmpty && files.allSatisfy { $0.conforms(to: type) } }
    var hasFolders: Bool { kinds.contains(.folder) }

    var title: String {
        if files.count == 1 { return files[0].url.lastPathComponent }
        let noun: String
        switch commonKind {
        case .image: noun = "Images"
        case .pdf: noun = "PDFs"
        case .video: noun = "Videos"
        case .audio: noun = "Audio Files"
        case .folder: noun = "Folders"
        default: noun = "Items"
        }
        return "\(files.count) \(noun)"
    }

    var subtitle: String {
        var formats: [String] = []
        for file in files where !formats.contains(file.formatLabel) { formats.append(file.formatLabel) }
        var parts: [String] = []
        if !formats.isEmpty {
            parts.append(formats.prefix(3).joined(separator: ", ") + (formats.count > 3 ? "…" : ""))
        }
        if totalSize > 0 { parts.append(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }
}
