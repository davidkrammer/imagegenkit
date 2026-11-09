import SwiftUI

/// Step 2: a hands-on Generate demo on the bundled samples. No API calls, no cost.
struct OnboardingDemoStep: View {
    enum Target: Hashable { case chip, provider, generate }
    enum Phase { case idle, working, done }

    private static let providers = ["grok", "openai", "gemini"]
    private static let ideas: [OnboardingSample] = [.nook, .robot, .ramen]

    @State private var prompt = ""
    @State private var provider: String?
    @State private var phase: Phase = .idle
    @State private var progress = 0.0
    @State private var result: OnboardingSample?
    @State private var hint: String?
    @State private var shakes = 0
    @State private var cursor = Cursor()
    @State private var cursorTask: Task<Void, Never>?
    @State private var showing = false  // "Show me" is running
    @FocusState private var promptFocused: Bool
    @Environment(OnboardingKeys.self) private var keys
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Cursor {
        var target: Target = .chip
        var offset = CGSize(width: 60, height: 40)
        var opacity = 0.0
        var pressed = false
    }

    private var hasPrompt: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var current: Int { !hasPrompt ? 0 : provider == nil ? 1 : phase != .done ? 2 : 3 }
    private var hintTarget: Target? {
        switch current {
        case 0: .chip
        case 1: .provider
        case 2: phase == .idle ? .generate : nil
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingArtPanel { art }
            OnboardingText(title: "Try it", lead: "A live demo on sample images. Free, nothing is sent.") {
                OnboardingBadge(text: "Demo", color: Theme.accent)
            } content: {
                HStack(alignment: .top, spacing: 24) {
                    checklist.frame(width: 150, alignment: .leading)
                    form
                }
            }
        }
        .overlayPreferenceValue(OnboardingTargetKey.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[cursor.target] {
                    let r = proxy[anchor]
                    OnboardingCursor(pressed: cursor.pressed)
                        .position(x: r.midX + cursor.offset.width + 8, y: r.midY + cursor.offset.height + 11)
                        .opacity(cursor.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            if OnboardingStore.debugAutoplay {
                Task { try? await Task.sleep(for: .seconds(1.2)); showMe() }
            } else {
                startHints(after: 0.9)
            }
        }
        .onDisappear {
            cursorTask?.cancel()
            keys.typing = false
        }
        .onChange(of: promptFocused) { _, focused in keys.typing = focused }
        .onChange(of: prompt) { hint = nil }
        .onChange(of: provider) { hint = nil }
    }

    // MARK: Picture: prompt card → canvas

    private var art: some View {
        let sample = result ?? OnboardingSample.match(prompt)
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "text.cursor").foregroundStyle(Theme.accent)
                    Text("Prompt").foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
                Group {
                    if hasPrompt {
                        Text(prompt) + Text(phase == .idle ? "|" : "").foregroundStyle(Theme.accent)
                    } else {
                        Text("Describe an image…").foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: prompt)
                if phase == .done, let result {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            ProviderBadge(provider: provider ?? "grok")
                            Pill(text: result.size)
                        }
                        Pill(text: "$0.00 · demo", color: .green)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let provider {
                    ProviderBadge(provider: provider).transition(.opacity)
                }
            }
            .frame(width: 186, alignment: .leading)
            .card(padding: 14)
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)

            Image(systemName: phase == .working ? "sparkles" : "arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(phase == .idle ? Color.secondary : Theme.accent)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: phase == .working && !reduceMotion)
                .frame(width: 20)

            OnboardingDemoCanvas(sample: sample, phase: phase, progress: progress)
                .frame(width: 172 * 16 / 9 * 0.82, height: 172)
        }
        .padding(.horizontal, 28)
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 13) {
            OnboardingCheckRow(number: 1, title: "Write a prompt", state: state(0)).onboardingEnter(0)
            OnboardingCheckRow(number: 2, title: "Pick a provider", state: state(1)).onboardingEnter(1)
            OnboardingCheckRow(number: 3, title: "Generate", state: state(2)).onboardingEnter(2)
        }
        .padding(.top, 4)
    }

    private func state(_ i: Int) -> OnboardingCheckRow.State {
        i < current ? .done : i == current ? .current : .upcoming
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Describe an image…", text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($promptFocused)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(promptFocused ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
                .disabled(phase != .idle || showing)
                .onSubmit(generate)

            HStack(spacing: 6) {
                ForEach(Self.ideas) { idea in
                    OnboardingChip(selected: prompt == idea.prompt) {
                        Label(idea.chip, systemImage: "lightbulb").labelStyle(.titleAndIcon)
                    } action: {
                        userActed()
                        prompt = idea.prompt
                    }
                    .disabled(phase != .idle)
                    .onboardingTarget(idea == .nook ? .chip : nil)
                }
            }

            HStack(spacing: 6) {
                ForEach(Self.providers, id: \.self) { id in
                    OnboardingChip(selected: provider == id) {
                        HStack(spacing: 5) {
                            Circle().fill(ProviderStyle.color(id)).frame(width: 7, height: 7)
                            Text(ProviderStyle.label(id))
                        }
                    } action: {
                        userActed()
                        withAnimation(.snappy(duration: 0.2)) { provider = id }
                    }
                    .disabled(phase != .idle)
                    .onboardingTarget(id == "grok" ? .provider : nil)
                }
                Spacer(minLength: 6)
                if phase == .done {
                    Button { playAgain() } label: { Label("Play again", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PrimaryButtonStyle())
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Button {
                        userActed()
                        generate()
                    } label: { Label("Generate", systemImage: "sparkles") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(phase == .working)
                        .opacity(phase == .working ? 0.6 : 1)
                        .onboardingTarget(.generate)
                        .modifier(OnboardingShake(shakes: CGFloat(shakes)))
                }
            }
            .padding(.top, 3)

            HStack(spacing: 6) {
                if let hint {
                    Image(systemName: "hand.point.up.left.fill").foregroundStyle(.orange)
                    Text(hint).foregroundStyle(.primary)
                } else if phase == .working {
                    Text("Generating…").foregroundStyle(.secondary)
                } else if phase == .done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("That's it. The real one works the same.").foregroundStyle(.secondary)
                } else {
                    Button(showing ? "Showing…" : "Show me") { showMe() }
                        .buttonStyle(.link)
                        .disabled(showing)
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
            .frame(height: 18)
            .animation(.easeOut(duration: 0.2), value: hint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.25), value: phase)
    }

    // MARK: Actions

    private func generate() {
        guard phase == .idle else { return }
        if !hasPrompt {
            fail("Write a prompt first, or tap an idea.")
        } else if provider == nil {
            fail("Pick a provider first.")
        } else {
            promptFocused = false
            hint = nil
            phase = .working
            progress = 0
            withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 2.2)) { progress = 1 }
            Task {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 2.3))
                result = OnboardingSample.match(prompt)
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { phase = .done }
            }
        }
    }

    private func fail(_ message: String) {
        hint = message
        withAnimation(.linear(duration: 0.45)) { shakes += 1 }
    }

    private func playAgain() {
        withAnimation(.snappy(duration: 0.3)) {
            prompt = ""
            provider = nil
            result = nil
            progress = 0
            hint = nil
            phase = .idle
        }
        startHints(after: 0.8)
    }

    private func userActed() {
        guard !showing else { return }
        // The hint loop follows the next item by itself; nothing to stop.
    }

    // MARK: Cursor

    /// Points at the next thing to do, again and again, until the demo is done.
    private func startHints(after delay: Double) {
        cursorTask?.cancel()
        guard !reduceMotion else { return }
        cursorTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled {
                guard let target = hintTarget else {
                    withAnimation(.easeOut(duration: 0.3)) { cursor.opacity = 0 }
                    try? await Task.sleep(for: .seconds(0.6))
                    if hintTarget == nil && phase == .done { return }
                    continue
                }
                if promptFocused && target == .chip {
                    try? await Task.sleep(for: .seconds(0.5))
                    continue
                }
                await glide(to: target, from: CGSize(width: 70, height: 46))
                guard !Task.isCancelled else { return }
                await tap()
                try? await Task.sleep(for: .seconds(0.4))
                withAnimation(.easeOut(duration: 0.35)) { cursor.opacity = 0 }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    /// "Show me": the cursor does every step.
    private func showMe() {
        cursorTask?.cancel()
        showing = true
        hint = nil
        promptFocused = false
        cursorTask = Task {
            defer { showing = false }
            if !hasPrompt {
                await glide(to: .chip, from: CGSize(width: 90, height: 60), fast: true)
                await tap()
                for ch in OnboardingSample.nook.prompt {
                    guard !Task.isCancelled else { return }
                    prompt.append(ch)
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 22))
                }
                try? await Task.sleep(for: .seconds(0.25))
            }
            if provider == nil {
                await glide(to: .provider, from: nil, fast: true)
                await tap()
                withAnimation(.snappy(duration: 0.2)) { provider = "grok" }
                try? await Task.sleep(for: .seconds(0.35))
            }
            await glide(to: .generate, from: nil, fast: true)
            await tap()
            generate()
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeOut(duration: 0.4)) { cursor.opacity = 0 }
            startHints(after: 3)
        }
    }

    private func glide(to target: Target, from start: CGSize?, fast: Bool = false) async {
        if let start {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                cursor.target = target
                cursor.offset = start
                cursor.opacity = 0
            }
            withAnimation(.easeOut(duration: 0.25)) { cursor.opacity = 1 }
            withAnimation(.smooth(duration: fast ? 0.6 : 0.9)) { cursor.offset = .zero }
        } else {
            withAnimation(.smooth(duration: 0.6)) {
                cursor.target = target
                cursor.offset = .zero
                cursor.opacity = 1
            }
        }
        try? await Task.sleep(for: .seconds(fast ? 0.65 : 0.95))
    }

    private func tap() async {
        withAnimation(.easeOut(duration: 0.1)) { cursor.pressed = true }
        try? await Task.sleep(for: .seconds(0.16))
        withAnimation(.easeOut(duration: 0.2)) { cursor.pressed = false }
    }
}

// MARK: - Demo parts

/// The picture's result area: placeholder, calm progress, then the sample appears.
private struct OnboardingDemoCanvas: View {
    let sample: OnboardingSample
    let phase: OnboardingDemoStep.Phase
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height: CGFloat = 172
        let width = min(height * sample.aspect, 172 * 16 / 9 * 0.82)
        ZStack {
            switch phase {
            case .done:
                Image(nsImage: sample.image)
                    .resizable()
                    .aspectRatio(sample.aspect, contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    .transition(reduceMotion ? .opacity : .modifier(
                        active: OnboardingReveal(amount: 1), identity: OnboardingReveal(amount: 0)))
            case .working, .idle:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.card)
                    .overlay {
                        if phase == .working {
                            OnboardingShimmer().clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(phase == .idle ? 0.18 : 0.06),
                                      style: StrokeStyle(lineWidth: 1.2, dash: phase == .idle ? [5, 4] : [])))
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: phase == .idle ? "photo" : "sparkles")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(phase == .idle ? Color.secondary.opacity(0.6) : Theme.accent)
                            if phase == .working {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(Theme.accent)
                                    .frame(width: min(120, width - 30))
                            }
                        }
                    }
                    .frame(width: width, height: height)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: sample)
    }
}

/// Blur-to-sharp reveal for the finished image.
private nonisolated struct OnboardingReveal: ViewModifier {
    let amount: Double
    func body(content: Content) -> some View {
        content.blur(radius: 18 * amount).scaleEffect(1 + 0.05 * amount).opacity(1 - amount)
    }
}

private struct OnboardingShimmer: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            LinearGradient(colors: [.clear, Theme.accent.opacity(0.14), .clear],
                           startPoint: UnitPoint(x: -1 + t * 2.4, y: 0), endPoint: UnitPoint(x: -0.4 + t * 2.4, y: 1))
        }
    }
}

/// A selectable capsule chip (prompt ideas, providers).
private struct OnboardingChip<Label: View>: View {
    let selected: Bool
    @ViewBuilder var label: Label
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : .primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(selected ? Theme.accent.opacity(0.14)
                    : hovering ? Color.primary.opacity(0.08) : Theme.well))
                .overlay(Capsule().strokeBorder(selected ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Numbered checklist item that turns into a green check once done.
struct OnboardingCheckRow: View {
    enum State { case done, current, upcoming }
    let number: Int
    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(state == .done ? Color.green : state == .current ? Theme.accent : Color.primary.opacity(0.08))
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state == .current ? .white : .secondary)
                }
            }
            .frame(width: 22, height: 22)
            Text(title)
                .font(.system(size: 13, weight: state == .current ? .semibold : .regular))
                .foregroundStyle(state == .upcoming ? .secondary : state == .done ? .secondary : .primary)
                .strikethrough(false)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: state)
    }
}

/// The demo's animated mouse pointer.
private struct OnboardingCursor: View {
    let pressed: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Theme.accent.opacity(0.28))
                .frame(width: 28, height: 28)
                .offset(x: -14, y: -14)
                .scaleEffect(pressed ? 1 : 0.2, anchor: .topLeading)
                .opacity(pressed ? 1 : 0)
            OnboardingCursorShape()
                .fill(.black)
                .overlay(OnboardingCursorShape().stroke(.white, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)))
                .frame(width: 16, height: 22)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .scaleEffect(pressed ? 0.86 : 1, anchor: .topLeading)
        }
        .frame(width: 16, height: 22, alignment: .topLeading)
    }
}

private nonisolated struct OnboardingCursorShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: h * 0.78))
        p.addLine(to: CGPoint(x: w * 0.27, y: h * 0.6))
        p.addLine(to: CGPoint(x: w * 0.47, y: h))
        p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.93))
        p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.55))
        p.closeSubpath()
        return p
    }
}

/// A small horizontal shake for a wrong attempt.
nonisolated struct OnboardingShake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 6), y: 0))
    }
}

// MARK: - Cursor targets

struct OnboardingTargetKey: PreferenceKey {
    static let defaultValue: [OnboardingDemoStep.Target: Anchor<CGRect>] = [:]
    static func reduce(value: inout [OnboardingDemoStep.Target: Anchor<CGRect>],
                       nextValue: () -> [OnboardingDemoStep.Target: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func onboardingTarget(_ target: OnboardingDemoStep.Target?) -> some View {
        anchorPreference(key: OnboardingTargetKey.self, value: .bounds) { anchor in
            target.map { [$0: anchor] } ?? [:]
        }
    }
}
