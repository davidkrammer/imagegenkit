import AppKit
import SwiftUI

/// Overview's empty state: three numbered first steps that tick off as they're done.
struct OnboardingFirstSteps: View {
    let generate: () -> Void
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @State private var route: AddProviderRoute?

    private var providerReady: Bool {
        config.enabled(ready: { status.state($0).isReady }).contains { status.state($0.id).isReady }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    IconBadge(symbol: "sparkles", size: 60)
                    Text("Let's make your first image")
                        .font(.system(size: 22, weight: .semibold))
                }

                VStack(spacing: 10) {
                    OnboardingFirstStepRow(number: 1, title: "Connect a provider", detail: "Grok, ChatGPT, OpenAI, Gemini…",
                                           done: providerReady, button: "Connect") { route = .add }
                    OnboardingFirstStepRow(number: 2, title: "Connect your AI agents", detail: "Claude Code, Codex · optional",
                                           done: installer.ready, button: "Set up") { OnboardingStore.show(step: .agents) }
                    OnboardingFirstStepRow(number: 3, title: "Generate your first image", detail: "⌘N, anywhere in the app",
                                           done: false, button: "Generate", primary: true, action: generate)
                }

                Button("Take the Tour") { OnboardingStore.show() }
                    .buttonStyle(.link).foregroundStyle(Theme.accent)
                    .font(.callout)
            }
            .frame(maxWidth: 480)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 480)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Theme.background)
        .sheet(item: $route, onDismiss: { Task { await status.refresh(config.providers) } }) { AddProviderSheet(route: $0).dismissOnQuit() }
    }
}

private struct OnboardingFirstStepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let button: String
    var primary = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green : Theme.accent.opacity(0.13))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if done {
                Text("Done").font(.callout.weight(.medium)).foregroundStyle(.green)
            } else if primary {
                Button(action: action) { Label(button, systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(button, action: action)
            }
        }
        .card(padding: 14)
        .animation(.smooth(duration: 0.3), value: done)
    }
}
