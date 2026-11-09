import SwiftUI

// MARK: - 4 Connect a provider

/// Finds what's already on this Mac (Grok/Codex logins, keys in the Keychain); otherwise offers
/// simple choices that open the real Add Provider sheet on top of the tour.
struct OnboardingProviderStep: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(OnboardingKeys.self) private var keys
    @State private var checking = true
    @State private var ignoreFound = OnboardingStore.debugFresh
    @State private var route: AddProviderRoute?
    @State private var readyBefore: Set<String> = []
    @State private var connected: ProviderInfo?
    @State private var used = false

    private var found: [ProviderInfo] {
        ignoreFound ? [] : config.providers.filter { status.state($0.id).isReady }
    }

    private var enabledIDs: [String] {
        config.enabled(ready: { status.state($0).isReady }).map(\.id)
    }

    private var pending: [ProviderInfo] { found.filter { !enabledIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingArtPanel {
                OnboardingScanArt(found: Set(found.map(\.id)), scanning: checking)
            }
            OnboardingText(title: "Connect a provider", lead: "Where your images come from. One-time setup.") {
                if connected != nil || (!found.isEmpty && (pending.isEmpty || used)) {
                    OnboardingBadge(text: "Ready")
                } else if !found.isEmpty {
                    OnboardingBadge(text: "Found on this Mac")
                }
            } content: {
                Group {
                    if checking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking on this Mac…").foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    } else if let connected {
                        success("\(connected.label) is ready.")
                    } else if !found.isEmpty {
                        foundList
                    } else {
                        choices
                    }
                }
                .animation(.smooth(duration: 0.3), value: checking)
            }
        }
        .sheet(item: $route, onDismiss: sheetClosed) { route in
            AddProviderSheet(route: route).dismissOnQuit()
        }
        .onChange(of: route) { _, r in keys.sheetOpen = r != nil }
        .task {
            await status.refresh(config.providers)
            withAnimation(.smooth(duration: 0.35)) { checking = false }
        }
    }

    // Found on this Mac: green checks and one tap to use them.
    private var foundList: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(found.prefix(3).enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(p.label).font(.system(size: 14, weight: .medium))
                        Pill(text: p.kind.isSubscription ? "Subscription" : "API key")
                        Spacer(minLength: 0)
                    }
                    .onboardingEnter(i)
                }
                if found.count > 3 {
                    Text("+ \(found.count - 3) more").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                if pending.isEmpty || used {
                    Label("You're connected.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Button { useFound() } label: { Label("Use \(pending.count == 1 ? "this" : "these")", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                }
                Button("Add another") { open(.add) }.buttonStyle(.link).foregroundStyle(Theme.accent)
            }
            .onboardingEnter(min(found.count, 3))
        }
    }

    // Nothing found: pick by what the person already pays for.
    private var choices: some View {
        HStack(spacing: 10) {
            OnboardingChoice(symbol: "bubble.left.and.bubble.right.fill", color: ProviderStyle.color("codex"),
                             title: "I pay for ChatGPT", detail: "Use your plan") { open(.setup("codex")) }
                .onboardingEnter(0)
            OnboardingChoice(symbol: "bolt.fill", color: ProviderStyle.color("grok"),
                             title: "I pay for Grok", detail: "Use your plan") { open(.setup("grok")) }
                .onboardingEnter(1)
            OnboardingChoice(symbol: "key.fill", color: ProviderStyle.color("openai"),
                             title: "I have an API key", detail: "OpenAI, Gemini & more") { open(.add) }
                .onboardingEnter(2)
        }
    }

    private func success(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
                    .onboardingPop()
                Text(text).font(.system(size: 15, weight: .semibold))
            }
            Button("Add another") { open(.add) }.buttonStyle(.link).foregroundStyle(Theme.accent)
        }
    }

    private func open(_ r: AddProviderRoute) {
        readyBefore = Set(config.providers.filter { status.state($0.id).isReady }.map(\.id))
        route = r
    }

    private func useFound() {
        config.setEnabled(enabledIDs + pending.map(\.id).filter { !enabledIDs.contains($0) })
        withAnimation(.smooth(duration: 0.3)) { used = true }
    }

    private func sheetClosed() {
        keys.sheetOpen = false
        Task {
            await status.refresh(config.providers)
            let now = config.providers.filter { status.state($0.id).isReady }
            withAnimation(.smooth(duration: 0.35)) {
                ignoreFound = false
                connected = now.first { !readyBefore.contains($0.id) }
            }
        }
    }
}

/// A big friendly choice card.
private struct OnboardingChoice: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconBadge(symbol: symbol, color: color, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(hovering ? Theme.accent.opacity(0.07) : Theme.well, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hovering ? Theme.accent.opacity(0.5) : Color.primary.opacity(0.05)))
            .offset(y: hovering ? -1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A Mac with a pulsing scan; provider chips pop in around it and turn green when found.
private struct OnboardingScanArt: View {
    let found: Set<String>
    let scanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let chips: [(id: String, x: CGFloat, y: CGFloat)] = [
        ("grok", -190, -40), ("codex", -175, 42), ("openai", 180, -46), ("gemini", 190, 34), ("xai", 0, -78),
    ]

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<2) { i in
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 110, height: 110)
                        .phaseAnimator([false, true]) { v, out in
                            v.scaleEffect(out ? 2.3 : 0.9).opacity(out ? 0 : 0.9)
                        } animation: { out in out ? .easeOut(duration: 2.4).delay(Double(i) * 1.2) : .linear(duration: 0) }
                }
            }
            Image(systemName: "laptopcomputer")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 104, height: 84)
                .card(padding: 0, radius: 22)
                .shadow(color: Theme.accent.opacity(0.15), radius: 16, y: 6)
                .overlay(alignment: .bottomTrailing) {
                    if scanning {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent, in: Circle())
                            .offset(x: 8, y: 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .onboardingFloat(3, duration: 3)
            ForEach(Array(chips.enumerated()), id: \.element.id) { i, chip in
                let isFound = found.contains(chip.id)
                HStack(spacing: 6) {
                    if isFound {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle().fill(ProviderStyle.color(chip.id)).frame(width: 8, height: 8)
                    }
                    Text(ProviderStyle.label(chip.id))
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isFound ? Color.green.opacity(0.5) : Color.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
                .opacity(scanning || isFound || found.isEmpty ? 1 : 0.55)
                .onboardingFloat(4, duration: 2.6 + Double(i) * 0.35)
                .offset(x: chip.x, y: chip.y)
                .onboardingPop(0.15 + Double(i) * 0.1)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isFound)
            }
        }
        .animation(.smooth(duration: 0.3), value: scanning)
    }
}

// MARK: - 5 Connect your AI agents

/// Shows the command line tool and agent skills on this Mac; one button installs everything.
struct OnboardingAgentsStep: View {
    @Environment(Installer.self) private var installer
    @State private var working: Item?
    @State private var running = false

    enum Item: Hashable { case cli, claude, codex }

    private var cliOK: Bool { installer.cli.isOK && installer.inPath != false }
    private func skill(_ t: SkillTarget) -> InstallState { installer.skills[t] ?? .checking }
    private var available: [SkillTarget] {
        SkillTarget.allCases.filter { if case .unavailable = skill($0) { false } else { true } }
    }
    private var allDone: Bool {
        cliOK && available.allSatisfy { skill($0).isOK }
    }
    private var checking: Bool { installer.cli == .checking }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingArtPanel { OnboardingTerminalArt() }
            OnboardingText(title: "Connect your AI agents", lead: "Let Claude Code and Codex make images for you.") {
                if allDone && !checking { OnboardingBadge(text: "All set") }
            } content: {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        row(.cli, title: "Command line tool", state: cliState, index: 0)
                        row(.claude, title: "Claude Code", state: skill(.claude), index: 1)
                        row(.codex, title: "Codex", state: skill(.codex), index: 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 10) {
                        if allDone && !checking {
                            Label("Ready to go", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.green)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        } else {
                            Button { setUpEverything() } label: {
                                HStack(spacing: 6) {
                                    if running { ProgressView().controlSize(.small) }
                                    Text(running ? "Setting up…" : "Set up everything")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(running || checking)
                        }
                        if installer.python == .missing {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Python is missing.").font(.callout.weight(.medium)).foregroundStyle(.orange)
                                Button("Install it") { installer.installCommandLineTools() }.buttonStyle(.link).foregroundStyle(Theme.accent)
                            }
                        }
                        if let error = installer.lastError, !running {
                            Text(error).font(.caption).foregroundStyle(.red).lineLimit(2).multilineTextAlignment(.trailing)
                        }
                    }
                    .frame(width: 180, alignment: .trailing)
                    .onboardingEnter(3)
                }
                .animation(.smooth(duration: 0.3), value: allDone)
            }
        }
        .task { await installer.refresh() }
    }

    private var cliState: InstallState {
        if case .installed = installer.cli, installer.inPath == false { return .missing }
        return installer.cli
    }

    private func row(_ item: Item, title: String, state: InstallState, index: Int) -> some View {
        HStack(spacing: 10) {
            Group {
                if working == item {
                    ProgressView().controlSize(.small)
                } else {
                    switch state {
                    case .installed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    case .checking: ProgressView().controlSize(.mini)
                    case .unavailable: Image(systemName: "minus.circle").foregroundStyle(.tertiary)
                    case .outdated: Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
                    case .missing, .custom: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 16))
            .frame(width: 20)
            Text(title).font(.system(size: 14, weight: .medium))
                .foregroundStyle(isUnavailable(state) ? .secondary : .primary)
            Text(detail(state)).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(height: 26)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state)
        .onboardingEnter(index)
    }

    private func isUnavailable(_ s: InstallState) -> Bool { if case .unavailable = s { true } else { false } }

    private func detail(_ s: InstallState) -> String {
        switch s {
        case .installed: "Installed"
        case .outdated: "Update"
        case .unavailable: "Not on this Mac"
        case .missing, .custom: "Not set up"
        case .checking: ""
        }
    }

    private func setUpEverything() {
        running = true
        installer.lastError = nil
        Task {
            if !installer.cli.isOK {
                working = .cli
                await installer.installCLI()
            }
            if installer.inPath == false {
                working = .cli
                await installer.addToPath()
            }
            for t in available where !skill(t).isOK {
                working = t == .claude ? .claude : .codex
                try? await Task.sleep(for: .milliseconds(250))
                await installer.installSkill(t)
            }
            withAnimation(.smooth(duration: 0.3)) {
                working = nil
                running = false
            }
        }
    }
}

/// A terminal typing an imagegenkit command; the image pops out next to it. Loops.
private struct OnboardingTerminalArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    private let command = "imagegenkit draft \"robot sticker\""

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 6 : context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 7)
            let typed = Int(max(0, min(Double(command.count), (t - 0.4) * 24)))
            let output = t > 2.6
            let shown = t > 3.0 && t < 6.6
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach([Color(light: 0xFF5F57, dark: 0xFF5F57), Color(light: 0xFEBC2E, dark: 0xFEBC2E),
                                 Color(light: 0x28C840, dark: 0x28C840)], id: \.self) { Circle().fill($0).frame(width: 9, height: 9) }
                        Spacer()
                        Text("Claude Code").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.bottom, 12)
                    (Text("> ").foregroundStyle(Color(light: 0xD97757, dark: 0xD97757))
                        + Text("make a robot sticker").foregroundStyle(.white.opacity(0.85)))
                    (Text("$ ").foregroundStyle(.green)
                        + Text(String(command.prefix(typed))).foregroundStyle(.white)
                        + Text(typed < command.count && Int(t * 2.5) % 2 == 0 ? "▌" : " ").foregroundStyle(.white.opacity(0.7)))
                        .padding(.top, 6)
                    Text("✓ Saved robot-sticker.png · Grok")
                        .foregroundStyle(.green.opacity(0.9))
                        .opacity(output ? 1 : 0)
                        .padding(.top, 6)
                }
                .font(.system(size: 11.5, design: .monospaced))
                .frame(width: 290, height: 116, alignment: .topLeading)
                .padding(14)
                .background(Color(light: 0x1C1C1F, dark: 0x111113), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)

                OnboardingSampleImage(sample: .robot, height: 118)
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)
                    .rotationEffect(.degrees(shown ? 3 : -6))
                    .animation(.spring(response: 0.45, dampingFraction: 0.65), value: shown)
            }
        }
        .onboardingFloat(3, duration: 3.4)
    }
}
