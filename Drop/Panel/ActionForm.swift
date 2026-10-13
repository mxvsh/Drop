import Observation
import SwiftUI

/// Values the user picks for a configurable action. Prefilled from last time and from the file itself.
@Observable
final class ActionDraft {
    let configuration: ActionConfiguration

    var usesPercent: Bool
    var percent: Double
    private(set) var width: Int
    private(set) var height: Int
    var keepsAspect = true {
        didSet { if keepsAspect { setWidth(width) } }
    }
    /// Upright pixel size of the first file, when it's an image.
    let originalSize: (width: Int, height: Int)?

    var quality: Double
    var videoResolution: VideoResolution
    var gifFPS: Int
    var gifWidth: Int

    init(configuration: ActionConfiguration, settings: AppSettings, selection: DropSelection) {
        self.configuration = configuration
        usesPercent = settings.resizeUsesPercent
        percent = settings.resizePercent
        originalSize = selection.files.first.flatMap { ImageEngine.pixelSize(of: $0.url) }
        width = originalSize?.width ?? 1920
        height = originalSize?.height ?? 1080
        quality = settings.imageQuality
        videoResolution = settings.videoResolution
        gifFPS = settings.gifFPS
        gifWidth = settings.gifWidth
    }

    private var aspect: Double {
        guard let size = originalSize, size.height > 0 else { return Double(width) / Double(max(height, 1)) }
        return Double(size.width) / Double(size.height)
    }

    func setWidth(_ value: Int) {
        width = max(1, value)
        if keepsAspect { height = max(1, Int((Double(width) / aspect).rounded())) }
    }

    func setHeight(_ value: Int) {
        height = max(1, value)
        if keepsAspect { width = max(1, Int((Double(height) * aspect).rounded())) }
    }

    var resizeRequest: ResizeRequest {
        if usesPercent { return .scale(percent / 100) }
        return keepsAspect ? .fit(width: width, height: height) : .exact(width: width, height: height)
    }

    /// "2016 × 1512" for the first image, so the result is never a surprise.
    var resizePreview: String? {
        guard let size = originalSize else { return nil }
        let target: (Int, Int)
        switch resizeRequest {
        case .scale(let factor):
            target = (Int((Double(size.width) * factor).rounded()), Int((Double(size.height) * factor).rounded()))
        case .fit(let w, let h):
            let factor = min(Double(w) / Double(size.width), Double(h) / Double(size.height))
            target = (Int((Double(size.width) * factor).rounded()), Int((Double(size.height) * factor).rounded()))
        case .exact(let w, let h):
            target = (w, h)
        }
        return "\(target.0) × \(target.1) px"
    }

    var isValid: Bool {
        switch configuration {
        case .resize: usesPercent ? (1...1000).contains(percent) : width > 0 && height > 0
        case .quality, .videoResolution, .gif: true
        }
    }

    func apply(to options: inout ProcessingOptions) {
        options.resize = resizeRequest
        options.imageQuality = quality
        options.videoResolution = videoResolution
        options.gifFPS = gifFPS
        options.gifWidth = gifWidth
    }

    /// The next form opens with these values.
    func remember(in settings: AppSettings) {
        switch configuration {
        case .resize:
            settings.resizeUsesPercent = usesPercent
            settings.resizePercent = percent
        case .quality:
            settings.imageQuality = quality
        case .videoResolution:
            settings.videoResolution = videoResolution
        case .gif:
            settings.gifFPS = gifFPS
            settings.gifWidth = gifWidth
        }
    }
}

// MARK: - Form

struct ActionFormView: View {
    let action: ActionSpec
    @Bindable var draft: ActionDraft
    let selection: DropSelection
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ActionIcon(action: action, size: 32, isTargeted: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            fields

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(Theme.padding)
    }

    private var subtitle: String {
        guard draft.configuration == .resize, let size = draft.originalSize, selection.count == 1 else {
            return selection.title
        }
        return "\(selection.title) · \(size.width) × \(size.height)"
    }

    private var confirmTitle: String {
        switch draft.configuration {
        case .resize: "Resize"
        case .quality, .videoResolution: "Compress"
        case .gif: "Make GIF"
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch draft.configuration {
        case .resize: resizeFields
        case .quality: qualityFields
        case .videoResolution: videoFields
        case .gif: gifFields
        }
    }

    // MARK: Resize

    private var resizeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $draft.usesPercent) {
                Text("Percent").tag(true)
                Text("Pixels").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if draft.usesPercent {
                HStack(spacing: 6) {
                    ForEach([25, 50, 75], id: \.self) { value in
                        OptionChip(title: "\(value)%", isSelected: Int(draft.percent) == value) {
                            draft.percent = Double(value)
                        }
                    }
                    Spacer(minLength: 8)
                    NumberField(value: Int(draft.percent)) { draft.percent = Double($0) }
                    Text("%").foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text("W").foregroundStyle(.secondary)
                    NumberField(value: draft.width) { draft.setWidth($0) }
                    Button {
                        draft.keepsAspect.toggle()
                    } label: {
                        Image(systemName: draft.keepsAspect ? "lock.fill" : "lock.open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(draft.keepsAspect ? Color.accentColor : .secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(draft.keepsAspect ? "Proportions locked" : "Proportions unlocked")
                    Text("H").foregroundStyle(.secondary)
                    NumberField(value: draft.height) { draft.setHeight($0) }
                    Text("px").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            if let preview = draft.resizePreview {
                Text(selection.count > 1 ? "First image becomes \(preview)" : "Becomes \(preview)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    // MARK: Quality

    private var qualityFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach([("Smallest", 0.5), ("Balanced", 0.7), ("Best", 0.85)], id: \.0) { title, value in
                    OptionChip(title: title, isSelected: abs(draft.quality - value) < 0.001) { draft.quality = value }
                }
            }
            HStack(spacing: 10) {
                Slider(value: $draft.quality, in: 0.1...1, step: 0.05)
                    .controlSize(.small)
                Text("\(Int((draft.quality * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    // MARK: Video

    private var videoFields: some View {
        Picker("Resolution", selection: $draft.videoResolution) {
            ForEach(VideoResolution.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: GIF

    private var gifFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledRow(title: "Width") {
                Picker("Width", selection: $draft.gifWidth) {
                    ForEach([480, 720, 1080], id: \.self) { Text("\($0) px").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            LabeledRow(title: "Frame rate") {
                Picker("Frame rate", selection: $draft.gifFPS) {
                    ForEach([10, 15, 24], id: \.self) { Text("\($0) fps").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text("Uses the first \(Int(MediaEngine.maxGIFSeconds)) seconds at most")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }
}

// MARK: - Pieces

private struct OptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.8)))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(hovering ? Theme.surfaceHover : Theme.surface))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: isSelected)
    }
}

private struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content
        }
    }
}

/// A small integer field that updates live as you type and tolerates an empty field mid-edit.
private struct NumberField: View {
    let value: Int
    let onChange: (Int) -> Void

    @State private var text = ""

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12).monospacedDigit())
            .frame(width: 58)
            .onAppear { text = "\(value)" }
            .onChange(of: text) { _, newText in
                let digits = newText.filter(\.isNumber)
                if digits != newText { text = digits }
                if let number = Int(digits), number != value { onChange(number) }
            }
            .onChange(of: value) { _, newValue in
                if Int(text) != newValue { text = "\(newValue)" }
            }
    }
}
