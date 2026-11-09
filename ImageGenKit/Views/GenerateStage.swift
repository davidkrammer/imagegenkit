import SwiftUI

// Building blocks that give the Generate panel the welcome tour's look:
// an accent-washed dotted picture area, a calm title + one-line lead, short staggered entrances.

/// Light accent wash with a dotted grid (the tour's picture background).
struct GenerateWash: View {
    var center = UnitPoint(x: 0.5, y: 0)
    var radius: CGFloat = 360
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

/// Panel header: app icon, a big friendly title and a one-line lead on the accent wash.
struct GenerateHeader<Lead: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var lead: Lead
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "sparkles", size: 46)
                .generatePop()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 22, weight: .semibold))
                    accessory
                }
                lead
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 26)
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background { GenerateWash(center: UnitPoint(x: 0.15, y: 0), radius: 420) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}

/// Small status tag next to the title ("Working", "Done").
struct GenerateTag: View {
    let text: String
    var color: Color = Theme.accent
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
                .phaseAnimator(pulsing && !reduceMotion ? [1.0, 0.35] : [1.0]) { dot, o in dot.opacity(o) }
                    animation: { _ in .easeInOut(duration: 0.7) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(0.13), in: Capsule())
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// The "picture" area that holds the running placeholders and the results.
struct GenerateStagePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { GenerateWash(radius: 420) }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// An empty canvas with a soft shimmer while an image is being made.
struct GenerateCanvasPlaceholder: View {
    let aspect: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let (w, h) = aspect == GenerateSpec.auto ? (1, 1) : GenerateAspectShape.ratio(aspect)
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.card)
            .overlay {
                if !reduceMotion { GenerateShimmer().clipShape(RoundedRectangle(cornerRadius: 10)) }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
            }
            .aspectRatio(w / h, contentMode: .fit)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

struct GenerateShimmer: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            LinearGradient(colors: [.clear, Theme.accent.opacity(0.14), .clear],
                           startPoint: UnitPoint(x: -1 + t * 2.4, y: 0), endPoint: UnitPoint(x: -0.4 + t * 2.4, y: 1))
        }
    }
}

/// Wraps its children onto more lines when they don't fit (provider choices).
struct GenerateFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, view) in zip(arrange(subviews, width: bounds.width), subviews) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
        }
        return frames
    }
}

// MARK: - Motion (same timing as the welcome tour)

struct GenerateEnterModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                withAnimation(.smooth(duration: 0.45).delay(0.08 + Double(index) * 0.06)) { shown = true }
            }
    }
}

struct GeneratePopModifier: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .scaleEffect(visible ? 1 : 0.7)
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(delay)) { shown = true } }
    }
}

/// Blur-to-sharp reveal for a finished image.
nonisolated struct GenerateReveal: ViewModifier {
    let amount: Double
    func body(content: Content) -> some View {
        content.blur(radius: 16 * amount).scaleEffect(1 + 0.04 * amount).opacity(1 - amount)
    }
}

extension View {
    func generateEnter(_ index: Int) -> some View { modifier(GenerateEnterModifier(index: index)) }
    func generatePop(_ delay: Double = 0) -> some View { modifier(GeneratePopModifier(delay: delay)) }
}
