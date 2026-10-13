import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private let settings = AppSettings()
    private let shelf = ShelfStore()
    private let updater = UpdaterService()
    private let practice = PracticeSession()
    private var panelController: DropPanelController!
    private var dragMonitor: DragMonitor!
    private var statusMenu: StatusMenuController!
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = DropPanelController(settings: settings, shelf: shelf)

        dragMonitor = DragMonitor(settings: settings)
        dragMonitor.onReveal = { [weak self] urls in
            guard let self else { return }
            let sample = self.practice.sampleURL.resolvingSymlinksInPath()
            if self.practice.isActive && urls.contains(where: { $0.resolvingSymlinksInPath() == sample }) {
                self.practice.hasRevealed = true
            }
            self.panelController.reveal(urls: urls)
        }
        dragMonitor.acceptsLocalDrags = { [weak self] in self?.practice.isActive ?? false }
        panelController.onActionFinished = { [weak self] in
            guard let self, self.practice.isActive, self.practice.hasRevealed else { return }
            self.practice.hasDropped = true
        }
        dragMonitor.onDragEnded = { [weak self] in self?.panelController.dragEnded() }
        dragMonitor.start()

        statusMenu = StatusMenuController(settings: settings, shelf: shelf, updater: updater)
        statusMenu.onShowShelf = { [weak self] in self?.panelController.showShelf() }
        statusMenu.onShowSettings = { [weak self] in self?.showSettings() }
        statusMenu.onShowWelcome = { [weak self] in self?.showOnboarding() }

        if !settings.onboardingCompleted { showOnboarding() }

        #if DEBUG
        // Lets scripts open the panel without a real drag: post "com.monawwar.Drop.debugReveal" with newline-separated paths.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.monawwar.Drop.debugReveal"), object: nil, queue: .main) { [weak self] note in
            let urls = (note.object as? String ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            MainActor.assumeIsolated { self?.panelController.reveal(urls: urls) }
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: settings, updater: updater) }
        NSApp.activate()
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            practice.reset()
            onboardingWindow = OnboardingWindowController(
                settings: settings, updater: updater, practice: practice, folders: FolderAccess(),
                onShowMenuBarIcon: { [weak self] in self?.statusMenu.pulse() }
            ) { [weak self] in
                self?.practice.isActive = false
                self?.settings.onboardingCompleted = true
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        }
        NSApp.activate()
        onboardingWindow?.showWindow(nil)
        onboardingWindow?.window?.makeKeyAndOrderFront(nil)
    }
}
