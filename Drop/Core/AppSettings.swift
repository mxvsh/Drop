import AppKit
import Observation

/// The modifier (or gesture) that reveals the drop zone while a file is being dragged.
nonisolated enum DragTrigger: String, CaseIterable, Identifiable, Sendable {
    case option, control, command, shift, function, shakeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: "Option"
        case .control: "Control"
        case .command: "Command"
        case .shift: "Shift"
        case .function: "Fn"
        case .shakeOnly: "None — shake only"
        }
    }

    var keySymbol: String {
        switch self {
        case .option: "⌥"
        case .control: "⌃"
        case .command: "⌘"
        case .shift: "⇧"
        case .function: "fn"
        case .shakeOnly: "〰"
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .option: .option
        case .control: .control
        case .command: .command
        case .shift: .shift
        case .function: .function
        case .shakeOnly: nil
        }
    }

    /// What the key already means to Finder during a drag, if anything.
    var conflictNote: String? {
        switch self {
        case .option: "Finder treats Option as “copy” while dragging. Drop stays open once revealed, so let go of the key before dropping elsewhere."
        case .command: "Finder treats Command as “move” while dragging. Drop stays open once revealed, so let go of the key before dropping elsewhere."
        default: nil
        }
    }

    func isPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        guard let flag else { return false }
        return flags.intersection(.deviceIndependentFlagsMask).contains(flag)
    }
}

nonisolated enum OutputLocationKind: String, CaseIterable, Identifiable, Sendable {
    case besideOriginal, downloads, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .besideOriginal: "Next to the original"
        case .downloads: "Downloads"
        case .custom: "Custom folder"
        }
    }
}

nonisolated enum OriginalsPolicy: String, CaseIterable, Identifiable, Sendable {
    case keep, trash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keep: "Keep originals"
        case .trash: "Move originals to Trash"
        }
    }
}

nonisolated enum VideoResolution: String, CaseIterable, Identifiable, Sendable {
    case p720, p1080, p2160
    var id: String { rawValue }
    var title: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p2160: "4K"
        }
    }
}

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var trigger: DragTrigger { didSet { defaults.set(trigger.rawValue, forKey: Key.trigger) } }
    var shakeToReveal: Bool { didSet { defaults.set(shakeToReveal, forKey: Key.shake) } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: Key.paused) } }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) } }

    var outputLocation: OutputLocationKind { didSet { defaults.set(outputLocation.rawValue, forKey: Key.outputLocation) } }
    var customFolderPath: String? { didSet { defaults.set(customFolderPath, forKey: Key.customFolder) } }
    var originals: OriginalsPolicy { didSet { defaults.set(originals.rawValue, forKey: Key.originals) } }
    var copyResultToClipboard: Bool { didSet { defaults.set(copyResultToClipboard, forKey: Key.copyResult) } }
    var revealInFinder: Bool { didSet { defaults.set(revealInFinder, forKey: Key.reveal) } }

    var imageQuality: Double { didSet { defaults.set(imageQuality, forKey: Key.imageQuality) } }
    /// Last resize choice, so the Resize form opens where you left it.
    var resizeUsesPercent: Bool { didSet { defaults.set(resizeUsesPercent, forKey: Key.resizeUsesPercent) } }
    var resizePercent: Double { didSet { defaults.set(resizePercent, forKey: Key.resizePercent) } }
    var videoResolution: VideoResolution { didSet { defaults.set(videoResolution.rawValue, forKey: Key.videoResolution) } }
    var gifFPS: Int { didSet { defaults.set(gifFPS, forKey: Key.gifFPS) } }
    var gifWidth: Int { didSet { defaults.set(gifWidth, forKey: Key.gifWidth) } }

    var disabledActions: Set<String> { didSet { defaults.set(Array(disabledActions), forKey: Key.disabledActions) } }

    init() {
        let d = UserDefaults.standard
        trigger = d.string(forKey: Key.trigger).flatMap(DragTrigger.init) ?? .option
        shakeToReveal = d.bool(forKey: Key.shake)
        isPaused = d.bool(forKey: Key.paused)
        onboardingCompleted = d.bool(forKey: Key.onboarding)
        outputLocation = d.string(forKey: Key.outputLocation).flatMap(OutputLocationKind.init) ?? .besideOriginal
        customFolderPath = d.string(forKey: Key.customFolder)
        originals = d.string(forKey: Key.originals).flatMap(OriginalsPolicy.init) ?? .keep
        copyResultToClipboard = d.bool(forKey: Key.copyResult)
        revealInFinder = d.bool(forKey: Key.reveal)
        imageQuality = d.object(forKey: Key.imageQuality) as? Double ?? 0.8
        resizeUsesPercent = d.object(forKey: Key.resizeUsesPercent) as? Bool ?? true
        resizePercent = d.object(forKey: Key.resizePercent) as? Double ?? 50
        videoResolution = d.string(forKey: Key.videoResolution).flatMap(VideoResolution.init) ?? .p1080
        gifFPS = d.object(forKey: Key.gifFPS) as? Int ?? 15
        gifWidth = d.object(forKey: Key.gifWidth) as? Int ?? 720
        disabledActions = Set(d.stringArray(forKey: Key.disabledActions) ?? [])
    }

    /// The trigger reveals the panel either by key or by shaking; "shake only" forces shaking on.
    var isShakeActive: Bool { shakeToReveal || trigger == .shakeOnly }

    var processingOptions: ProcessingOptions {
        let location: OutputPlanner.Location
        switch outputLocation {
        case .besideOriginal:
            location = .besideOriginal
        case .downloads:
            location = .folder(URL.downloadsDirectory)
        case .custom:
            location = customFolderPath.map { .folder(URL(fileURLWithPath: $0, isDirectory: true)) } ?? .besideOriginal
        }
        return ProcessingOptions(
            imageQuality: imageQuality,
            resize: .scale(resizePercent / 100),
            videoResolution: videoResolution,
            gifFPS: gifFPS,
            gifWidth: gifWidth,
            output: OutputPlanner(location: location)
        )
    }

    private enum Key {
        static let trigger = "drag.trigger"
        static let shake = "drag.shake"
        static let paused = "drag.paused"
        static let onboarding = "onboarding.completed"
        static let outputLocation = "output.location"
        static let customFolder = "output.customFolder"
        static let originals = "output.originals"
        static let copyResult = "output.copyToClipboard"
        static let reveal = "output.revealInFinder"
        static let imageQuality = "image.quality"
        static let resizeUsesPercent = "resize.usesPercent"
        static let resizePercent = "resize.percent"
        static let videoResolution = "video.resolution"
        static let gifFPS = "gif.fps"
        static let gifWidth = "gif.width"
        static let disabledActions = "actions.disabled"
    }
}

nonisolated enum ResizeRequest: Sendable, Equatable {
    /// Both sides multiplied by a factor, e.g. 0.5.
    case scale(Double)
    /// Fit inside a box, keeping proportions.
    case fit(width: Int, height: Int)
    /// Exactly this size, proportions ignored.
    case exact(width: Int, height: Int)
}

/// An immutable snapshot of the settings an action needs, safe to hand to background work.
nonisolated struct ProcessingOptions: Sendable {
    var imageQuality: Double
    var resize: ResizeRequest
    var videoResolution: VideoResolution
    var gifFPS: Int
    var gifWidth: Int
    var output: OutputPlanner
}
