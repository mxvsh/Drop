import AppKit

/// Watches for file drags in any app and asks for the drop zone when the trigger is met.
///
/// A global mouse-down monitor arms a short-lived poll that runs only while the button is held.
/// The poll reads the drag pasteboard, modifier flags and cursor position. None of these need the
/// Accessibility or Input Monitoring permission.
final class DragMonitor {
    var onReveal: (([URL]) -> Void)?
    var onDragEnded: (() -> Void)?
    /// Drags that start inside Drop's own windows are normally ignored. Onboarding turns this on
    /// so its practice file can be dragged.
    var acceptsLocalDrags: () -> Bool = { false }

    private let settings: AppSettings
    private var mouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var timer: Timer?
    private var baselineChangeCount = 0
    /// nil until a drag starts; empty when the drag carries no files.
    private var draggedFiles: [URL]?
    private var revealed = false
    private var shake = ShakeDetector()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                if self?.acceptsLocalDrags() == true { self?.mouseDown() }
            }
            return event
        }
    }

    func stop() {
        for monitor in [mouseDownMonitor, localMouseDownMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        mouseDownMonitor = nil
        localMouseDownMonitor = nil
        endTracking()
    }

    private func mouseDown() {
        guard !settings.isPaused else { return }
        baselineChangeCount = NSPasteboard(name: .drag).changeCount
        draggedFiles = nil
        revealed = false
        shake.reset()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            endTracking()
            return
        }

        if draggedFiles == nil {
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != baselineChangeCount else { return }
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []
            draggedFiles = urls
        }

        guard let files = draggedFiles, !files.isEmpty, !revealed else { return }

        let shook = settings.isShakeActive && shake.add(NSEvent.mouseLocation)
        if shook || settings.trigger.isPressed(in: NSEvent.modifierFlags) {
            revealed = true
            onReveal?(files)
        }
    }

    private func endTracking() {
        timer?.invalidate()
        timer = nil
        if revealed { onDragEnded?() }
        revealed = false
        draggedFiles = nil
    }
}

/// Detects a quick left-right wiggle of the cursor.
struct ShakeDetector {
    private var samples: [(x: CGFloat, time: TimeInterval)] = []
    private let window: TimeInterval = 0.7
    private let threshold: CGFloat = 28
    private let requiredReversals = 3

    mutating func reset() { samples.removeAll() }

    mutating func add(_ point: NSPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        samples.append((point.x, now))
        samples.removeAll { now - $0.time > window }

        var reversals = 0
        var direction: CGFloat = 0
        var pivot = samples.first?.x ?? point.x
        for sample in samples {
            let delta = sample.x - pivot
            if direction == 0 {
                if abs(delta) > threshold { direction = delta > 0 ? 1 : -1; pivot = sample.x }
            } else if (delta > 0) == (direction > 0) {
                pivot = sample.x
            } else if abs(delta) > threshold {
                reversals += 1
                direction = -direction
                pivot = sample.x
            }
        }
        if reversals >= requiredReversals {
            samples.removeAll()
            return true
        }
        return false
    }
}
