import SwiftUI
import UniformTypeIdentifiers

/// Fills the panel. The content is pinned to the top so a size change can only ever clip the bottom.
struct DropPanelView: View {
    let session: DropSession
    let shelf: ShelfStore
    let controller: DropPanelController

    var body: some View {
        DropPanelContent(session: session, shelf: shelf, controller: controller)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.contentSizeChanged($0) }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}

/// The panel's content at its natural size. Also measured off-screen before the panel appears.
struct DropPanelContent: View {
    let session: DropSession
    let shelf: ShelfStore
    let controller: DropPanelController

    var body: some View {
        ZStack(alignment: .top) {
            switch session.phase {
            case .choosing:
                ChooserView(session: session, shelf: shelf, controller: controller)
            case .configuring:
                if let action = session.pendingAction, let draft = session.draft {
                    ActionFormView(
                        action: action, draft: draft, selection: session.selection,
                        onConfirm: { controller.confirmForm() },
                        onCancel: { controller.dismiss() }
                    )
                }
            case .working:
                WorkingView(session: session, controller: controller)
            case .finished:
                if let result = session.result {
                    ResultView(result: result, controller: controller)
                }
            case .failed:
                FailureView(session: session, controller: controller)
            case .shelf:
                ShelfView(shelf: shelf, controller: controller)
            }
        }
        .transition(.opacity)
        .animation(Theme.fade, value: session.phase)
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Choosing

private struct ChooserView: View {
    let session: DropSession
    let shelf: ShelfStore
    let controller: DropPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FileHeader(selection: session.selection)

            if !session.conversions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Convert to")
                    Rows(session.conversions) { action in
                        ConversionChip(action: action, session: session) { controller.run(action) }
                    }
                }
            }

            if !session.tools.isEmpty {
                ToolGrid(session: session, controller: controller)
            }

            if session.conversions.isEmpty && session.tools.isEmpty {
                Text("Nothing to do with this file yet.\nKeep it on the Shelf for later.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Footer(session: session, shelfCount: shelf.items.count) { controller.keepOnShelf() }
        }
        .padding(Theme.padding)
    }
}

private struct FileHeader: View {
    let selection: DropSelection

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailStack(urls: selection.urls, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(selection.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(selection.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Lays items out in rows of `Theme.columns`, each cell the same width.
private struct Rows<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let cell: (Item) -> Cell

    init(_ items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.cell = cell
    }

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: Theme.columns).map {
            Array(items[$0..<min($0 + Theme.columns, items.count)])
        }
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Theme.spacing) {
                    ForEach(rows[index]) { item in
                        cell(item).frame(width: Theme.tileWidth)
                    }
                }
            }
        }
    }
}

/// Reports hover-during-drag to the status line and gives a light haptic tick.
private struct DropTargetFeedback: ViewModifier {
    let session: DropSession
    let hint: String
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        content.onChange(of: isTargeted) { _, targeted in
            if targeted {
                session.hint = hint
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } else if session.hint == hint {
                session.hint = nil
            }
        }
    }
}

private struct ConversionChip: View {
    let action: ActionSpec
    let session: DropSession
    let onDrop: () -> Void

    @State private var isTargeted = false

    var body: some View {
        Text(action.title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isTargeted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.85)))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipCornerRadius, style: .continuous)
                    .fill(isTargeted ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Theme.surface))
            )
            .animation(Theme.hover, value: isTargeted)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { _ in
                onDrop()
                return true
            }
            .modifier(DropTargetFeedback(session: session, hint: hint, isTargeted: $isTargeted))
            .accessibilityLabel(action.name)
    }

    private var hint: String { "\(action.name) · \(session.options.map(action.detail) ?? "")" }
}

private struct ToolGrid: View {
    let session: DropSession
    let controller: DropPanelController

    /// One row by default: three tools and "More". Everything once opened.
    private var collapsedCount: Int { Theme.columns - 1 }

    var body: some View {
        let tools = session.tools
        let collapsed = !session.showsAllTools && tools.count > Theme.columns
        let shown = collapsed ? Array(tools.prefix(collapsedCount)) : tools
        let items = shown.map(ToolItem.action) + (collapsed ? [.more(tools.count - collapsedCount)] : [])

        Rows(items) { item in
            switch item {
            case .action(let action):
                ToolTile(action: action, session: session) { controller.run(action) }
            case .more(let hidden):
                MoreTile(hidden: hidden, session: session)
            }
        }
        .animation(Theme.fade, value: session.showsAllTools)
    }
}

private enum ToolItem: Identifiable {
    case action(ActionSpec)
    case more(Int)

    var id: String {
        switch self {
        case .action(let action): action.id
        case .more: "more"
        }
    }
}

private struct ToolTile: View {
    let action: ActionSpec
    let session: DropSession
    let onDrop: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 5) {
            ActionIcon(action: action, isTargeted: isTargeted)
            Text(action.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(isTargeted ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .animation(Theme.hover, value: isTargeted)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { _ in
            onDrop()
            return true
        }
        .modifier(DropTargetFeedback(session: session, hint: hint, isTargeted: $isTargeted))
        .accessibilityLabel(action.name)
    }

    private var hint: String { "\(action.name) · \(session.options.map(action.detail) ?? "")" }
}

/// Opens the rest of the tools. Hovering a dragged file over it opens it, like a spring-loaded folder.
private struct MoreTile: View {
    let hidden: Int
    let session: DropSession

    @State private var isTargeted = false
    @State private var springTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.toolCornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(isTargeted ? 3 : 1.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Theme.toolIconSize, height: Theme.toolIconSize)
            Text("\(hidden) more")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .animation(Theme.hover, value: isTargeted)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { _ in false }
        .modifier(DropTargetFeedback(session: session, hint: "Hold here to see more", isTargeted: $isTargeted))
        .onChange(of: isTargeted) { _, targeted in
            springTask?.cancel()
            guard targeted else { return }
            springTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { open() }
            }
        }
    }

    private func open() {
        session.hint = nil
        withAnimation(Theme.fade) { session.showsAllTools = true }
    }
}

/// Status line on the left, the Shelf target on the right.
private struct Footer: View {
    let session: DropSession
    let shelfCount: Int
    let onShelf: () -> Void

    @State private var shelfTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Text(session.hint ?? "Drop on an action")
                .font(.system(size: 11))
                .foregroundStyle(session.hint == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.12), value: session.hint)
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(shelfCount > 0 ? "Shelf · \(shelfCount)" : "Shelf")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(shelfTargeted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(shelfTargeted ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Theme.surface)))
            .animation(Theme.hover, value: shelfTargeted)
            .contentShape(Capsule())
            .onDrop(of: [UTType.fileURL], isTargeted: $shelfTargeted) { _ in
                onShelf()
                return true
            }
            .modifier(DropTargetFeedback(session: session, hint: "Keep on the Shelf for later", isTargeted: $shelfTargeted))
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

// MARK: - Working

private struct WorkingView: View {
    let session: DropSession
    let controller: DropPanelController

    var body: some View {
        if let action = session.activeAction {
            HStack(spacing: 12) {
                ActionIcon(action: action, size: 36, isTargeted: true)
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(action.verb)…")
                        .font(.system(size: 13, weight: .semibold))
                    Group {
                        if session.progress > 0 {
                            ProgressView(value: session.progress)
                        } else {
                            ProgressView()
                        }
                    }
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .animation(.linear(duration: 0.15), value: session.progress)
                }
                PanelIconButton(symbol: "xmark", help: "Cancel") { controller.cancelWork() }
            }
            .padding(Theme.padding)
        }
    }
}

// MARK: - Result

private struct ResultView: View {
    let result: DropResult
    let controller: DropPanelController

    @State private var appeared = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    preview
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.action.done)
                            .font(.system(size: 13, weight: .semibold))
                        Text(result.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(summaryColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .overlay {
                    if !result.files.isEmpty {
                        FileDragSource(urls: result.files, onDragEnded: { controller.resultsDraggedOut($0) })
                    }
                }
                .onHover { hovering = $0 }

                HStack(spacing: 4) {
                    if !result.files.isEmpty {
                        PanelIconButton(symbol: "folder", help: "Show in Finder") { controller.showInFinder(result.files) }
                        PanelIconButton(symbol: "doc.on.doc", help: "Copy to clipboard") { controller.copyToClipboard(result.files) }
                    }
                    PanelIconButton(symbol: "xmark", help: "Close") { controller.dismiss() }
                }
            }

            if let text = result.copiedText {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            } else {
                Text(result.files.count == 1 ? "Drag it anywhere · double-click to open" : "Drag all \(result.files.count) files anywhere")
                    .font(.system(size: 10.5))
                    .foregroundStyle(hovering ? .secondary : .tertiary)
            }
        }
        .padding(Theme.padding)
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private var preview: some View {
        if result.files.isEmpty {
            ZStack {
                Circle().fill(Color.green.gradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
        } else {
            ThumbnailStack(urls: result.files, size: 36)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.green)
                        .background(Circle().fill(.white).padding(1))
                        .offset(x: -4, y: 4)
                }
        }
    }

    private var summaryColor: Color {
        guard let savings = result.savings else { return .secondary }
        return savings > 0.005 ? .green : .secondary
    }
}

// MARK: - Failure

private struct FailureView: View {
    let session: DropSession
    let controller: DropPanelController

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.activeAction?.name ?? "That") didn't work")
                    .font(.system(size: 13, weight: .semibold))
                Text(session.errorMessage ?? "Something went wrong.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            PanelIconButton(symbol: "xmark", help: "Close") { controller.dismiss() }
        }
        .padding(Theme.padding)
    }
}

// MARK: - Shelf

private struct ShelfView: View {
    let shelf: ShelfStore
    let controller: DropPanelController

    @State private var isTargeted = false
    private let columns = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Shelf")
                    .font(.system(size: 13, weight: .semibold))
                if !shelf.isEmpty {
                    Text("\(shelf.items.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !shelf.isEmpty {
                    PanelIconButton(symbol: "folder", help: "Show in Finder") { controller.showInFinder(shelf.items) }
                    PanelIconButton(symbol: "trash", help: "Clear Shelf") { shelf.clear() }
                }
                PanelIconButton(symbol: "xmark", help: "Close") { controller.dismiss() }
            }

            if shelf.isEmpty {
                Text("Drop files here to keep them handy")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(isTargeted ? Color.accentColor : Theme.hairline.opacity(3))
                    )
            } else {
                let rows = stride(from: 0, to: shelf.items.count, by: columns).map {
                    Array(shelf.items[$0..<min($0 + columns, shelf.items.count)])
                }
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: Theme.spacing) {
                            ForEach(rows[index], id: \.self) { url in
                                ShelfItem(url: url) { shelf.remove(url) }
                            }
                        }
                    }
                }
                Text(shelf.items.count == 1 ? "Drag it out when you need it" : "Drag items out when you need them")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Theme.padding)
        .background(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(isTargeted ? 0.08 : 0))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { _ in
            controller.addDragToShelf()
            return true
        }
    }
}

private struct ShelfItem: View {
    let url: URL
    let onRemove: () -> Void

    @State private var hovering = false
    private let size: CGFloat = (Theme.panelWidth - Theme.padding * 2 - Theme.spacing * 4) / 5

    var body: some View {
        FileThumbnail(url: url, size: size - 14)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Theme.surface)
            )
            .overlay(FileDragSource(urls: [url]))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .help("Remove from Shelf")
                }
            }
            .onHover { hovering = $0 }
            .help(url.lastPathComponent)
    }
}
