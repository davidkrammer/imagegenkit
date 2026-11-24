import SwiftUI

/// Full-window terms of use at first launch, before the welcome tour: the key points in plain words, links to the full
/// terms and the privacy policy, and one "Agree and Continue" button. No skip; the app can't be used without agreeing.
struct TermsConsentView: View {
    let agreed: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let points: [(symbol: String, color: Color, title: String, text: String)] = [
        ("cloud.fill", Color(light: 0x2A78D6, dark: 0x5A9BEA), "Images come from your providers",
         "AI services you set up yourself, or open models on this Mac. Their terms and prices apply; costs shown here are estimates."),
        ("hand.raised.fill", Color(light: 0xEB6834, dark: 0xF08A5D), "You're responsible for what you make",
         "Nothing illegal, no nude or sexual images of real people without their consent, nothing involving minors. Respect other people's rights."),
        ("tag.fill", Color(light: 0x8E5CD9, dark: 0xAD86E8), "AI images are marked",
         "Images made on this Mac carry an AI mark. Don't remove it, and say an image is AI-made wherever the law requires it."),
        ("lock.fill", Color(light: 0x34A853, dark: 0x4CC26B), "Your data stays on this Mac",
         "Keys, prompts and images stay here; prompts go only to the provider you pick. AI results can be wrong, so check them."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .enter(0, shown, reduceMotion)

                Text("Welcome to ImageGenKit")
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.top, 16)
                    .enter(1, shown, reduceMotion)
                Text("Before you start, please read and accept the terms of use.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .enter(1, shown, reduceMotion)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(symbol: p.symbol, color: p.color, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(.system(size: 14, weight: .semibold))
                                Text(p.text).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .enter(2 + i, shown, reduceMotion)
                    }
                }
                .card(padding: 22)
                .padding(.top, 22)

                HStack(spacing: 6) {
                    Link("Read the Terms of Use", destination: TermsConsent.url)
                    Text("·").foregroundStyle(.tertiary)
                    Link("Privacy Policy", destination: TermsConsent.privacyURL)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .padding(.top, 16)
                .enter(6, shown, reduceMotion)

                Button {
                    TermsConsent.accept()
                    agreed()
                } label: {
                    Text("Agree and Continue").frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 20)
                .enter(7, shown, reduceMotion)

                Text("Terms of Use, version \(TermsConsent.version). ImageGenKit is free and open source, made by STRICS IT GmbH, Austria.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
                    .enter(7, shown, reduceMotion)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .onAppear { shown = true }
    }
}

private extension View {
    /// Rows come in one after another.
    func enter(_ index: Int, _ shown: Bool, _ reduceMotion: Bool) -> some View {
        self.opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.05 + Double(index) * 0.06), value: shown)
    }
}
