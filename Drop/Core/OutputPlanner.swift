import Foundation

/// Decides where results are written and picks names that never overwrite an existing file.
nonisolated struct OutputPlanner: Sendable {
    enum Location: Sendable, Equatable {
        case besideOriginal
        case folder(URL)
    }

    var location: Location

    func folder(for source: URL) -> URL {
        switch location {
        case .besideOriginal:
            return source.deletingLastPathComponent()
        case .folder(let url):
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    /// `photo.heic` → `photo.png`, or `photo (compressed).jpg` with a suffix.
    func file(for source: URL, suffix: String = "", ext: String? = nil) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent + suffix
        return unique(in: folder(for: source), name: stem, ext: ext ?? source.pathExtension)
    }

    /// A free path in `folder`; appends " 2", " 3"… like Finder does. Pass an empty `ext` for folders.
    func unique(in folder: URL, name: String, ext: String) -> URL {
        let fm = FileManager.default
        func candidate(_ base: String) -> URL {
            let url = folder.appendingPathComponent(base)
            return ext.isEmpty ? url : url.appendingPathExtension(ext)
        }
        var url = candidate(name)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = candidate("\(name) \(n)")
            n += 1
        }
        return url
    }
}
