import SwiftUI

// Shared look for Settings and the Add Provider sheet, matching the welcome tour.

/// Soft accent wash with a dotted grid (the tour's picture panel), at any size.
struct SettingsArtBackground: View {
    var center: UnitPoint = .init(x: 0.5, y: 0)
    var radius: CGFloat = 320
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accent.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                           center: center, startRadius: 0, endRadius: radius)
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
        }
    }
}

/// A provider's tinted tile with its symbol.
struct SettingsProviderTile: View {
    let id: String
    var kind: ProviderKind?
    var size: CGFloat = 32

    var body: some View {
        IconBadge(symbol: Self.symbol(id, kind), color: ProviderStyle.color(id), size: size)
    }

    static func symbol(_ id: String, _ kind: ProviderKind?) -> String {
        switch kind ?? ProviderKind(rawValue: id) {
        case .grokBuild?: "bolt.fill"
        case .codex?: "bubble.left.and.bubble.right.fill"
        case .openai?: "sparkles"
        case .gemini?: "diamond.fill"
        case .xai?: "bolt.horizontal.fill"
        case .compatible?: "server.rack"
        default:
            switch id {
            case "grok": "bolt.fill"
            case "codex": "bubble.left.and.bubble.right.fill"
            default: "key.fill"
            }
        }
    }
}

/// Green "Ready" style tag (the tour's badge).
struct SettingsBadge: View {
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
        .fixedSize()
    }
}

/// Numbered circle that turns into a green check.
struct SettingsStepNumber: View {
    let number: Int
    var done = false
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(done ? Color.green : Theme.accent.opacity(0.13))
            if done {
                Image(systemName: "checkmark").font(.system(size: size * 0.46, weight: .heavy)).foregroundStyle(.white)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                Text("\(number)").font(.system(size: size * 0.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
    }
}

// MARK: - Motion (short, respects Reduce Motion)

struct SettingsEnterModifier: ViewModifier {
    let index: Int
    var dx: CGFloat = 0
    var dy: CGFloat = 10
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(x: visible ? 0 : dx, y: visible ? 0 : dy)
            .onAppear {
                withAnimation(.smooth(duration: 0.45).delay(0.05 + Double(index) * 0.06)) { shown = true }
            }
    }
}

struct SettingsFloatModifier: ViewModifier {
    var amount: CGFloat = 3
    var duration: Double = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, up in
                view.offset(y: up ? -amount : amount)
            } animation: { _ in .easeInOut(duration: duration) }
        }
    }
}

struct SettingsPopModifier: ViewModifier {
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
    /// Fades and slides in after the views before it (`index` sets the delay).
    func settingsEnter(_ index: Int, dx: CGFloat = 0, dy: CGFloat = 10) -> some View {
        modifier(SettingsEnterModifier(index: index, dx: dx, dy: dy))
    }
    func settingsFloat(_ amount: CGFloat = 3, duration: Double = 3) -> some View {
        modifier(SettingsFloatModifier(amount: amount, duration: duration))
    }
    func settingsPop(_ delay: Double = 0) -> some View { modifier(SettingsPopModifier(delay: delay)) }
}
