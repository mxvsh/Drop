import Foundation
import Sparkle

/// In-app updates through Sparkle. The feed URL and EdDSA public key come from build settings
/// (see Config/Shared.xcconfig). Debug builds, and any build without both, never check for updates.
final class UpdaterService {
    private let controller: SPUStandardUpdaterController?

    init() {
        #if DEBUG
        controller = nil
        #else
        let info = Bundle.main.infoDictionary
        let feed = info?["SUFeedURL"] as? String ?? ""
        let key = info?["SUPublicEDKey"] as? String ?? ""
        controller = feed.isEmpty || key.isEmpty
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    var isEnabled: Bool { controller != nil }

    /// Setting this records the choice, so Sparkle doesn't ask on its own later.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
