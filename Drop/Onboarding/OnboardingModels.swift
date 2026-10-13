import AppKit
import Observation
import SwiftUI

/// Tracks the hands-on step: drag the sample, hold the trigger, drop on an action.
@Observable
final class PracticeSession {
    var isActive = false
    var hasDragged = false
    var hasRevealed = false
    var hasDropped = false

    /// Lives in a temporary folder, which macOS doesn't guard, so practice never triggers a permission prompt.
    let sampleURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Drop Practice", isDirectory: true)
        .appendingPathComponent("Sample Photo.png")

    var isComplete: Bool { hasDropped }

    func prepareSample() {
        let folder = sampleURL.deletingLastPathComponent()
        // Start clean so earlier practice results don't pile up.
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: SampleArtwork())
        renderer.scale = 2
        if let image = renderer.cgImage {
            try? ImageEngine.write(image, to: sampleURL, format: .png, quality: 1, properties: nil)
        }
    }

    func reset() {
        hasDragged = false
        hasRevealed = false
        hasDropped = false
    }
}

/// A small generated landscape, so the practice file looks like a real photo.
private struct SampleArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.4), Color(red: 0.55, green: 0.36, blue: 0.95)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Color(red: 1, green: 0.9, blue: 0.6))
                .frame(width: 150)
                .offset(y: -20)
            MountainShape(peak: 0.35)
                .fill(Color(red: 0.3, green: 0.22, blue: 0.55))
            MountainShape(peak: 0.6)
                .fill(Color(red: 0.18, green: 0.14, blue: 0.38))
        }
        .frame(width: 600, height: 400)
    }
}

private struct MountainShape: Shape {
    let peak: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY * 0.75))
        path.addLine(to: CGPoint(x: rect.width * peak, y: rect.maxY * 0.45))
        path.addLine(to: CGPoint(x: rect.width * (peak + 0.3), y: rect.maxY * 0.8))
        path.addLine(to: CGPoint(x: rect.width, y: rect.maxY * 0.6))
        path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// macOS guards Desktop, Documents and Downloads even for apps outside the sandbox. Touching each
/// folder here raises the system prompt during onboarding instead of in the middle of a drag.
@Observable
final class FolderAccess {
    enum Status { case notAsked, granted, denied }

    struct Folder: Identifiable {
        let name: String
        let symbol: String
        let url: URL
        var status: Status = .notAsked
        var id: String { name }
    }

    var folders = [
        Folder(name: "Desktop", symbol: "menubar.dock.rectangle", url: .desktopDirectory),
        Folder(name: "Documents", symbol: "doc", url: .documentsDirectory),
        Folder(name: "Downloads", symbol: "arrow.down.circle", url: .downloadsDirectory),
    ]
    var isRequesting = false

    var allGranted: Bool { folders.allSatisfy { $0.status == .granted } }
    var anyDenied: Bool { folders.contains { $0.status == .denied } }
    var wasAsked: Bool { folders.contains { $0.status != .notAsked } }

    func request() async {
        isRequesting = true
        for index in folders.indices {
            let url = folders[index].url
            // The prompt blocks the calling thread until answered, so ask off the main thread.
            let granted = await Task.detached {
                (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
            }.value
            folders[index].status = granted ? .granted : .denied
        }
        isRequesting = false
    }

    static func openFilesAndFoldersSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
