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
        .frame(width: 500)
        .background(Theme.background)
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

// MARK: - Page 1: picker

struct AddProviderPicker: View {
    let choose: (AddProviderTarget) -> Void
    let custom: () -> Void
    let cancel: () -> Void
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Catalog.self) private var catalog

    var body: some View {
        let added = Set(config.enabled(ready: { status.state($0).isReady }).flatMap { [$0.id, $0.catalogID ?? $0.id] })
        let entries = catalog.providers.filter { $0.isBuiltin || $0.adapter == "openai-compatible" }
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Provider").font(.title2.weight(.semibold))
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(entries) { e in
                        let isAdded = added.contains(e.id)
                        AddProviderCard(color: ProviderStyle.color(e.id), title: e.name, tagline: e.tagline,
                                        price: e.priceHint, beta: e.beta, added: isAdded) {
                            choose(AddProviderTarget(info: AddProviderSheet.info(for: e, config: config), entry: e))
                        }
                        .disabled(isAdded)
                    }
                    AddProviderCard(color: .gray, title: "Other API", tagline: "Any OpenAI-compatible image API.",
                                    price: nil, beta: false, added: false, symbol: "server.rack", action: custom)
                }
                .padding(2)
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
    }
}

struct AddProviderCard: View {
    let color: Color
    let title: String
    let tagline: String
    let price: String?
    let beta: Bool
    let added: Bool
    var symbol: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.15))
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                    } else {
                        Circle().fill(color).frame(width: 12, height: 12)
                    }
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.body.weight(.semibold))
                        if beta { Pill(text: "Untested") }
                    }
                    Text(tagline).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    if let price, !price.isEmpty {
                        Text(price).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if added {
                    Label("Added", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hovering && !added ? Theme.accent.opacity(0.5) : Color.primary.opacity(0.06)))
            .opacity(added ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
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
    @FocusState private var keyFocused: Bool

    private var info: ProviderInfo { target.info }
    private var isLogin: Bool { !info.needsKey }
    private var steps: [CatalogProvider.Step] {
        if let s = target.entry?.steps, !s.isEmpty { return s }
        if isLogin {
            return [.init(text: "Install Grok Build.", button: nil, url: nil, action: "install-grok"),
                    .init(text: "Log in to your Grok account.", button: nil, url: nil, action: "login-grok")]
        }
        return [.init(text: "Paste your API key below.", button: info.keyURL == nil ? nil : "Get Key", url: info.keyURL, action: nil)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    AddProviderStepRow(number: i + 1, step: step, done: stepDone(step), enabled: stepEnabled(step))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 0)
            if !isLogin { keyField }
            result
            footer
        }
        .padding(24)
        .task(id: info.id) {
            guard isLogin else { return }
            while !Task.isCancelled {
                await status.refresh([info])
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await status.refresh([info]) }
        }
        .onAppear { if !isLogin { keyFocused = true } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Back")
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(info.color.opacity(0.15))
                Circle().fill(info.color).frame(width: 13, height: 13)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.entry?.name ?? info.label).font(.title2.weight(.semibold))
                    if target.entry?.beta == true { Pill(text: "Untested") }
                }
                if let hint = target.entry?.priceHint, !hint.isEmpty {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            SecureField("API key", text: $key, prompt: Text("Paste your API key"))
                .textFieldStyle(.plain)
                .focused($keyFocused)
                .onSubmit(connect)
            Button("Paste") {
                if let s = NSPasteboard.general.string(forType: .string) {
                    key = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(keyFocused ? Theme.accent.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: keyFocused ? 1.5 : 1))
    }

    @ViewBuilder
    private var result: some View {
        let loginReady = isLogin && status.state(info.id).isReady
        if phase == .success || loginReady {
            Label(isLogin ? "You're logged in." : "Connected. Ready to make images.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
                .transition(.opacity)
        } else if phase == .working {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        } else if case .failed(let message) = phase {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if isLogin {
                let ready = status.state(info.id).isReady
                if !ready { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                Button("Done") { finishLogin() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.5)
            } else if phase == .success {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                let empty = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(empty || phase == .working)
                    .opacity(empty || phase == .working ? 0.5 : 1)
            }
        }
    }

    // MARK: Steps

    private func stepDone(_ step: CatalogProvider.Step) -> Bool? {
        switch step.action {
        case "install-grok": status.grokInstalled
        case "login-grok": status.state(info.id).isReady
        default: nil
        }
    }

    private func stepEnabled(_ step: CatalogProvider.Step) -> Bool {
        step.action == "login-grok" ? status.grokInstalled : true
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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if done == true {
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().fill(Theme.accent.opacity(0.14))
                    Text("\(number)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 22, height: 22)
            .animation(.snappy, value: done)
            VStack(alignment: .leading, spacing: 8) {
                Text(step.text)
                    .foregroundStyle(done == true ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if done != true, let (title, action) = button {
                    Button(title, action: action)
                        .controlSize(.regular)
                        .disabled(!enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var button: (String, () -> Void)? {
        switch step.action {
        case "install-grok":
            return ("Install", { TerminalRunner.run("curl -fsSL https://x.ai/cli/install.sh | bash") })
        case "login-grok":
            return ("Log In", { TerminalRunner.run("grok login") })
        default:
            guard let url = step.url else { return nil }
            return (step.button ?? "Open", { Actions.open(url) })
        }
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("Back")
                }
                IconBadge(symbol: "server.rack", color: .gray, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(editing == nil ? "Other API" : editing!.label).font(.title2.weight(.semibold))
                    Text("OpenAI-compatible").font(.callout).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                field("Name", text: $name, prompt: "Together AI")
                SettingsDivider()
                field("Base URL", text: $baseURL, prompt: "https://api.example.com/v1")
                SettingsDivider()
                field("Model", text: $model, prompt: "model-id")
                SettingsDivider()
                field("Edit model", text: $editModel, prompt: "Optional")
                SettingsDivider()
                HStack(spacing: 12) {
                    Text("API key").frame(width: 84, alignment: .leading)
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
            .card(padding: 0)
            switch phase {
            case .success:
                Label("Connected. Ready to make images.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout.weight(.medium))
            case .working:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            case .failed(let m):
                Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout).lineLimit(3)
            case .idle:
                EmptyView()
            }
            HStack {
                Spacer()
                if phase == .success {
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(editing == nil ? "Connect" : "Save", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(!valid || phase == .working)
                        .opacity(!valid || phase == .working ? 0.5 : 1)
                }
            }
        }
        .padding(24)
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
            Text(title).frame(width: 84, alignment: .leading)
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
