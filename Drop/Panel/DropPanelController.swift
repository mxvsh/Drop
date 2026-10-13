import AppKit
import SwiftUI

/// Owns the floating drop zone: where it appears, what it shows, and running the chosen action.
final class DropPanelController {
    let session = DropSession()
    /// Called after any action finishes successfully.
    var onActionFinished: (() -> Void)?

    private let settings: AppSettings
    private let shelf: ShelfStore
    private let panel = DropPanel()
    private var hostingView: NSHostingView<DropPanelView>?

    private var contentSize = CGSize(width: Theme.panelWidth, height: 320)
    private var anchor: NSPoint = .zero
    private var presentedAt: Date = .distantPast
    private var isPresented = false
    private var task: Task<Void, Never>?
    private var autoDismiss: Task<Void, Never>?
    private var outsideClickMonitor: Any?

    init(settings: AppSettings, shelf: ShelfStore) {
        self.settings = settings
        self.shelf = shelf
        let hostingView = NSHostingView(rootView: DropPanelView(session: session, shelf: shelf, controller: self))
        hostingView.sizingOptions = []
        self.hostingView = hostingView
        panel.contentView = PanelBackground.make(content: hostingView, cornerRadius: Theme.panelCornerRadius)
        panel.onCancel = { [weak self] in self?.dismiss() }
    }

    // MARK: Drag lifecycle

    /// Called by `DragMonitor` when the trigger is met mid-drag.
    func reveal(urls: [URL]) {
        guard session.phase != .working else { return }
        let selection = DropSelection(urls: urls)
        guard !selection.isEmpty else { return }
        cancelAutoDismiss()
        session.selection = selection
        session.options = settings.processingOptions
        let actions = ActionCatalog.available(for: selection, disabled: settings.disabledActions)
        session.conversions = actions.filter(\.isConversion)
        session.tools = actions.filter { !$0.isConversion }
        session.showsAllTools = false
        session.hint = nil
        session.result = nil
        session.errorMessage = nil
        session.isDragging = true
        session.phase = .choosing
        present(at: NSEvent.mouseLocation)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// The drag finished. If nothing was dropped on the panel, it goes away.
    func dragEnded() {
        session.isDragging = false
        guard session.phase == .choosing else { return }
        // The drop callback can arrive slightly after the mouse is released.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if session.phase == .choosing && !session.isDragging { dismiss() }
        }
    }

    // MARK: Actions

    /// A drop on an action. Configurable actions show their form first; the rest run straight away.
    func run(_ action: ActionSpec) {
        guard task == nil, !session.selection.isEmpty else { return }
        if let configuration = action.configuration {
            session.draft = ActionDraft(configuration: configuration, settings: settings, selection: session.selection)
            session.pendingAction = action
            session.hint = nil
            session.isDragging = false
            session.phase = .configuring
            // Key, but not active: typing goes to the form while the other app stays frontmost.
            panel.makeKey()
            return
        }
        execute(action, options: settings.processingOptions)
    }

    func confirmForm() {
        guard let action = session.pendingAction, let draft = session.draft, draft.isValid else { return }
        draft.remember(in: settings)
        var options = settings.processingOptions
        draft.apply(to: &options)
        execute(action, options: options)
    }

    private func execute(_ action: ActionSpec, options: ProcessingOptions) {
        let selection = session.selection
        guard task == nil, !selection.isEmpty else { return }
        session.activeAction = action
        session.hint = nil
        session.progress = 0
        session.isDragging = false
        session.phase = .working
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)

        let session = session
        let input = ActionInput(files: selection.files, options: options) { value in
            Task { @MainActor in
                if session.phase == .working { session.progress = max(session.progress, value) }
            }
        }
        task = Task { [weak self] in
            do {
                let output = try await action.run(input)
                self?.complete(action, selection: selection, output: output)
            } catch is CancellationError {
                self?.dismiss(force: true)
            } catch {
                self?.fail(action, error: error)
            }
            self?.task = nil
        }
    }

    func cancelWork() {
        task?.cancel()
    }

    func keepOnShelf() {
        shelf.add(session.selection.urls)
        session.isDragging = false
        session.phase = .shelf
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Files dropped straight onto the open shelf, without the trigger.
    func addDragToShelf() {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        shelf.add(urls)
    }

    func showShelf() {
        shelf.prune()
        cancelAutoDismiss()
        session.phase = .shelf
        present(at: NSEvent.mouseLocation)
    }

    func showInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyToClipboard(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// After results are dragged into another app the job is done.
    func resultsDraggedOut(_ operation: NSDragOperation) {
        guard !operation.isEmpty, session.phase == .finished else { return }
        dismiss()
    }

    private func complete(_ action: ActionSpec, selection: DropSelection, output: ActionOutput) {
        switch output {
        case .files(let urls):
            let before = selection.totalSize
            let after = urls.reduce(Int64(0)) { $0 + fileSize($1) }
            var parts = ["\(urls.count) \(urls.count == 1 ? "file" : "files")", formattedSize(after)]
            var savings: Double?
            if action.reportsSavings, before > 0 {
                let ratio = 1 - Double(after) / Double(before)
                savings = ratio
                let percent = Int((abs(ratio) * 100).rounded())
                parts.append(percent == 0 ? "same size" : ratio > 0 ? "\(percent)% smaller" : "\(percent)% larger")
            }
            session.result = DropResult(
                action: action, files: urls, summary: parts.joined(separator: " · "), copiedText: nil, savings: savings
            )
            applyOutputPreferences(action, originals: selection.urls, results: urls)

        case .text(let text, let summary):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            session.result = DropResult(action: action, files: [], summary: summary, copiedText: text, savings: nil)
            scheduleAutoDismiss(after: .seconds(2.5))
        }
        session.phase = .finished
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        onActionFinished?()
    }

    private func applyOutputPreferences(_ action: ActionSpec, originals: [URL], results: [URL]) {
        if settings.originals == .trash && action.replacesOriginals {
            for url in originals where !results.contains(url) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }
        if settings.copyResultToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(results as [NSURL])
        }
        if settings.revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting(results)
        }
    }

    private func fail(_ action: ActionSpec, error: Error) {
        session.errorMessage = error.localizedDescription
        session.phase = .failed
        NSSound.beep()
    }

    // MARK: Presentation

    /// The content's height for the current state, computed off-screen so the panel opens at the right size.
    private func measuredContentSize() -> CGSize {
        let host = NSHostingController(rootView: DropPanelContent(session: session, shelf: shelf, controller: self))
        let fitting = host.sizeThatFits(in: CGSize(width: Theme.panelWidth, height: 4000))
        return CGSize(width: Theme.panelWidth, height: ceil(fitting.height))
    }

    private func present(at point: NSPoint) {
        anchor = point
        let measured = measuredContentSize()
        if measured.height > 0 { contentSize = measured }
        if !isPresented {
            isPresented = true
            presentedAt = Date()
            panel.setFrame(initialFrame(), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
            installOutsideClickMonitor()
        } else {
            panel.setFrame(clamped(initialFrame()), display: true, animate: false)
        }
    }

    func dismiss(force: Bool = false) {
        guard isPresented, force || session.phase != .working else { return }
        isPresented = false
        cancelAutoDismiss()
        removeOutsideClickMonitor()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPresented else { return }
                self.panel.orderOut(nil)
                self.session.phase = .choosing
                self.session.result = nil
                self.session.activeAction = nil
                self.session.pendingAction = nil
                self.session.draft = nil
            }
        })
    }

    /// The SwiftUI content reports its size; the panel follows, keeping its top edge in place.
    func contentSizeChanged(_ size: CGSize) {
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        guard isPresented else { return }

        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        frame = clamped(frame)

        if Date().timeIntervalSince(presentedAt) < 0.12 {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        })
    }

    /// Beside the cursor with the header level with it, flipped to the left near the screen edge.
    private func initialFrame() -> NSRect {
        let screen = screenForAnchor()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.x + Theme.cursorGap
        if x + contentSize.width > visible.maxX - Theme.screenMargin {
            x = anchor.x - Theme.cursorGap - contentSize.width
        }
        let top = anchor.y + 36
        return clamped(NSRect(x: x, y: top - contentSize.height, width: contentSize.width, height: contentSize.height))
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        guard let visible = screenForAnchor()?.visibleFrame.insetBy(dx: Theme.screenMargin, dy: Theme.screenMargin) else {
            return frame
        }
        var frame = frame
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    private func screenForAnchor() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch self.session.phase {
                case .configuring, .finished, .failed, .shelf: self.dismiss()
                case .choosing, .working: break
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func scheduleAutoDismiss(after delay: Duration) {
        cancelAutoDismiss()
        autoDismiss = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Hovering keeps it open so the copied text can be read.
            while self.panel.frame.contains(NSEvent.mouseLocation) {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { return }
            }
            if self.session.phase == .finished { self.dismiss() }
        }
    }

    private func cancelAutoDismiss() {
        autoDismiss?.cancel()
        autoDismiss = nil
    }
}
