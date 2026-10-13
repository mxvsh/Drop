import AppKit
import SwiftUI

// MARK: - General

struct GeneralPane: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Drag any file, then \(triggerPhrase)")
                            .font(.headline)
                        Text("Drop appears next to the cursor with actions for that file.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Reveal Drop with", selection: $settings.trigger) {
                    ForEach(DragTrigger.allCases) { trigger in
                        Text(trigger == .shakeOnly ? trigger.title : "\(trigger.keySymbol)  \(trigger.title)").tag(trigger)
                    }
                }
                Toggle("Also reveal by shaking the cursor", isOn: $settings.shakeToReveal)
                    .disabled(settings.trigger == .shakeOnly)
            } header: {
                Text("Activation")
            } footer: {
                if let note = settings.trigger.conflictNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("App") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                Toggle("Pause Drop", isOn: $settings.isPaused)
            }
        }
        .formStyle(.grouped)
    }

    private var triggerPhrase: String {
        switch settings.trigger {
        case .shakeOnly: "shake it"
        default: "hold \(settings.trigger.keySymbol) \(settings.trigger.title)"
        }
    }
}

// MARK: - Output

struct OutputPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Save results", selection: $settings.outputLocation) {
                    ForEach(OutputLocationKind.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.outputLocation) { _, location in
                    if location == .custom && settings.customFolderPath == nil { chooseFolder() }
                }
                if settings.outputLocation == .custom {
                    LabeledContent("Folder") {
                        HStack(spacing: 8) {
                            Text(settings.customFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") { chooseFolder() }
                        }
                    }
                }
                Picker("Originals", selection: $settings.originals) {
                    ForEach(OriginalsPolicy.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Saving")
            } footer: {
                Text("Moving originals to the Trash applies to conversions, compression and resizing. Merging, zipping and extracting always keep the originals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("After saving") {
                Toggle("Copy results to the clipboard", isOn: $settings.copyResultToClipboard)
                Toggle("Reveal results in Finder", isOn: $settings.revealInFinder)
            }

            Section("Images") {
                LabeledContent("Quality") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.imageQuality, in: 0.4...1, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int((settings.imageQuality * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("Video") {
                Picker("Compress to", selection: $settings.videoResolution) {
                    ForEach(VideoResolution.allCases) { Text($0.title).tag($0) }
                }
                Picker("GIF frame rate", selection: $settings.gifFPS) {
                    ForEach([10, 12, 15, 20, 24, 30], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("GIF width", selection: $settings.gifWidth) {
                    ForEach([360, 480, 640, 720, 960, 1080], id: \.self) { Text("\($0) px").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Drop saves results"
        if panel.runModal() == .OK, let url = panel.url {
            settings.customFolderPath = url.path
        } else if settings.customFolderPath == nil {
            settings.outputLocation = .besideOriginal
        }
    }
}

// MARK: - Actions

struct ActionsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Text("Drop shows only the actions that fit the files you drag. Turn off any you never use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(ActionGroup.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(ActionCatalog.all.filter { $0.group == group }) { action in
                        Toggle(isOn: enabledBinding(action.id)) {
                            HStack(spacing: 10) {
                                ActionIcon(action: action, size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(action.name)
                                    Text("\(scope(of: action)) · \(action.detail(settings.processingOptions))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding {
            !settings.disabledActions.contains(id)
        } set: { enabled in
            if enabled { settings.disabledActions.remove(id) } else { settings.disabledActions.insert(id) }
        }
    }

    private func scope(of action: ActionSpec) -> String {
        switch action.id.split(separator: ".").first {
        case "image", "images": "Images"
        case "pdf": "PDFs"
        case "video": "Videos"
        case "audio": "Audio"
        case "text": "Images & PDFs"
        default: "Any file"
        }
    }
}

// MARK: - About

struct AboutPane: View {
    let updater: UpdaterService

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("Drop")
                    .font(.system(size: 24, weight: .bold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if updater.isEnabled {
                Button("Check for Updates…") { updater.checkForUpdates() }
            }
            Text("Convert, compress and keep files without leaving the drag.\nEverything runs on your Mac. Nothing is uploaded.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
