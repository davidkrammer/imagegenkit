import AppKit
import SwiftUI

/// What the Add Provider sheet opens on.
enum AddProviderRoute: Identifiable, Hashable {
    case add               // catalog picker
    case setup(String)     // guided setup for one provider id (also "Change Key")
    case custom(String?)   // OpenAI-compatible endpoint: new (nil) or edit

    var id: String {
        switch self {
        case .add: "add"
        case .setup(let id): "setup-\(id)"
        case .custom(let id): "custom-\(id ?? "")"
        }
    }
}

/// A provider being set up: what the app stores plus its catalog guide.
struct AddProviderTarget: Hashable {
    var info: ProviderInfo
    var entry: CatalogProvider?
}

struct AddProviderSheet: View {
    let route: AddProviderRoute
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Catalog.self) private var catalog
    @State private var page: Page = .pick

    enum Page: Hashable {
        case pick
        case setup(AddProviderTarget)
        case custom(String?)
    }

    var body: some View {
        Group {
            switch page {
            case .pick:
                AddProviderPicker(choose: { t in withAnimation(.snappy(duration: 0.25)) { page = .setup(t) } },
                                  custom: { withAnimation(.snappy(duration: 0.25)) { page = .custom(nil) } },
                                  cancel: { dismiss() })
            case .setup(let t):
                AddProviderSetup(target: t, back: route == .add ? { withAnimation(.snappy(duration: 0.25)) { page = .pick } } : nil)
            case .custom(let id):
                AddProviderCustom(editing: id.flatMap(config.provider),
                                  back: route == .add ? { withAnimation(.snappy(duration: 0.25)) { page = .pick } } : nil)
            }
        }
        .frame(width: 560)
        .background(Theme.card)
        .onAppear {
            switch route {
            case .add: page = .pick
            case .custom(let id): page = .custom(id)
            case .setup(let id):
                if let info = config.provider(id) {
                    page = .setup(AddProviderTarget(info: info, entry: catalog.entry(id) ?? info.catalogID.flatMap(catalog.entry)))
                } else if let e = catalog.entry(id) {
                    page = .setup(AddProviderTarget(info: Self.info(for: e, config: config), entry: e))
                }
            }
        }
    }

    /// The provider a catalog entry becomes once added.
    static func info(for e: CatalogProvider, config: ConfigStore) -> ProviderInfo {
        if let p = config.provider(e.id) { return p }
        return ProviderInfo(id: e.id, label: e.name, kind: ProviderKind(rawValue: e.adapter) ?? .compatible,
                            baseURL: e.baseURL, model: e.model,
                            editModel: e.editModel, keyURL: e.keyURL, builtin: false, catalogID: e.id)
    }
}

/// Adds a provider id to the end of the user's list (keeps the existing order).
@MainActor
func addProviderEnable(_ id: String, before: [String], config: ConfigStore) {
    config.setEnabled(before.contains(id) ? before : before + [id])
}

// MARK: - Shared page layout (like a tour step)

/// Picture panel, title with badge, one-line lead, content and a footer bar.
struct AddProviderPage<Art: View, Badge: View, Content: View, Footer: View>: View {
    let title: String
    let lead: String
    var artHeight: CGFloat = 100
    @ViewBuilder var art: Art
    @ViewBuilder var badge: Badge
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SettingsArtBackground(radius: 300)
                art
            }
            .frame(height: artHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    Text(title).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                    badge
                    Spacer(minLength: 0)
                }
                if !lead.isEmpty {
                    Text(lead)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 5)
                }
                content.padding(.top, 16)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) { footer }
                .padding(.horizontal, 24)
                .frame(height: 64)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
        }
    }
}

/// A provider tile lifted on a card, floating in the picture panel.
struct AddProviderHero: View {
    let id: String
    var kind: ProviderKind?
    var symbol: String?

    var body: some View {
        Group {
            if let symbol {
                IconBadge(symbol: symbol, color: .gray, size: 52)
            } else {
                SettingsProviderTile(id: id, kind: kind, size: 52)
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: ProviderStyle.color(id).opacity(0.18), radius: 16, y: 6)
        .settingsFloat(3, duration: 3)
        .settingsPop(0.05)
    }
}

// MARK: - Page 1: picker

struct AddProviderPicker: View {
    let choose: (AddProviderTarget) -> Void
    let custom: () -> Void
    let cancel: () -> Void
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Catalog.self) private var catalog

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let added = Set(config.enabled(ready: { status.state($0).isReady }).flatMap { [$0.id, $0.catalogID ?? $0.id] })
        let all = catalog.providers.filter { $0.isBuiltin || $0.adapter == "openai-compatible" }
        // Not-yet-added providers first; the ones already set up go last.
        let entries = all.filter { !added.contains($0.id) } + all.filter { added.contains($0.id) }
        AddProviderPage(title: "Add a provider", lead: "Use a subscription you have, or an API key.", artHeight: 92) {
            HStack(spacing: 14) {
                ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { i, e in
                    SettingsProviderTile(id: e.id, kind: ProviderKind(rawValue: e.adapter), size: 34)
                        .padding(6)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 13))
                        .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
                        .settingsFloat(3, duration: 2.6 + Double(i) * 0.35)
                        .settingsPop(0.08 + Double(i) * 0.06)
                }
            }
        } badge: {
            EmptyView()
        } content: {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                        let isAdded = added.contains(e.id)
                        AddProviderCard(id: e.id, kind: ProviderKind(rawValue: e.adapter), title: e.name,
                                        tagline: e.tagline, price: e.priceHint, untested: !e.tested, added: isAdded) {
                            choose(AddProviderTarget(info: AddProviderSheet.info(for: e, config: config), entry: e))
                        }
                        .disabled(isAdded)
                        .settingsEnter(i)
                    }
                    AddProviderCard(id: "other", title: "Other API", tagline: "Any OpenAI-compatible image API.",
                                    price: nil, untested: false, added: false, symbol: "server.rack", action: custom)
                        .settingsEnter(entries.count)
                }
                .padding(2)
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .frame(maxHeight: 296)
            .fixedSize(horizontal: false, vertical: true)
            .padding(-2)
        } footer: {
            Spacer()
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
    }
}

/// A provider choice card (the tour's choice cards).
struct AddProviderCard: View {
    let id: String
    var kind: ProviderKind?
    let title: String
    let tagline: String
    let price: String?
    let untested: Bool
    let added: Bool
    var symbol: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let symbol {
                        IconBadge(symbol: symbol, color: .gray, size: 30)
                    } else {
                        SettingsProviderTile(id: id, kind: kind, size: 30)
                    }
                    Spacer(minLength: 4)
                    if added {
                        SettingsBadge(text: "Added")
                    } else if untested {
                        Pill(text: "Untested")
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(tagline).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(price?.isEmpty == false ? price! : " ")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(hovering && !added ? Theme.accent.opacity(0.07) : Theme.well, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hovering && !added ? Theme.accent.opacity(0.5) : Color.primary.opacity(0.05)))
            .offset(y: hovering && !added ? -1 : 0)
            .opacity(added ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(added ? "Already added" : tagline)
    }
}

// MARK: - Page 2: guided setup

/// Result of connecting a provider.
enum AddProviderPhase: Equatable {
    case idle, working, success, failed(String)
}

struct AddProviderSetup: View {
    let target: AddProviderTarget
    let back: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @State private var key = ""
    @State private var phase: AddProviderPhase = .idle
    @State private var tick = 0  // re-reads install/login ticks (files on disk aren't observable)
    @FocusState private var keyFocused: Bool

    private var info: ProviderInfo { target.info }
    private var isLogin: Bool { !info.needsKey }
    private var untested: Bool { target.entry.map { !$0.tested } ?? false }
    private var steps: [CatalogProvider.Step] {
        if let s = target.entry?.steps, !s.isEmpty { return s }
        if isLogin {
            let (tool, app) = info.kind == .codex ? ("codex", "Codex") : ("grok", "Grok Build")
            return [.init(text: "Install \(app).", button: nil, url: nil, action: "install-\(tool)"),
                    .init(text: "Log in to your account.", button: nil, url: nil, action: "login-\(tool)")]
        }
        return [.init(text: "Paste your API key below.", button: info.keyURL == nil ? nil : "Get Key", url: info.keyURL, action: nil)]
    }

    private var connected: Bool { phase == .success || (isLogin && status.state(info.id).isReady) }

    var body: some View {
        AddProviderPage(title: target.entry?.name ?? info.label, lead: lead) {
            AddProviderHero(id: info.id, kind: info.kind)
                .overlay(alignment: .bottomTrailing) {
                    if connected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, .green)
                            .background(Circle().fill(Theme.card).padding(2))
                            .offset(x: 8, y: 8)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: connected)
        } badge: {
            if connected {
                SettingsBadge(text: "Ready")
            } else if untested {
                SettingsBadge(text: "Untested", color: .secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                if connected {
                    success
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        let _ = tick
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            AddProviderStepRow(number: i + 1, step: step, done: stepDone(step), enabled: stepEnabled(step))
                                .settingsEnter(i, dx: 14, dy: 0)
                        }
                    }
                    if !isLogin { keyField.settingsEnter(steps.count, dx: 14, dy: 0) }
                    result
                }
            }
            .animation(.smooth(duration: 0.3), value: connected)
        } footer: {
            footer
        }
        .task(id: info.id) {
            guard isLogin else { return }
            while !Task.isCancelled {
                await status.refresh([info])
                tick &+= 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await status.refresh([info])
                tick &+= 1
            }
        }
        .onAppear { if !isLogin { keyFocused = true } }
    }

    private var lead: String {
        if let hint = target.entry?.priceHint, !hint.isEmpty { return hint }
        return isLogin ? "Uses your subscription." : "Uses your API key."
    }

    private var success: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.green)
                .settingsPop()
            VStack(alignment: .leading, spacing: 2) {
                Text(isLogin ? "You're logged in." : "Connected.").font(.system(size: 15, weight: .semibold))
                Text("Ready to make images.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            SecureField("API key", text: $key, prompt: Text("Paste your API key"))
                .textFieldStyle(.roundedBorder)
                .focused($keyFocused)
                .onSubmit(connect)
            Button("Paste", systemImage: "doc.on.clipboard") {
                if let s = NSPasteboard.general.string(forType: .string) {
                    key = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        if phase == .working {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
            .font(.callout)
        } else if case .failed(let message) = phase {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let back, !connected {
            Button("Back", action: back)
        }
        Spacer()
        if isLogin {
            let ready = status.state(info.id).isReady
            if !ready { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            Button("Done") { finishLogin() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
        } else if phase == .success {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            let empty = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Connect", action: connect)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(empty || phase == .working)
        }
    }

    // MARK: Steps

    /// nil for plain steps; install/login steps tick themselves off.
    private func stepDone(_ step: CatalogProvider.Step) -> Bool? {
        guard let action = step.action, SetupAction.command(action) != nil else { return nil }
        if action.hasPrefix("login-") && status.state(info.id).isReady { return true }
        return SetupAction.isDone(action)
    }

    /// A login step waits for its install step.
    private func stepEnabled(_ step: CatalogProvider.Step) -> Bool {
        guard let action = step.action, action.hasPrefix("login-") else { return true }
        let install = "install-" + action.dropFirst("login-".count)
        return SetupAction.command(install) == nil || SetupAction.isDone(install)
    }

    // MARK: Actions

    private func connect() {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, phase != .working else { return }
        phase = .working
        let before = config.enabled(ready: { status.state($0).isReady }).map(\.id)
        Task {
            guard await Keychain.save(clean, service: info.keychainService, label: info.label) else {
                withAnimation { phase = .failed("Couldn't save the key. Check it and try again.") }
                return
            }
            key = ""
            if config.provider(info.id) == nil {
                // Catalog providers keep their adapter settings (type, base URL, size style ...).
                if let entry = target.entry, !entry.isBuiltin { config.addCatalogProvider(entry) } else { config.saveCustomProvider(info) }
            }
            addProviderEnable(info.id, before: before, config: config)
            await status.refresh(config.providers)
            await status.test(info, installer: installer)
            withAnimation(.snappy) {
                switch status.state(info.id) {
                case .ready: phase = .success
                case .missing(let m), .error(let m): phase = .failed(m.isEmpty ? "Couldn't connect." : m)
                case .unknown: phase = .failed(status.testMessages[info.id] ?? "Couldn't connect.")
                }
            }
        }
    }

    private func finishLogin() {
        let before = config.enabled(ready: { status.state($0).isReady }).map(\.id)
        addProviderEnable(info.id, before: before, config: config)
        dismiss()
    }
}

struct AddProviderStepRow: View {
    let number: Int
    let step: CatalogProvider.Step
    let done: Bool?
    let enabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsStepNumber(number: number, done: done == true)
            Text(step.text)
                .font(.system(size: 14))
                .foregroundStyle(done == true ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if done != true, let (title, action) = button {
                Button(title, action: action)
                    .disabled(!enabled)
                    .fixedSize()
            }
        }
        .frame(minHeight: 30)
    }

    private var button: (String, () -> Void)? {
        if let action = step.action, let command = SetupAction.command(action) {
            let title = step.button ?? (action.hasPrefix("install-") ? "Install" : action.hasPrefix("login-") ? "Log In" : "Run")
            return (title, { TerminalRunner.run(command) })
        }
        guard let url = step.url else { return nil }
        return (step.button ?? "Open", { Actions.open(url) })
    }
}

// MARK: - Other API (OpenAI-compatible)

struct AddProviderCustom: View {
    let editing: ProviderInfo?
    let back: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @State private var name = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var editModel = ""
    @State private var key = ""
    @State private var phase: AddProviderPhase = .idle

    private static let reserved: Set<String> = [
        "openai", "grok", "xai", "gemini", "draft", "final", "edit", "transparent", "check", "models", "config",
        "providers", "provider", "version", "help", "log", "set-key", "delete-key",
    ]

    /// A unique, CLI-safe id derived from the name.
    private var id: String {
        if let editing { return editing.id }
        var base = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.first?.isLetter != true { base = "api-" + base }
        base = String(base.prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.count < 2 { base = "custom" }
        var candidate = base
        var n = 2
        while Self.reserved.contains(candidate) || config.provider(candidate) != nil {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: baseURL)?.scheme?.hasPrefix("http") == true
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
            && (editing != nil || !key.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        AddProviderPage(title: editing?.label ?? "Other API", lead: "Any OpenAI-compatible image API.") {
            AddProviderHero(id: editing?.id ?? "other", symbol: editing == nil ? "server.rack" : nil)
        } badge: {
            if phase == .success { SettingsBadge(text: "Ready") }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    field("Name", text: $name, prompt: "My API")
                    SettingsDivider()
                    field("Base URL", text: $baseURL, prompt: "https://api.example.com/v1")
                    SettingsDivider()
                    field("Model", text: $model, prompt: "model-id")
                    SettingsDivider()
                    field("Edit model", text: $editModel, prompt: "Optional")
                    SettingsDivider()
                    HStack(spacing: 12) {
                        Text("API key").foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                        SecureField("API key", text: $key, prompt: Text(editing == nil ? "Paste your API key" : "Unchanged"))
                            .textFieldStyle(.plain)
                            .labelsHidden()
                        Button("Paste") {
                            if let s = NSPasteboard.general.string(forType: .string) {
                                key = s.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                }
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.05)))
                switch phase {
                case .success:
                    Label("Connected. Ready to make images.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout.weight(.medium))
                        .transition(.opacity)
                case .working:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
                        .font(.callout)
                case .failed(let m):
                    Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout).lineLimit(3)
                case .idle:
                    EmptyView()
                }
            }
        } footer: {
            if let back, phase != .success { Button("Back", action: back) }
            Spacer()
            if phase == .success {
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Connect" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid || phase == .working)
            }
        }
        .onAppear {
            guard let editing else { return }
            name = editing.label
            baseURL = editing.baseURL ?? ""
            model = editing.model ?? ""
            editModel = editing.editModel ?? ""
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
    }

    private func save() {
        let before = config.enabled(ready: { status.state($0).isReady }).map(\.id)
        let p = ProviderInfo(id: id, label: name.trimmingCharacters(in: .whitespaces), kind: .compatible,
                             baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                             model: model.trimmingCharacters(in: .whitespaces),
                             editModel: editModel.isEmpty ? nil : editModel, keyURL: nil, builtin: false,
                             catalogID: editing?.catalogID)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .working
        Task {
            if !key.isEmpty, !(await Keychain.save(key, service: p.keychainService, label: p.label)) {
                withAnimation { phase = .failed("Couldn't save the key. Check it and try again.") }
                return
            }
            config.saveCustomProvider(p)
            addProviderEnable(p.id, before: before, config: config)
            if editing != nil && key.isEmpty {
                await status.refresh(config.providers)
                dismiss()
                return
            }
            await status.refresh(config.providers)
            await status.test(p, installer: installer)
            withAnimation(.snappy) {
                switch status.state(p.id) {
                case .ready: phase = .success
                case .missing(let m), .error(let m): phase = .failed(m.isEmpty ? "Couldn't connect." : m)
                case .unknown: phase = .failed("Couldn't connect.")
                }
            }
        }
    }
}
