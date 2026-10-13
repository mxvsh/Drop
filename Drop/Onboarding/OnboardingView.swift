import AppKit
import SwiftUI

/// First-run guide: a few short pages, only the choices that matter now. Everything else stays in Settings.
struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let updater: UpdaterService
    let practice: PracticeSession
    let folders: FolderAccess
    let onShowMenuBarIcon: () -> Void
    let onSizeChange: (CGSize) -> Void
    let onFinish: () -> Void

    enum Page: Int, CaseIterable {
        case welcome, practice, folders, menuBar, ready
    }

    @State private var page: Page = .welcome
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var checksForUpdates = true

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(height: 168)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if page != .ready {
                        Button("Skip") { finish() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.black.opacity(0.15)))
                            .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .id(page)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 24)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: page)
        .onChange(of: page) { _, newPage in
            practice.isActive = newPage == .practice
            if newPage == .menuBar { onShowMenuBarIcon() }
        }
        .onAppear { practice.prepareSample() }
        .onDisappear { practice.isActive = false }
    }

    // MARK: Pages

    @ViewBuilder
    private var hero: some View {
        switch page {
        case .welcome:
            DemoAnimation(keySymbol: triggerSymbol)
        case .practice:
            ZStack {
                OnboardingBackdrop()
                PracticeCard(practice: practice)
            }
        case .folders:
            HeroSymbol(symbol: "folder.badge.person.crop")
        case .menuBar:
            ZStack {
                OnboardingBackdrop()
                MenuBarMock()
            }
        case .ready:
            HeroSymbol(symbol: "checkmark.seal.fill")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .welcome:
            PageHeader(
                title: "Welcome to Drop",
                subtitle: "Convert, compress and keep files without leaving the drag."
            )
            HStack(spacing: 8) {
                StepCard(number: 1, symbol: "hand.draw", text: "Drag any file")
                StepCard(number: 2, symbol: "keyboard", text: settings.trigger == .shakeOnly ? "Shake it" : "Hold \(settings.trigger.keySymbol) \(settings.trigger.title)")
                StepCard(number: 3, symbol: "arrow.down.to.line", text: "Drop on an action")
            }

        case .practice:
            PageHeader(title: "Try it now", subtitle: "Drag the sample photo above anywhere, then \(revealPhrase).")
            VStack(alignment: .leading, spacing: 10) {
                ChecklistRow(done: practice.hasDragged, text: "Start dragging the sample photo")
                ChecklistRow(done: practice.hasRevealed, text: settings.trigger == .shakeOnly ? "Give it a little shake" : "Hold \(settings.trigger.keySymbol) \(settings.trigger.title) while dragging")
                ChecklistRow(done: practice.hasDropped, text: "Drop it on any action")
            }
            if practice.isComplete {
                Label("That's all there is to it.", systemImage: "hand.thumbsup.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }

        case .folders:
            PageHeader(
                title: "Allow folder access",
                subtitle: "macOS asks before any app reads or saves files in these folders. Allow Drop now so it doesn't ask in the middle of a drag."
            )
            VStack(spacing: 8) {
                ForEach(folders.folders) { folder in
                    FolderRow(folder: folder)
                }
            }
            HStack(spacing: 10) {
                if folders.anyDenied {
                    Button("Open Privacy Settings") { FolderAccess.openFilesAndFoldersSettings() }
                } else if !folders.allGranted {
                    Button {
                        Task { await folders.request() }
                    } label: {
                        Text(folders.isRequesting ? "Waiting for macOS…" : "Allow Access")
                    }
                    .disabled(folders.isRequesting)
                }
                Spacer()
                Button("Full Disk Access…") { FolderAccess.openFullDiskAccessSettings() }
                    .buttonStyle(.link)
                    .help("Optional. Needed only for files on external or network drives.")
            }
            .controlSize(.regular)

        case .menuBar:
            PageHeader(
                title: "Drop lives in your menu bar",
                subtitle: "There's no Dock icon. Click the drop in the menu bar for the Shelf, Settings and this guide."
            )
            if #available(macOS 26.0, *) {
                Label {
                    Text("Don't see it? Check that Drop is allowed in System Settings → Menu Bar.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Button("Show me again") { onShowMenuBarIcon() }
                .buttonStyle(.link)

        case .ready:
            PageHeader(title: "You're all set", subtitle: "A few choices to start with. Everything else is in Settings.")
            VStack(spacing: 0) {
                SettingRow(title: "Reveal Drop with") {
                    Picker("Reveal Drop with", selection: $settings.trigger) {
                        ForEach(DragTrigger.allCases) { trigger in
                            Text(trigger == .shakeOnly ? trigger.title : "\(trigger.keySymbol)  \(trigger.title)").tag(trigger)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider().padding(.leading, 14)
                SettingRow(title: "Open at login") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if updater.isEnabled {
                    Divider().padding(.leading, 14)
                    SettingRow(title: "Check for updates automatically") {
                        Toggle("Check for updates automatically", isOn: $checksForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == page ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: item == page ? 16 : 6, height: 6)
                }
            }
            Spacer()
            if page != .welcome {
                Button("Back") { move(by: -1) }
                    .keyboardShortcut(.cancelAction)
            }
            Button(primaryTitle) {
                if page == .ready { finish() } else { move(by: 1) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }

    private var primaryTitle: String {
        switch page {
        case .welcome: "Get Started"
        case .practice: practice.isComplete ? "Continue" : "Skip for Now"
        case .folders: folders.allGranted || folders.wasAsked ? "Continue" : "Not Now"
        case .menuBar: "Continue"
        case .ready: "Start Using Drop"
        }
    }

    private func move(by offset: Int) {
        guard let next = Page(rawValue: page.rawValue + offset) else { return }
        page = next
    }

    private func finish() {
        if launchAtLogin != LaunchAtLogin.isEnabled { LaunchAtLogin.set(launchAtLogin) }
        if updater.isEnabled { updater.automaticallyChecksForUpdates = checksForUpdates }
        onFinish()
    }

    private var triggerSymbol: String { settings.trigger == .shakeOnly ? "〰" : settings.trigger.keySymbol }

    private var revealPhrase: String {
        settings.trigger == .shakeOnly ? "give it a little shake" : "hold \(settings.trigger.keySymbol) \(settings.trigger.title)"
    }
}

// MARK: - Building blocks

/// The shared gradient behind every page's hero.
struct OnboardingBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.36, green: 0.42, blue: 0.98), Color(red: 0.55, green: 0.36, blue: 0.95), Color(red: 0.95, green: 0.45, blue: 0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct HeroSymbol: View {
    let symbol: String

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        }
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StepCard: View {
    let number: Int
    let symbol: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

private struct ChecklistRow: View {
    let done: Bool
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.5))
                .contentTransition(.opacity)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(done ? .secondary : .primary)
        }
        .animation(.easeOut(duration: 0.2), value: done)
    }
}

private struct FolderRow: View {
    let folder: FolderAccess.Folder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.symbol)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(folder.name)
                .font(.system(size: 13))
            Spacer()
            switch folder.status {
            case .notAsked:
                Text("Not allowed yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            case .denied:
                Label("Denied", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// The sample photo, draggable like a real file in Finder.
private struct PracticeCard: View {
    let practice: PracticeSession

    var body: some View {
        VStack(spacing: 8) {
            FileThumbnail(url: practice.sampleURL, size: 84)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            Text(practice.sampleURL.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.2)))
            Text(practice.hasDragged ? " " : "Drag me")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .contentShape(Rectangle())
        .overlay(FileDragSource(urls: [practice.sampleURL], onDragStarted: { practice.hasDragged = true }))
    }
}

/// A sketch of the menu bar with Drop's icon picked out.
private struct MenuBarMock: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Spacer()
                ForEach(["wifi", "battery.75percent", "magnifyingglass"], id: \.self) { symbol in
                    Image(systemName: symbol).foregroundStyle(.white.opacity(0.6))
                }
                Image(systemName: "drop.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.3)))
                Text("Mon 9:41")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(.white.opacity(0.15))
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: 52)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 34)
    }
}

// MARK: - Demo

/// A looping sketch of the gesture at fixed sizes: drag a file, hold the key, the panel appears, drop on PNG.
private struct DemoAnimation: View {
    let keySymbol: String

    enum Step: CaseIterable {
        case start, holding, hovering, dropped
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop()
            PhaseAnimator(Step.allCases) { step in
                ZStack {
                    MiniPanel(highlight: step == .hovering, done: step == .dropped)
                        .opacity(step == .start ? 0 : 1)
                        .offset(x: 70)

                    BigKeyCap(symbol: keySymbol, pressed: step == .holding || step == .hovering)
                        .offset(x: -120, y: 42)

                    FileGlyph()
                        .scaleEffect(step == .hovering ? 0.8 : 1)
                        .opacity(step == .dropped ? 0 : 1)
                        .offset(x: step == .start || step == .holding ? -120 : 22, y: step == .start || step == .holding ? -18 : -14)
                }
                .frame(width: 380, height: 150)
            } animation: { step in
                switch step {
                case .start: .easeInOut(duration: 0.4).delay(0.8)
                case .holding: .easeInOut(duration: 0.25).delay(0.5)
                case .hovering: .easeInOut(duration: 0.7).delay(0.3)
                case .dropped: .easeInOut(duration: 0.3).delay(0.5)
                }
            }
        }
    }
}

private struct FileGlyph: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
                .frame(width: 38, height: 48)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            Text("HEIC")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.orange))
                .padding(.bottom, 7)
        }
    }
}

/// A miniature of the real drop zone: chips for formats, tiles for tools.
private struct MiniPanel: View {
    let highlight: Bool
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.6)).frame(width: 54, height: 5)
            }
            HStack(spacing: 6) {
                ForEach(Array(["PNG", "JPEG", "WebP"].enumerated()), id: \.offset) { index, label in
                    let active = index == 0 && (highlight || done)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(active ? 0.95 : 0.22))
                        if index == 0 && done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text(label)
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(active ? Color.accentColor : .white)
                        }
                    }
                    .frame(width: 44, height: 22)
                }
            }
            HStack(spacing: 6) {
                ForEach(["arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "person.and.background.dotted"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.15)))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.75))
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

private struct BigKeyCap: View {
    let symbol: String
    let pressed: Bool

    var body: some View {
        Text(symbol)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.25))
            .frame(width: 40, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(pressed ? 0.1 : 0.28), radius: 0, y: pressed ? 1 : 3)
            )
            .offset(y: pressed ? 2 : 0)
    }
}
