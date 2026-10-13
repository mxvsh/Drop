import AppKit
import ServiceManagement
import SwiftUI

/// Preferences window: a toolbar-style tab controller with a SwiftUI form per pane.
final class SettingsWindowController: NSWindowController {
    private static let paneSize = NSSize(width: 560, height: 520)

    init(settings: AppSettings) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.pane("General", symbol: "gearshape", GeneralPane(settings: settings)))
        tabs.addTabViewItem(Self.pane("Output", symbol: "square.and.arrow.down", OutputPane(settings: settings)))
        tabs.addTabViewItem(Self.pane("Actions", symbol: "square.grid.2x2", ActionsPane(settings: settings)))
        tabs.addTabViewItem(Self.pane("About", symbol: "info.circle", AboutPane()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.setContentSize(Self.paneSize)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func pane<Content: View>(_ title: String, symbol: String, _ content: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: content.frame(width: paneSize.width, height: paneSize.height))
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Drop: couldn't update login item: \(error.localizedDescription)")
        }
    }
}
