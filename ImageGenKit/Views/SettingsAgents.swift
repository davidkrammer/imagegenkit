import SwiftUI

/// Command line tool, agent skills, and fixes shown only when something is wrong.
struct SettingsAgentsSection: View {
    @Environment(Installer.self) private var installer
    @State private var busy: Set<String> = []
    @State private var replacing: SkillTarget?
    @State private var replacingCLI = false
    @State private var removingLegacy = false

    var body: some View {
        SettingsSection(title: "Agents", icon: "terminal.fill", lead: "Let Claude Code and Codex make images.") {
            Menu {
                ForEach(SnippetTarget.allCases) { t in
                    let added = installer.snippets[t] == true
                    Button(added ? "Added to \(t.label)" : "Add to \(t.label)",
                           systemImage: added ? "checkmark" : "doc.badge.plus") {
                        run(t.id) { await installer.addSnippet(t) }
                    }
                    .disabled(added)
                }
                Divider()
                Button("Copy Note", systemImage: "doc.on.doc") { Actions.copy(Installer.snippet) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Agent notes")
        } content: {
            SettingsRow(icon: "terminal", tint: .gray, title: "Command line tool", detail: detail(installer.cli)) {
                cliAction
            }
            ForEach(SkillTarget.allCases) { t in
                SettingsDivider(inset: 58)
                SettingsRow(icon: t == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right",
                            tint: t == .claude ? .orange : .teal,
                            title: t == .claude ? "Claude Code" : "Codex",
                            detail: detail(installer.skills[t] ?? .checking)) {
                    skillAction(t)
                }
            }
            if installer.python == .missing {
                SettingsDivider(inset: 58)
                SettingsRow(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Python 3", detail: "Missing") {
                    Button("Install") { installer.installCommandLineTools() }
                }
            }
            if installer.inPath == false, installer.cli != .missing {
                SettingsDivider(inset: 58)
                SettingsRow(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Terminal", detail: "imagegenkit isn't on your PATH") {
                    busyButton("path", "Fix") { await installer.addToPath() }
                }
            }
            if installer.legacyFound {
                SettingsDivider(inset: 58)
                SettingsRow(icon: "clock.arrow.circlepath", tint: .gray, title: "Old imagegen", detail: "No longer needed") {
                    Button(role: .destructive) { removingLegacy = true } label: { DestructiveLabel(title: "Remove") }
                }
            }
            if let error = installer.lastError {
                SettingsDivider()
                Text(error)
                    .font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            SettingsDivider()
            CommandField(command: "imagegenkit providers", runnable: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .alert("Replace \(replacing == .claude ? "Claude Code" : "Codex") skill?",
               isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
               presenting: replacing) { t in
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) { run(t.rawValue) { await installer.installSkill(t) } }
        } message: { _ in
            Text("Your own imagegenkit skill will be overwritten.")
        }
        .alert("Replace command line tool?", isPresented: $replacingCLI) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) { run("cli") { await installer.installCLI() } }
        } message: {
            Text("Another imagegenkit command will be overwritten.")
        }
        .alert("Remove old imagegen?", isPresented: $removingLegacy) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { run("legacy") { await installer.removeLegacy() } }
        } message: {
            Text("The old command and its skills move to the Trash.")
        }
    }

    private func detail(_ s: InstallState) -> String {
        switch s {
        case .checking: ""
        case .missing: "Not installed"
        case .installed(let v): "Version \(v)"
        case .outdated(let v): "Version \(v) · update available"
        case .custom: "Other version found"
        case .unavailable(let why): why
        }
    }

    @ViewBuilder
    private var cliAction: some View {
        switch installer.cli {
        case .checking: ProgressView().controlSize(.small)
        case .installed: done
        case .outdated: busyButton("cli", "Update", prominent: true) { await installer.installCLI() }
        case .missing: busyButton("cli", "Install", prominent: true) { await installer.installCLI() }
        case .custom: Button("Replace…") { replacingCLI = true }.disabled(busy.contains("cli"))
        case .unavailable: EmptyView()
        }
    }

    @ViewBuilder
    private func skillAction(_ t: SkillTarget) -> some View {
        switch installer.skills[t] ?? .checking {
        case .checking: ProgressView().controlSize(.small)
        case .installed: done
        case .outdated: busyButton(t.rawValue, "Update", prominent: true) { await installer.installSkill(t) }
        case .missing: busyButton(t.rawValue, "Install") { await installer.installSkill(t) }
        case .custom: Button("Replace…") { replacing = t }.disabled(busy.contains(t.rawValue))
        case .unavailable: Text("Not found").font(.callout).foregroundStyle(.tertiary)
        }
    }

    private var done: some View {
        SettingsBadge(text: "Installed")
    }

    @ViewBuilder
    private func busyButton(_ id: String, _ title: String, prominent: Bool = false,
                            action: @escaping () async -> Void) -> some View {
        if busy.contains(id) {
            ProgressView().controlSize(.small)
        } else if prominent {
            Button(title) { run(id, action) }.buttonStyle(.borderedProminent)
        } else {
            Button(title) { run(id, action) }
        }
    }

    private func run(_ id: String, _ action: @escaping () async -> Void) {
        busy.insert(id)
        Task {
            await action()
            busy.remove(id)
        }
    }
}
