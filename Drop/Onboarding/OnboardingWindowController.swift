import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: () -> Void
    private var finished = false
    private var hasSized = false

    init(
        settings: AppSettings,
        updater: UpdaterService,
        practice: PracticeSession,
        folders: FolderAccess,
        onShowMenuBarIcon: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.onFinish = onFinish
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let host = NSHostingController(
            rootView: OnboardingView(
                settings: settings, updater: updater, practice: practice, folders: folders,
                onShowMenuBarIcon: onShowMenuBarIcon,
                onSizeChange: { [weak self] size in self?.fit(size) },
                onFinish: { [weak self] in self?.finish() }
            )
        )
        // The window follows the page's size itself; SwiftUI would otherwise add the title bar's height.
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 480, height: 460))
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) { finish() }

    /// Each page sizes the window to its content, keeping the top edge where it is.
    private func fit(_ size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        var frame = window.frame
        let height = ceil(size.height)
        guard abs(frame.height - height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: ceil(size.width), height: height)
        if hasSized {
            window.animator().setFrame(frame, display: true)
        } else {
            window.setFrame(frame, display: true)
            window.center()
            hasSized = true
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
