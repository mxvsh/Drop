import AppKit
import QuickLookThumbnailing
import SwiftUI

// MARK: - Action icon

/// Neutral icon for an action: its symbol, or its format name for conversions.
struct ActionIcon: View {
    let action: ActionSpec
    var size: CGFloat = Theme.toolIconSize
    var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Theme.surface))
            if action.isConversion {
                Text(action.title)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            } else {
                Image(systemName: action.symbol)
                    .font(.system(size: size * 0.38, weight: .medium))
            }
        }
        .foregroundStyle(isTargeted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.75)))
        .frame(width: size, height: size)
    }
}

// MARK: - Thumbnails

/// Quick Look thumbnail with the Finder icon as an instant placeholder.
struct FileThumbnail: View {
    let url: URL
    var size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: url, size: size)
        }
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [String: NSImage] = [:]

    func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))"
        if let cached = cache[key] { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache[key] = image
        return image
    }
}

/// Up to three thumbnails fanned out like a small stack of photos.
struct ThumbnailStack: View {
    let urls: [URL]
    var size: CGFloat = 44

    var body: some View {
        let shown = Array(urls.prefix(urls.count == 1 ? 1 : 3))
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.element) { index, url in
                let offset = CGFloat(index) - CGFloat(shown.count - 1) / 2
                FileThumbnail(url: url, size: size)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .rotationEffect(.degrees(Double(offset) * 6))
                    .offset(x: offset * 4)
                    .zIndex(Double(index))
            }
        }
        .frame(width: urls.count == 1 ? size : size + 8, height: size)
        .overlay(alignment: .bottomTrailing) {
            if urls.count > 1 {
                Text("\(urls.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color.accentColor))
                    .offset(x: 5, y: 4)
            }
        }
    }
}

// MARK: - Dragging files out

/// Transparent AppKit view laid over SwiftUI content that starts a real multi-file drag.
/// SwiftUI's `onDrag` carries a single item; this hands all files to Finder, Mail, Slack and so on.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    var onDragStarted: () -> Void = {}
    var onDragEnded: (NSDragOperation) -> Void = { _ in }

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) { update(view) }

    private func update(_ view: FileDragSourceView) {
        view.urls = urls
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onDragStarted: () -> Void = {}
    var onDragEnded: (NSDragOperation) -> Void = { _ in }
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Dragging here drags the file, never the window, even in windows movable by their background.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        // A click without a drag opens the file, matching Finder's double-click affordance.
        if event.clickCount >= 2, let url = urls.first { NSWorkspace.shared.open(url) }
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, !urls.isEmpty else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        mouseDownEvent = nil

        let origin = convert(start.locationInWindow, from: nil)
        let items = urls.prefix(12).enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 48, height: 48)
            let shift = CGFloat(index) * 4
            item.setDraggingFrame(NSRect(x: origin.x - 24 + shift, y: origin.y - 24 - shift, width: 48, height: 48), contents: icon)
            return item
        }
        let session = beginDraggingSession(with: Array(items), event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
        onDragStarted()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded(operation)
    }
}

// MARK: - Small pieces

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
    }
}

struct PanelIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A small key cap, e.g. ⌥, used in hints.
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

func formattedSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func fileSize(_ url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
    if values?.isDirectory == true {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
    return Int64(values?.fileSize ?? 0)
}
