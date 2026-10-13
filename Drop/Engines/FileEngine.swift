import CryptoKit
import UniformTypeIdentifiers
import Foundation

nonisolated enum FileEngine {
    /// One item zips as `Name.zip`; several go into `Archive.zip` with the items at its root, like Finder.
    @concurrent
    static func zip(_ files: [DroppedFile], options: ProcessingOptions) async throws -> [URL] {
        let fm = FileManager.default
        let first = files[0].url
        let folder = options.output.folder(for: first)

        if files.count == 1 {
            let dest = options.output.unique(in: folder, name: first.lastPathComponent, ext: "zip")
            try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, dest.path])
            return [dest]
        }

        let staging = fm.temporaryDirectory.appendingPathComponent("Drop-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let planner = OutputPlanner(location: .folder(staging))
        for file in files {
            let name = file.url.deletingPathExtension().lastPathComponent
            try fm.copyItem(at: file.url, to: planner.unique(in: staging, name: name, ext: file.url.pathExtension))
        }
        let dest = options.output.unique(in: folder, name: "Archive", ext: "zip")
        try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, dest.path])
        return [dest]
    }

    /// Extracts next to the archive. A single top-level item is unwrapped so you don't get `Name/Name/`.
    @concurrent
    static func unzip(_ files: [DroppedFile], options: ProcessingOptions) async throws -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []
        for file in files {
            try Task.checkCancellation()
            let folder = options.output.folder(for: file.url)
            let staging = folder.appendingPathComponent(".drop-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            try await run("/usr/bin/ditto", ["-x", "-k", file.url.path, staging.path])

            let contents = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }
            if contents.count == 1, let only = contents.first {
                let dest = options.output.unique(
                    in: folder, name: only.deletingPathExtension().lastPathComponent, ext: only.pathExtension
                )
                try fm.moveItem(at: only, to: dest)
                results.append(dest)
            } else {
                let dest = options.output.unique(in: folder, name: file.url.deletingPathExtension().lastPathComponent, ext: "")
                try fm.moveItem(at: staging, to: dest)
                results.append(dest)
            }
        }
        return results
    }

    /// `shasum -a 256` style output for several files, the bare hash for one.
    @concurrent
    static func sha256(_ files: [DroppedFile], progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let lines = try Batch.map(files, progress: progress) { file -> String in
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: chunk)
            }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return files.count == 1 ? hex : "\(hex)  \(file.url.lastPathComponent)"
        }
        return lines.joined(separator: "\n")
    }

    /// Images become a `data:` URI ready for CSS or HTML; anything else is plain Base64.
    @concurrent
    static func base64(_ file: DroppedFile) async throws -> String {
        let encoded = try Data(contentsOf: file.url).base64EncodedString()
        if file.kind == .image || file.kind == .vector, let mime = file.type?.preferredMIMEType {
            return "data:\(mime);base64,\(encoded)"
        }
        return encoded
    }

    static func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(throwing: DropError.failed(message.isEmpty ? "The operation failed." : message))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
