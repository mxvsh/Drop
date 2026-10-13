import AppKit

/// The menu bar item. A plain `NSMenu`, rebuilt each time it opens so it always reflects current state.
final class StatusMenuController: NSObject, NSMenuDelegate {
    var onShowShelf: () -> Void = {}
    var onShowSettings: () -> Void = {}
    var onShowWelcome: () -> Void = {}

    private let settings: AppSettings
    private let shelf: ShelfStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(settings: AppSettings, shelf: ShelfStore) {
        self.settings = settings
        self.shelf = shelf
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let shelfTitle = shelf.isEmpty ? "Show Shelf" : "Show Shelf (\(shelf.items.count))"
        menu.addItem(ClosureMenuItem(title: shelfTitle, symbol: "tray.full", keyEquivalent: "") { [weak self] in
            self?.onShowShelf()
        })

        let pause = ClosureMenuItem(title: "Pause Drop", symbol: "pause.circle", keyEquivalent: "") { [weak self] in
            guard let self else { return }
            self.settings.isPaused.toggle()
            self.updateIcon()
        }
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(pause)

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Welcome Guide", symbol: "sparkles", keyEquivalent: "") { [weak self] in
            self?.onShowWelcome()
        })
        menu.addItem(ClosureMenuItem(title: "Settings…", symbol: "gearshape", keyEquivalent: ",") { [weak self] in
            self?.onShowSettings()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Drop", symbol: nil, keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    private var hintTitle: String {
        if settings.isPaused { return "Drop is paused" }
        if settings.trigger == .shakeOnly { return "Shake while dragging a file" }
        return "Hold \(settings.trigger.keySymbol) while dragging a file"
    }

    private func updateIcon() {
        let name = settings.isPaused ? "drop" : "drop.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Drop")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = settings.isPaused
    }
}

/// A menu item that runs a closure, avoiding `@objc` selectors at each call site.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String?, keyEquivalent: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
