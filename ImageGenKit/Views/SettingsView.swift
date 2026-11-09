import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case providers = "Providers"
    case tasks = "Use for"
    case defaults = "Defaults"
    case prices = "Prices"
    case install = "Install"
    var id: String { rawValue }
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab: SettingsTab = .providers
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)
            Divider()
            Group {
                switch tab {
                case .providers: ProvidersSettings()
                default: Text("Being redesigned").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            config.reload()
            await status.refresh(config.providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            config.reload()
            Task {
                await status.refresh(config.providers)
                await installer.refresh()
            }
        }
    }
}

// MARK: - Providers

struct ProvidersSettings: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @State private var keyFor: ProviderInfo?
    @State private var editing: ProviderInfo?
    @State private var removeKeyFor: ProviderInfo?
    @State private var deleting: ProviderInfo?

    var body: some View {
        List {
            Section {
                ForEach(config.providers) { p in
                    ProviderRow(provider: p, keyFor: $keyFor, editing: $editing, removeKeyFor: $removeKeyFor, deleting: $deleting)
                }
                .onMove { config.moveProviders(from: $0, to: $1) }
            } header: {
                Text("Order")
            } footer: {
                Button("Add Provider", systemImage: "plus") {
                    editing = ProviderInfo(id: "", label: "", kind: .compatible, builtin: false)
                }
                .padding(.top, 6)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .sheet(item: $keyFor) { KeySheet(provider: $0) }
        .sheet(item: $editing) { CustomProviderSheet(original: $0) }
        .alert("Remove API key?", isPresented: Binding(get: { removeKeyFor != nil }, set: { if !$0 { removeKeyFor = nil } }),
               presenting: removeKeyFor) { p in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    await Keychain.delete(p.keychainService)
                    await status.refresh(config.providers)
                }
            }
        } message: { p in
            Text("\(p.label) stops working until you add a key again.")
        }
        .alert("Delete provider?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { p in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                config.removeCustomProvider(p.id)
                Task { await Keychain.delete(p.keychainService) }
            }
        } message: { p in
            Text("\(p.label) and its key will be removed.")
        }
    }
}

private struct ProviderRow: View {
    let provider: ProviderInfo
    @Binding var keyFor: ProviderInfo?
    @Binding var editing: ProviderInfo?
    @Binding var removeKeyFor: ProviderInfo?
    @Binding var deleting: ProviderInfo?
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer

    var body: some View {
        let state = status.state(provider.id)
        HStack(spacing: 10) {
            Circle().fill(provider.color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.label).font(.body.weight(.medium))
                Text(subtitle(state)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if status.testing.contains(provider.id) {
                ProgressView().controlSize(.small)
            }
            primaryButton(state)
            Menu {
                if state.isReady {
                    Button("Test") { Task { await status.test(provider, installer: installer) } }
                }
                if let url = provider.keyURL {
                    Link(provider.needsKey ? "Get API Key" : "Open grok.com", destination: url)
                }
                if provider.kind == .grokBuild {
                    Button("Log In Again") { TerminalRunner.run("grok login") }
                }
                if !provider.builtin {
                    Button("Edit…") { editing = provider }
                }
                if provider.needsKey && state.isReady {
                    Divider()
                    Button(role: .destructive) { removeKeyFor = provider } label: { DestructiveLabel(title: "Remove Key", icon: "key.slash") }
                }
                if !provider.builtin {
                    Button(role: .destructive) { deleting = provider } label: { DestructiveLabel(title: "Delete Provider") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func subtitle(_ state: ProviderState) -> String {
        if let msg = status.testMessages[provider.id] { return msg }
        switch state {
        case .ready: return provider.kind == .grokBuild ? "Logged in" : "Key saved"
        case .missing(let why), .error(let why): return why
        case .unknown: return " "
        }
    }

    @ViewBuilder
    private func primaryButton(_ state: ProviderState) -> some View {
        if provider.kind == .grokBuild {
            if !status.grokInstalled {
                Button("Install") { TerminalRunner.run("curl -fsSL https://x.ai/cli/install.sh | bash") }
            } else if !state.isReady {
                Button("Log In") { TerminalRunner.run("grok login") }
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.iconOnly)
            }
        } else {
            Button(state.isReady ? "Change Key" : "Add Key") { keyFor = provider }
        }
    }
}

private struct KeySheet: View {
    let provider: ProviderInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @State private var key = ""
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(provider.label) API key").font(.headline)
            SecureField("Paste key", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit(save)
            HStack {
                if let url = provider.keyURL { Link("Get a key", destination: url).font(.callout) }
                if failed { Text("Couldn't save").font(.callout).foregroundStyle(.red) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            Text("Stored in your Keychain.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func save() {
        saving = true
        Task {
            let ok = await Keychain.save(key, service: provider.keychainService, label: provider.label)
            saving = false
            guard ok else { failed = true; return }
            await status.refresh(config.providers)
            dismiss()
            await status.test(provider, installer: installer)
        }
    }
}

private struct CustomProviderSheet: View {
    let original: ProviderInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @State private var id = ""
    @State private var label = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var editModel = ""
    @State private var key = ""

    private var isNew: Bool { original.id.isEmpty }
    private var idValid: Bool {
        id.range(of: #"^[a-z][a-z0-9-]{1,30}$"#, options: .regularExpression) != nil
            && !["openai", "grok", "xai", "gemini", "draft", "final", "edit", "transparent", "check", "models", "config",
                 "providers", "provider", "version", "help", "log", "set-key", "delete-key"].contains(id)
            && (!isNew || config.provider(id) == nil)
    }
    private var valid: Bool { idValid && URL(string: baseURL)?.scheme?.hasPrefix("http") == true && !model.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add Provider" : "Edit \(original.label)").font(.headline)
            Form {
                TextField("Name", text: $id, prompt: Text("together"))
                    .disabled(!isNew)
                TextField("Label", text: $label, prompt: Text("Together AI"))
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                TextField("Model", text: $model, prompt: Text("model-id"))
                TextField("Edit model", text: $editModel, prompt: Text("Optional"))
                SecureField("API key", text: $key, prompt: Text(isNew ? "Optional" : "Unchanged"))
            }
            .formStyle(.columns)
            .frame(width: 420)
            Text("OpenAI-compatible images API.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(20)
        .onAppear {
            id = original.id
            label = original.label
            baseURL = original.baseURL ?? ""
            model = original.model ?? ""
            editModel = original.editModel ?? ""
        }
    }

    private func save() {
        let p = ProviderInfo(id: id, label: label.isEmpty ? id : label, kind: .compatible, baseURL: baseURL, model: model,
                             editModel: editModel.isEmpty ? nil : editModel, keyURL: nil, builtin: false)
        config.saveCustomProvider(p)
        let key = key
        Task {
            if !key.isEmpty { _ = await Keychain.save(key, service: p.keychainService, label: p.label) }
            await status.refresh(config.providers)
        }
        dismiss()
    }
}
