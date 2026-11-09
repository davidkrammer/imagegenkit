import SwiftUI

/// History's empty and no-results states, styled like a welcome-tour step:
/// a small picture panel, one title, one line, and the native actions.
struct HistoryEmptyState: View {
    enum Kind: Equatable {
        case noRuns, filtered, search(String)
    }

    let kind: Kind
    @Environment(LogStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HistoryEmptyArt(symbol: symbol)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 24)
            Text(lead)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            actions.padding(.top, 20)
        }
        .padding(32)
        .frame(maxWidth: 460)
    }

    private var symbol: String {
        switch kind {
        case .noRuns: "clock"
        case .filtered: "line.3.horizontal.decrease"
        case .search: "magnifyingglass"
        }
    }

    private var title: String {
        switch kind {
        case .noRuns: "No runs yet"
        case .filtered: "Nothing in this range"
        case .search(let text): "No results for “\(text.trimmingCharacters(in: .whitespaces))”"
        }
    }

    private var lead: String {
        switch kind {
        case .noRuns: "Press ⌘N to make your first image."
        case .filtered: "Try a longer range or all providers."
        case .search: "Try a different word."
        }
    }

    @ViewBuilder
    private var actions: some View {
        @Bindable var store = store
        HStack(spacing: 10) {
            switch kind {
            case .noRuns:
                Button("Take the Tour") { OnboardingStore.show() }
            case .filtered:
                if store.providerFilter != nil {
                    Button("All Providers") { withAnimation { store.providerFilter = nil } }
                }
                if store.range != .all {
                    Button("Show All Time") { withAnimation { store.range = .all } }
                        .buttonStyle(.borderedProminent)
                }
            case .search:
                Button("Clear Search") { store.searchText = "" }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

/// Rounded picture panel: accent wash, dotted grid, a few placeholder rows floating in.
private struct HistoryEmptyArt: View {
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            OverviewArtBackground()
            VStack(spacing: 8) {
                ForEach(0..<3) { i in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.accent.opacity(0.12 + Double(2 - i) * 0.06))
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(Color.primary.opacity(0.14)).frame(width: [92, 70, 82][i], height: 6)
                            Capsule().fill(Color.primary.opacity(0.07)).frame(width: [56, 64, 44][i], height: 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .frame(width: 210)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 8, y: 3)
                    .opacity(shown || reduceMotion ? 1 - Double(i) * 0.22 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 10)
                    .animation(.smooth(duration: 0.5).delay(0.08 + Double(i) * 0.08), value: shown)
                }
            }
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accent.gradient, in: Circle())
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 3)
                .offset(x: 108, y: -44)
                .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                .opacity(shown || reduceMotion ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.68).delay(0.35), value: shown)
        }
        .frame(width: 340, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
        .onAppear { shown = true }
    }
}
