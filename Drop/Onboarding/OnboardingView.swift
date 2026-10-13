import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let onFinish: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            DemoAnimation(keySymbol: settings.trigger == .shakeOnly ? "〰" : settings.trigger.keySymbol)
                .frame(height: 230)

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Welcome to Drop")
                        .font(.system(size: 26, weight: .bold))
                    Text("Convert, compress and keep files without leaving the drag.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, title: "Start dragging any file", detail: "From Finder, the desktop, Mail or any other app.")
                    StepRow(number: 2, title: revealTitle, detail: "Drop appears beside your cursor with actions for that file.")
                    StepRow(number: 3, title: "Drop it on an action", detail: "The result is saved next to the original, ready to drag onward.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    HStack {
                        Text("Reveal with")
                        Spacer()
                        Picker("Reveal with", selection: $settings.trigger) {
                            ForEach(DragTrigger.allCases) { trigger in
                                Text(trigger == .shakeOnly ? trigger.title : "\(trigger.keySymbol)  \(trigger.title)").tag(trigger)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    HStack {
                        Text("Open at login")
                        Spacer()
                        Toggle("Open at login", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { _, enabled in
                                LaunchAtLogin.set(enabled)
                                launchAtLogin = LaunchAtLogin.isEnabled
                            }
                    }
                }
                .font(.system(size: 13))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))

                Button(action: onFinish) {
                    Text("Get Started")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .controlSize(.large)
                .glassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    private var revealTitle: String {
        settings.trigger == .shakeOnly ? "Give it a little shake" : "Hold \(settings.trigger.keySymbol) \(settings.trigger.title)"
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Demo

/// A looping sketch of the gesture: drag a file, hold the key, the panel appears, drop on a tile.
private struct DemoAnimation: View {
    let keySymbol: String

    enum Step: CaseIterable {
        case start, dragging, holding, hovering, dropped
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.42, blue: 0.98), Color(red: 0.55, green: 0.36, blue: 0.95), Color(red: 0.95, green: 0.45, blue: 0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PhaseAnimator(Step.allCases) { step in
                ZStack {
                    MiniPanel(highlight: step == .hovering || step == .dropped, done: step == .dropped)
                        .opacity(step == .start || step == .dragging ? 0 : 1)
                        .offset(x: 60)

                    FileGlyph()
                        .offset(x: fileX(step), y: fileY(step))
                        .scaleEffect(step == .dropped ? 0.3 : 1)
                        .opacity(step == .dropped ? 0 : 1)
                        .rotationEffect(.degrees(step == .start ? 0 : -6))

                    BigKeyCap(symbol: keySymbol, pressed: step == .holding || step == .hovering)
                        .offset(x: -165, y: 62)
                        .opacity(step == .start || step == .dragging ? 0.45 : 1)
                }
            } animation: { step in
                switch step {
                case .start: .easeInOut(duration: 0.5).delay(0.6)
                case .dragging: .easeInOut(duration: 0.7)
                case .holding: .easeInOut(duration: 0.3).delay(0.3)
                case .hovering: .easeInOut(duration: 0.8).delay(0.4)
                case .dropped: .easeInOut(duration: 0.4).delay(0.5)
                }
            }
        }
        .clipped()
    }

    private func fileX(_ step: Step) -> CGFloat {
        switch step {
        case .start: -150
        case .dragging: -90
        case .holding: -80
        case .hovering, .dropped: 18
        }
    }

    private func fileY(_ step: Step) -> CGFloat {
        switch step {
        case .start: 0
        case .dragging, .holding: -14
        case .hovering, .dropped: -22
        }
    }
}

private struct FileGlyph: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)
                .frame(width: 46, height: 58)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            Text("HEIC")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange))
                .padding(.bottom, 8)
        }
    }
}

private struct MiniPanel: View {
    let highlight: Bool
    let done: Bool

    private let tiles: [(String, Color)] = [("PNG", .blue), ("JPEG", .blue), ("WebP", .blue), ("", .green), ("", .teal), ("", .purple)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.9)).frame(width: 18, height: 18)
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.7)).frame(width: 60, height: 6)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 7), count: 3), spacing: 7) {
                ForEach(tiles.indices, id: \.self) { index in
                    let tile = tiles[index]
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.white.opacity(index == 0 && highlight ? 0.55 : 0.22))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tile.1.gradient)
                            .frame(width: 22, height: 22)
                        if index == 0 && done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else if !tile.0.isEmpty {
                            Text(tile.0)
                                .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 0.75))
        )
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }
}

private struct BigKeyCap: View {
    let symbol: String
    let pressed: Bool

    var body: some View {
        Text(symbol)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.25))
            .frame(width: 50, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(pressed ? 0.12 : 0.3), radius: pressed ? 1 : 0, y: pressed ? 1 : 4)
            )
            .offset(y: pressed ? 3 : 0)
    }
}
