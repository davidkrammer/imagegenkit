import SwiftUI

// MARK: - 1 Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            OnboardingArtPanel {
                HStack(spacing: 14) {
                    OnboardingToolCard(symbol: "sparkles", title: "Generate", color: Theme.accent)
                        .onboardingFloat(5, duration: 2.8, tilt: -4).onboardingPop(0.05)
                    OnboardingToolCard(symbol: "photo.on.rectangle.angled", title: "Gallery",
                                       color: Color(light: 0x2A78D6, dark: 0x4A93EA), sample: .nook)
                        .onboardingFloat(6, duration: 3.4, tilt: 3).onboardingPop(0.15)
                    OnboardingToolCard(symbol: "chart.bar.fill", title: "Usage & costs",
                                       color: Color(light: 0x1BAF7A, dark: 0x2BC48C))
                        .onboardingFloat(5, duration: 3.1, tilt: -2).onboardingPop(0.25)
                    OnboardingToolCard(symbol: "terminal.fill", title: "Agents",
                                       color: Color(light: 0xEB6834, dark: 0xF07A48))
                        .onboardingFloat(6, duration: 2.6, tilt: 4).onboardingPop(0.35)
                }
            }
            OnboardingText(title: "Welcome to ImageGenKit", lead: "Make AI images with your own accounts, all in one place.") {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingPoint(number: 1, text: "Generate with Grok, ChatGPT, OpenAI, Gemini and more.")
                    OnboardingPoint(number: 2, text: "Every image lands in your Gallery, with what it cost.")
                    OnboardingPoint(number: 3, text: "Claude Code and Codex can make images for you too.")
                }
            }
        }
    }
}

/// A small floating card with a tool's icon and a hint of what it shows.
private struct OnboardingToolCard: View {
    let symbol: String
    let title: String
    let color: Color
    var sample: OnboardingSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(symbol: symbol, color: color, size: 32)
            Group {
                switch title {
                case "Gallery":
                    HStack(spacing: 4) {
                        ForEach([OnboardingSample.nook, .robot, .ramen]) { s in
                            Image(nsImage: s.image).resizable().scaledToFill()
                                .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                case "Usage & costs":
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(Array([0.45, 0.8, 0.6, 1.0, 0.7].enumerated()), id: \.offset) { i, h in
                            OnboardingGrowBar(height: 26 * h, color: color, delay: 0.4 + Double(i) * 0.08)
                        }
                    }
                    .frame(height: 26, alignment: .bottom)
                case "Agents":
                    Text("$ imagegenkit")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(height: 26)
                default:
                    HStack(spacing: 4) {
                        Capsule().fill(Color.primary.opacity(0.12)).frame(width: 46, height: 8)
                        Capsule().fill(color).frame(width: 22, height: 8)
                    }
                    .frame(height: 26)
                }
            }
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 104, alignment: .leading)
        .card(padding: 13, radius: 14)
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
    }
}

/// A bar that grows from zero.
struct OnboardingGrowBar: View {
    let height: CGFloat
    let color: Color
    var width: CGFloat = 9
    var delay: Double = 0
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: min(3, width / 3))
            .fill(color.gradient)
            .frame(width: width, height: grown || reduceMotion ? height : 2)
            .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(delay)) { grown = true } }
    }
}

// MARK: - 3 Gallery & costs

/// Usage numbers from the real log, rounded; sample numbers when there are no runs yet.
struct OnboardingUsage {
    var images: Int
    var cost: Double
    var period: String
    var bars: [(provider: String, images: Int)]
    var isExample: Bool

    @MainActor
    init(store: LogStore, config: ConfigStore) {
        let monthStart = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let month = store.entries.filter { $0.date >= monthStart }
        let entries = month.isEmpty ? store.entries : month
        guard !entries.isEmpty else {
            images = 40; cost = 2.4; period = "a month"; isExample = true
            bars = [("grok", 18), ("openai", 12), ("gemini", 6), ("codex", 4)]
            return
        }
        let stats = Stats(entries: entries, rangeStart: nil, cost: config.cost)
        images = stats.images
        cost = stats.cost
        period = month.isEmpty ? "so far" : "this month"
        isExample = false
        bars = stats.byProvider.map { ($0.id, $0.images) }
    }

    static func about(_ n: Int) -> String {
        if n < 12 { return "\(n)" }
        let step = n < 60 ? 5 : n < 200 ? 10 : n < 1000 ? 50 : 100
        return "about \(Int((Double(n) / Double(step)).rounded()) * step)"
    }

    var imagesText: String { "\(Self.about(images)) image\(images == 1 ? "" : "s")" }
    var costText: String {
        if cost == 0 { return "$0" }
        if cost < 1 { return "under $1" }
        return "about \(Format.usd(cost.rounded()).replacingOccurrences(of: ".00", with: ""))"
    }
}

struct OnboardingGalleryStep: View {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config

    var body: some View {
        let usage = OnboardingUsage(store: store, config: config)
        VStack(spacing: 0) {
            OnboardingArtPanel {
                HStack(spacing: 22) {
                    // Gallery tiles popping in.
                    let tiles: [OnboardingSample] = [.nook, .robot, .mug, .ramen, .mountain, .robot]
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { i, s in
                            Image(nsImage: s.image).resizable().scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                                .onboardingPop(0.1 + Double(i) * 0.09)
                        }
                    }
                    .frame(width: 190)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
                    .onboardingFloat(4, duration: 3.2, tilt: -2)

                    // Usage card with growing bars.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(usage.period.capitalized(with: nil)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Spacer()
                            if usage.isExample { Pill(text: "Example") }
                        }
                        Text(usage.costText.replacingOccurrences(of: "about ", with: "≈ "))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        let top = max(1, usage.bars.map(\.images).max() ?? 1)
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(Array(usage.bars.prefix(5).enumerated()), id: \.offset) { i, bar in
                                VStack(spacing: 5) {
                                    OnboardingGrowBar(height: max(6, 58 * CGFloat(bar.images) / CGFloat(top)),
                                                      color: ProviderStyle.color(bar.provider), width: 22,
                                                      delay: 0.35 + Double(i) * 0.1)
                                    Text(ProviderStyle.label(bar.provider))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
                        }
                        .frame(height: 74, alignment: .bottom)
                    }
                    .frame(width: 180, alignment: .leading)
                    .card(padding: 14)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
                    .onboardingFloat(5, duration: 2.9, tilt: 2)
                }
            }
            OnboardingText(title: "Gallery & costs", lead: "Every image is saved with its prompt and price.") {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingPoint(number: 1, text: "Subscriptions (Grok, ChatGPT): no extra cost per image.")
                    OnboardingPoint(number: 2, text: "API keys: you pay per image, and see each price.")
                    OnboardingPoint(number: 3, text: usage.isExample
                        ? "Example: 40 images a month cost about $2 on an API key."
                        : "You: \(usage.imagesText) \(usage.period), \(usage.costText).")
                }
            }
        }
    }
}

// MARK: - 6 Done

struct OnboardingDoneStep: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer

    var body: some View {
        let ready = config.enabled(ready: { status.state($0).isReady }).filter { status.state($0.id).isReady }
        VStack(spacing: 0) {
            OnboardingArtPanel {
                ZStack {
                    let fan: [(OnboardingSample, CGFloat, Double, CGFloat)] = [
                        (.mountain, -206, -10, 96), (.mug, -120, -5, 104), (.robot, 120, 5, 104), (.ramen, 214, 9, 80),
                    ]
                    ForEach(Array(fan.enumerated()), id: \.offset) { i, item in
                        OnboardingSampleImage(sample: item.0, height: item.3)
                            .onboardingFloat(5, duration: 2.6 + Double(i) * 0.3, tilt: item.2)
                            .offset(x: item.1, y: 6)
                            .onboardingPop(0.08 * Double(i))
                    }
                    OnboardingSampleImage(sample: .nook, height: 124)
                        .onboardingFloat(4, duration: 3.3)
                        .onboardingPop(0.3)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.green.gradient, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .green.opacity(0.35), radius: 8, y: 3)
                        .offset(x: 92, y: -60)
                        .onboardingPop(0.6)
                }
            }
            OnboardingText(title: "You're all set", lead: "Make your first image.") {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingPoint(number: 1, text: ready.isEmpty
                        ? "No provider yet: add one any time in Settings."
                        : "Ready: \(ready.prefix(3).map(\.label).joined(separator: ", ")).")
                    OnboardingPoint(number: 2, text: "Press ⌘N to generate from anywhere in the app.")
                    OnboardingPoint(number: 3, text: "This tour is in the Help menu.")
                }
            }
        }
    }
}
