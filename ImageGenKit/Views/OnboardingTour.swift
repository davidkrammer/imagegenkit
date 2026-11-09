import AppKit
import SwiftUI

// MARK: - Seen state and opening

/// Seen state of the welcome tour. Bump `version` to show a reworked tour once more.
enum OnboardingStore {
    static let version = 1
    private static let seenKey = "onboardingSeenVersion"
    /// Posted by Settings ("Show welcome tour") and the Help menu; `userInfo["step"]` (Int) opens a given step.
    static let showNotification = Notification.Name("ImageGenKitShowOnboarding")

    static var seen: Bool { UserDefaults.standard.integer(forKey: seenKey) >= version }
    static func markSeen() { UserDefaults.standard.set(version, forKey: seenKey) }

    static func show(step: OnboardingStep = .welcome) {
        NotificationCenter.default.post(name: showNotification, object: nil, userInfo: ["step": step.rawValue])
    }

    #if DEBUG
    /// `-onboarding YES -onboardingStep N -onboardingFresh YES` (screenshots).
    static var debugOpen: Bool { UserDefaults.standard.bool(forKey: "onboarding") }
    static var debugStep: Int { UserDefaults.standard.integer(forKey: "onboardingStep") }
    static var debugFresh: Bool { UserDefaults.standard.bool(forKey: "onboardingFresh") }
    /// `-onboardingAutoplay YES`: walks through the steps by itself and runs "Show me" (walkthrough video).
    static var debugAutoplay: Bool { UserDefaults.standard.bool(forKey: "onboardingAutoplay") }
    #else
    static let debugAutoplay = false
    static let debugFresh = false
    #endif
}

/// Where the last step's buttons go.
enum OnboardingDestination { case generate, gallery, settings }

/// Attach once in RootView: `.background(OnboardingPresenter { destination in ... })`.
/// Opens the tour ~0.7 s after the window appears on first launch, and whenever the notification is posted.
struct OnboardingPresenter: View {
    let go: (OnboardingDestination) -> Void
    @State private var open = false
    @State private var start: OnboardingStep = .welcome

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: $open, onDismiss: OnboardingStore.markSeen) {
                OnboardingTour(start: start) { destination in
                    OnboardingStore.markSeen()
                    open = false
                    if let destination {
                        Task { try? await Task.sleep(for: .milliseconds(350)); go(destination) }
                    }
                }
            }
            .task {
                var auto = !OnboardingStore.seen
                #if DEBUG
                if OnboardingStore.debugOpen {
                    auto = true
                    start = OnboardingStep(rawValue: OnboardingStore.debugStep) ?? .welcome
                }
                #endif
                guard auto else { return }
                try? await Task.sleep(for: .milliseconds(700))
                open = true
            }
            .onReceive(NotificationCenter.default.publisher(for: OnboardingStore.showNotification)) { note in
                guard !open else { return }
                start = (note.userInfo?["step"] as? Int).flatMap(OnboardingStep.init) ?? .welcome
                open = true
            }
    }
}

// MARK: - Tour

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, generate, gallery, provider, agents, done
    var id: Int { rawValue }
}

/// Fixed sizes: every step has the same height, so the sheet never jumps.
enum OnboardingLayout {
    static let width: CGFloat = 620
    static let artHeight: CGFloat = 204
    static let textHeight: CGFloat = 238
    static let footerHeight: CGFloat = 60
}

/// Shared between the tour and its steps: whether arrow keys may change the step.
@Observable
final class OnboardingKeys {
    var typing = false
    var sheetOpen = false
}

struct OnboardingTour: View {
    let close: (OnboardingDestination?) -> Void
    @State private var step: OnboardingStep
    @State private var forward = true
    @State private var keys = OnboardingKeys()
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(start: OnboardingStep = .welcome, close: @escaping (OnboardingDestination?) -> Void) {
        self.close = close
        _step = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                page(step)
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            .frame(height: OnboardingLayout.artHeight + OnboardingLayout.textHeight, alignment: .top)
            .clipped()

            footer
        }
        .frame(width: OnboardingLayout.width)
        .background(Theme.card)
        .overlay(alignment: .topTrailing) { closeButton }
        .environment(keys)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { arrow(-1) }
        .onKeyPress(.rightArrow) { arrow(1) }
        .task {
            guard OnboardingStore.debugAutoplay else { return }
            let waits: [Double] = [4, 10, 4.5, 4, 5]
            for wait in waits {
                try? await Task.sleep(for: .seconds(wait))
                go(step.rawValue + 1)
            }
        }
    }

    @ViewBuilder
    private func page(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: OnboardingWelcomeStep()
        case .generate: OnboardingDemoStep()
        case .gallery: OnboardingGalleryStep()
        case .provider: OnboardingProviderStep()
        case .agents: OnboardingAgentsStep()
        case .done: OnboardingDoneStep()
        }
    }

    private var closeButton: some View {
        Button { close(nil) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            OnboardingDots(step: step, go: go)
            Spacer(minLength: 8)
            if step == .done {
                Button("Settings") { close(.settings) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                Button("Open Gallery") { close(.gallery) }
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                Button { close(.generate) } label: { Label("Generate your first image", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(step == .welcome ? "Skip" : "Back") {
                    if step == .welcome { close(nil) } else { go(step.rawValue - 1) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                Button { go(step.rawValue + 1) } label: {
                    HStack(spacing: 5) {
                        Text("Next")
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: OnboardingLayout.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }

    private func go(_ index: Int) {
        guard let target = OnboardingStep(rawValue: max(0, min(OnboardingStep.allCases.count - 1, index))),
              target != step else { return }
        forward = target.rawValue > step.rawValue
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.42)) { step = target }
    }

    private func arrow(_ delta: Int) -> KeyPress.Result {
        guard !keys.typing, !keys.sheetOpen else { return .ignored }
        go(step.rawValue + delta)
        return .handled
    }
}

/// Clickable progress dots; the current one is a wider accent capsule.
struct OnboardingDots: View {
    let step: OnboardingStep
    let go: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { s in
                Button { go(s.rawValue) } label: {
                    Capsule()
                        .fill(s == step ? Theme.accent : Color.primary.opacity(0.16))
                        .frame(width: s == step ? 22 : 7, height: 7)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(s.rawValue + 1) of \(OnboardingStep.allCases.count)")
            }
        }
        .animation(.smooth(duration: 0.3), value: step)
    }
}

// MARK: - Layout parts

/// The fixed-height picture at the top of each step.
struct OnboardingArtPanel<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accent.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                           center: .init(x: 0.5, y: 0), startRadius: 0, endRadius: 360)
            Canvas { ctx, size in
                let gap: CGFloat = 18
                var y: CGFloat = gap / 2
                while y < size.height {
                    var x: CGFloat = gap / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                                 with: .color(.primary.opacity(0.09)))
                        x += gap
                    }
                    y += gap
                }
            }
            content
        }
        .frame(height: OnboardingLayout.artHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}

/// Title, one-line lead and the step's content, at one fixed height.
struct OnboardingText<Content: View, Badge: View>: View {
    let title: String
    let lead: String
    @ViewBuilder var badge: Badge
    @ViewBuilder var content: Content

    init(title: String, lead: String, @ViewBuilder badge: () -> Badge = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.lead = lead
        self.badge = badge()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(.system(size: 22, weight: .semibold))
                badge
                Spacer(minLength: 0)
            }
            Text(lead)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            content
                .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: OnboardingLayout.textHeight, alignment: .top)
    }
}

/// A numbered point that slides in after the ones before it.
struct OnboardingPoint: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.13), in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(.system(size: 14))
        }
        .onboardingEnter(number - 1)
    }
}

/// Green "Found" style tag next to a title.
struct OnboardingBadge: View {
    let text: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: - Motion helpers

struct OnboardingEnterModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(x: visible ? 0 : 14)
            .onAppear {
                withAnimation(.smooth(duration: 0.5).delay(0.12 + Double(index) * 0.08)) { shown = true }
            }
    }
}

struct OnboardingFloatModifier: ViewModifier {
    var amount: CGFloat = 5
    var duration: Double = 3
    var tilt: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.rotationEffect(.degrees(tilt))
        } else {
            content.phaseAnimator([false, true]) { view, up in
                view.offset(y: up ? -amount : amount)
                    .rotationEffect(.degrees(tilt + (up ? 0.8 : -0.8)))
            } animation: { _ in .easeInOut(duration: duration) }
        }
    }
}

/// Pops in once with a spring after `delay`.
struct OnboardingPopModifier: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .scaleEffect(visible ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.68).delay(delay)) { shown = true } }
    }
}

extension View {
    func onboardingEnter(_ index: Int) -> some View { modifier(OnboardingEnterModifier(index: index)) }
    func onboardingFloat(_ amount: CGFloat = 5, duration: Double = 3, tilt: Double = 0) -> some View {
        modifier(OnboardingFloatModifier(amount: amount, duration: duration, tilt: tilt))
    }
    func onboardingPop(_ delay: Double = 0) -> some View { modifier(OnboardingPopModifier(delay: delay)) }
}

// MARK: - Sample images (bundled, used by the demos)

enum OnboardingSample: String, CaseIterable, Identifiable {
    case mug = "sample-1-1", nook = "sample-2-1", mountain = "sample-3-1", robot = "sample-4-2", ramen = "sample-5-1"
    var id: String { rawValue }

    var image: NSImage {
        if let cached = Self.cache[rawValue] { return cached }
        let image = Bundle.main.url(forResource: rawValue, withExtension: "jpg").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        Self.cache[rawValue] = image
        return image
    }

    private static var cache: [String: NSImage] = [:]

    var aspect: CGFloat {
        switch self {
        case .mug, .robot: 1
        case .nook: 1.5
        case .mountain: 2.0 / 3
        case .ramen: 16.0 / 9
        }
    }

    var size: String {
        switch self {
        case .mug, .robot: "1024 × 1024"
        case .nook: "1536 × 1024"
        case .mountain: "1024 × 1536"
        case .ramen: "1792 × 1024"
        }
    }

    /// The suggestion chip text and the prompt it types.
    var chip: String {
        switch self {
        case .mug: "Green mug"
        case .nook: "Reading nook"
        case .mountain: "Mountain poster"
        case .robot: "Robot sticker"
        case .ramen: "Ramen"
        }
    }

    var prompt: String {
        switch self {
        case .mug: "A sage green mug on a wooden table, morning light"
        case .nook: "A cozy reading nook with an olive tree and a lamp"
        case .mountain: "Minimal mountain poster at sunset"
        case .robot: "A cute robot sticker, waving"
        case .ramen: "A steaming bowl of ramen, moody light"
        }
    }

    /// The sample that best matches a typed prompt.
    static func match(_ prompt: String) -> OnboardingSample {
        let p = prompt.lowercased()
        let words: [(OnboardingSample, [String])] = [
            (.mug, ["mug", "cup", "coffee", "tea"]),
            (.nook, ["room", "nook", "chair", "read", "book", "interior", "lamp", "plant", "cozy"]),
            (.mountain, ["mountain", "poster", "landscape", "sunset", "lake", "nature"]),
            (.robot, ["robot", "sticker", "cute", "character", "mascot", "cartoon"]),
            (.ramen, ["ramen", "food", "noodle", "soup", "bowl", "dinner", "egg"]),
        ]
        if p.trimmingCharacters(in: .whitespaces).isEmpty { return .mug }
        if let hit = words.first(where: { $0.1.contains(where: p.contains) }) { return hit.0 }
        return allCases[abs(p.hashValue) % allCases.count]
    }
}

/// A sample image with rounded corners and a soft shadow.
struct OnboardingSampleImage: View {
    let sample: OnboardingSample
    var height: CGFloat = 120

    var body: some View {
        Image(nsImage: sample.image)
            .resizable()
            .aspectRatio(sample.aspect, contentMode: .fill)
            .frame(width: height * sample.aspect, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}
