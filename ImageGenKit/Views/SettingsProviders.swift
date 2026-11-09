import SwiftUI
import UniformTypeIdentifiers

/// The user's providers, drag to reorder (top is used first).
struct SettingsProvidersSection: View {
    @Binding var sheet: AddProviderRoute?
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @Environment(Catalog.self) private var catalog
    @State private var removing: ProviderInfo?
    @State private var dropTarget: String?

    var body: some View {
        let enabled = config.enabled(ready: { status.state($0).isReady })
        SettingsSection(title: "Providers", icon: "square.stack.3d.up.fill", lead: "Where your images come from.") {
            if !enabled.isEmpty {
                Button { sheet = .add } label: { Label("Add Provider", systemImage: "plus") }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        } content: {
            if enabled.isEmpty {
                SettingsProvidersEmpty { sheet = .add }
            } else {
                ForEach(Array(enabled.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { SettingsDivider(inset: 82) }
                    SettingsProviderRow(provider: p, rank: i, entry: entry(for: p), sheet: $sheet, removing: $removing)
                        .overlay(alignment: .top) {
                            if dropTarget == p.id {
                                Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 10)
                            }
                        }
                        .draggable(p.id) {
                            HStack(spacing: 8) {
                                Circle().fill(p.color).frame(width: 9, height: 9)
                                Text(p.label)
                            }
                            .padding(8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let source = items.first else { return false }
                            move(source, onto: p.id, in: enabled.map(\.id))
                            return true
                        } isTargeted: { on in
                            if on { dropTarget = p.id } else if dropTarget == p.id { dropTarget = nil }
                        }
                }
            }
        }
        .alert("Remove \(removing?.label ?? "provider")?",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { p in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { remove(p) }
        } message: { p in
            Text(p.needsKey ? "Its API key is deleted from your Keychain." : "It won't be used for images anymore.")
        }
    }

    private func entry(for p: ProviderInfo) -> CatalogProvider? {
        catalog.entry(p.id) ?? p.catalogID.flatMap(catalog.entry)
    }

    private func move(_ source: String, onto target: String, in ids: [String]) {
        guard source != target, let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target) else { return }
        var ids = ids
        ids.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy(duration: 0.25)) { config.setEnabled(ids) }
    }

    private func remove(_ p: ProviderInfo) {
        let ids = config.enabled(ready: { status.state($0).isReady }).map(\.id).filter { $0 != p.id }
        if p.builtin {
            config.setEnabled(ids)
        } else {
            config.removeCustomProvider(p.id)
            config.setEnabled(ids)
        }
        Task {
            if p.needsKey { await Keychain.delete(p.keychainService) }
            await status.refresh(config.providers)
        }
    }
}

struct SettingsProviderRow: View {
    let provider: ProviderInfo
    let rank: Int
    let entry: CatalogProvider?
    @Binding var sheet: AddProviderRoute?
    @Binding var removing: ProviderInfo?
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @State private var hovering = false

    var body: some View {
        let state = status.state(provider.id)
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0.35)
                .frame(width: 12)
                .help("Drag to reorder")
            SettingsProviderTile(id: provider.id, kind: provider.kind, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.label).font(.body.weight(.medium)).lineLimit(1)
                    if entry?.tested == false { Pill(text: "Untested") }
                }
                Text(subtitle(state))
                    .font(.caption)
                    .foregroundStyle(isError(state) ? Color.red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(status.testMessages[provider.id] ?? "")
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            primary(state)
            menu(state)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var installed: Bool { provider.kind == .codex ? status.codexInstalled : status.grokInstalled }

    private func isError(_ state: ProviderState) -> Bool {
        if case .error = state { return true }
        return false
    }

    private func subtitle(_ state: ProviderState) -> String {
        if status.testing.contains(provider.id) { return "Testing…" }
        switch state {
        case .ready: return provider.kind.isSubscription ? "Subscription · Logged in" : "API key · Connected"
        case .missing(let why), .error(let why): return why
        case .unknown: return "Checking…"
        }
    }

    @ViewBuilder
    private func primary(_ state: ProviderState) -> some View {
        if status.testing.contains(provider.id) {
            ProgressView().controlSize(.small)
        } else if state.isReady {
            SettingsBadge(text: "Ready")
                .help("Ready")
        } else if state != .unknown {
            Button(provider.needsKey ? "Add Key" : (installed ? "Log In" : "Set Up")) {
                sheet = .setup(provider.id)
            }
        }
    }

    private func menu(_ state: ProviderState) -> some View {
        Menu {
            Button("Test", systemImage: "checkmark.seal") {
                Task { await status.test(provider, installer: installer) }
            }
            .disabled(!state.isReady)
            if provider.needsKey {
                Button("Change Key…", systemImage: "key") { sheet = .setup(provider.id) }
            } else {
                if let login = SetupAction.command(provider.kind == .codex ? "login-codex" : "login-grok") {
                    Button("Log In Again", systemImage: "person.crop.circle") { TerminalRunner.run(login) }
                }
            }
            if !provider.builtin && provider.catalogID == nil {
                Button("Edit…", systemImage: "pencil") { sheet = .custom(provider.id) }
            }
            if let url = provider.keyURL ?? entry?.keyURL {
                Button(provider.needsKey ? "Get Key Page" : "Open \(url.host() ?? "Website")", systemImage: "safari") { Actions.open(url) }
            }
            Divider()
            Button(role: .destructive) { removing = provider } label: { DestructiveLabel(title: "Remove") }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// No providers yet: a small tour-style picture, a title and one button.
struct SettingsProvidersEmpty: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SettingsArtBackground(radius: 240)
                HStack(spacing: 14) {
                    ForEach(Array(["grok", "codex", "openai", "gemini"].enumerated()), id: \.element) { i, id in
                        SettingsProviderTile(id: id, size: 40)
                            .padding(6)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
                            .settingsFloat(3, duration: 2.6 + Double(i) * 0.35)
                            .settingsPop(0.1 + Double(i) * 0.08)
                    }
                }
            }
            .frame(height: 130)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
            VStack(spacing: 6) {
                Text("Connect a provider").font(.system(size: 17, weight: .semibold))
                Text("Your subscription or an API key.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 18)
            Button(action: add) { Label("Add Provider", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
    }
}
