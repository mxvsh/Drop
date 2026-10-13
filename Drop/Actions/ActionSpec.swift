import Foundation

nonisolated enum ActionGroup: String, CaseIterable, Sendable {
    case convert, optimize, create, utilities

    var title: String {
        switch self {
        case .convert: "Convert"
        case .optimize: "Optimize"
        case .create: "Create"
        case .utilities: "Utilities"
        }
    }
}

nonisolated struct ActionInput: Sendable {
    let files: [DroppedFile]
    let options: ProcessingOptions
    let progress: @Sendable (Double) -> Void
}

nonisolated enum ActionOutput: Sendable {
    /// New files on disk.
    case files([URL])
    /// Text for the clipboard, with a short description of what was copied.
    case text(String, summary: String)
}

/// Actions that ask for values before running. The panel shows a small form after the drop.
nonisolated enum ActionConfiguration: Sendable {
    case resize, quality, videoResolution, gif
}

/// One target in the drop zone: what it is, when it applies, and the work it does.
nonisolated struct ActionSpec: Identifiable, Sendable {
    let id: String
    /// Short tile label: "PNG", "Compress".
    let title: String
    /// Full name for the status line and Settings: "Convert to PNG".
    let name: String
    let symbol: String
    /// When set, dropping opens a form instead of running straight away.
    let configuration: ActionConfiguration?
    let group: ActionGroup
    /// "Converting to PNG", shown while running.
    let verb: String
    /// "Converted to PNG", shown when done.
    let done: String
    let minCount: Int
    /// The output stands in for the input, so "Move originals to Trash" applies.
    let replacesOriginals: Bool
    /// Whether to report size savings.
    let reportsSavings: Bool
    let detail: @Sendable (ProcessingOptions) -> String
    let isAvailable: @Sendable (DropSelection) -> Bool
    let run: @Sendable (ActionInput) async throws -> ActionOutput

    init(
        id: String,
        title: String,
        name: String,
        detail: @escaping @Sendable (ProcessingOptions) -> String,
        symbol: String,
        configuration: ActionConfiguration? = nil,
        group: ActionGroup,
        verb: String,
        done: String,
        minCount: Int = 1,
        replacesOriginals: Bool = false,
        reportsSavings: Bool = false,
        isAvailable: @escaping @Sendable (DropSelection) -> Bool,
        run: @escaping @Sendable (ActionInput) async throws -> ActionOutput
    ) {
        self.id = id
        self.title = title
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.configuration = configuration
        self.group = group
        self.verb = verb
        self.done = done
        self.minCount = minCount
        self.replacesOriginals = replacesOriginals
        self.reportsSavings = reportsSavings
        self.isAvailable = isAvailable
        self.run = run
    }

    init(
        id: String,
        title: String,
        name: String,
        detail: String,
        symbol: String,
        configuration: ActionConfiguration? = nil,
        group: ActionGroup,
        verb: String,
        done: String,
        minCount: Int = 1,
        replacesOriginals: Bool = false,
        reportsSavings: Bool = false,
        isAvailable: @escaping @Sendable (DropSelection) -> Bool,
        run: @escaping @Sendable (ActionInput) async throws -> ActionOutput
    ) {
        self.init(
            id: id, title: title, name: name, detail: { _ in detail }, symbol: symbol, configuration: configuration, group: group,
            verb: verb, done: done, minCount: minCount, replacesOriginals: replacesOriginals,
            reportsSavings: reportsSavings, isAvailable: isAvailable, run: run
        )
    }

    var isConversion: Bool { group == .convert }
}
