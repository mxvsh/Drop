import Foundation
import Observation

/// The state the drop zone renders. Owned and driven by `DropPanelController`.
@Observable
final class DropSession {
    enum Phase: Equatable {
        /// Mid-drag: action tiles for the dragged files.
        case choosing
        /// A configurable action was chosen; its form is showing.
        case configuring
        /// An action is running.
        case working
        /// Results ready to drag out, or text copied.
        case finished
        case failed
        /// Parked files, open outside a drag.
        case shelf
    }

    var phase: Phase = .choosing
    var selection = DropSelection(urls: [])
    /// Format targets, shown as a row of chips.
    var conversions: [ActionSpec] = []
    /// Everything else, shown as icon tiles.
    var tools: [ActionSpec] = []
    /// The "More" tile was opened, revealing every tool.
    var showsAllTools = false
    /// Describes whatever the dragged file is over; nil shows the default hint.
    var hint: String?
    var options: ProcessingOptions?
    var activeAction: ActionSpec?
    /// The configurable action waiting on its form, and the values being edited.
    var pendingAction: ActionSpec?
    var draft: ActionDraft?
    var progress: Double = 0
    var result: DropResult?
    var errorMessage: String?
    /// A drag from another app is in progress over or near the panel.
    var isDragging = false
}

struct DropResult {
    let action: ActionSpec
    let files: [URL]
    let summary: String
    let copiedText: String?
    /// Positive when the output is smaller than the input.
    let savings: Double?
    /// Facts about `subjects`, shown as a card instead of files to drag out.
    var details: [InfoRow] = []
    var subjects: [URL] = []
}
