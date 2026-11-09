import SwiftUI

/// The welcome tour's picture background: neutral surface, soft accent glow from the top, dotted grid.
struct GalleryWash: View {
    var glow: Double = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accent.opacity((scheme == .dark ? 0.22 : 0.14) * glow), .clear],
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
        }
    }
}

/// Short staggered entrance (fade + small rise), like the tour's points.
struct GalleryEnterModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                withAnimation(.smooth(duration: 0.4).delay(0.04 + Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func galleryEnter(_ index: Int) -> some View { modifier(GalleryEnterModifier(index: index)) }
}
