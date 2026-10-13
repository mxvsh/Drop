import AppKit

/// The files the most recent action produced, kept across launches for "Open Last Result".
enum LastResult {
    private static let key = "results.last"

    /// Files that still exist; an empty list once they've all been moved or deleted.
    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func save(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
    }

    /// Opens each file in its default app. A large batch is shown in Finder instead of opening a pile of windows.
    static func open() {
        let urls = urls
        if urls.count > 5 {
            revealInFinder()
        } else {
            urls.forEach { NSWorkspace.shared.open($0) }
        }
    }

    static func revealInFinder() {
        let urls = urls
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}
