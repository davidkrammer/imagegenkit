import AppKit
import Foundation
import Observation

/// API keys in the macOS Keychain, through /usr/bin/security like the imagegen CLI, so both can read
/// them without extra prompts. The app never reads a key's value.
nonisolated enum Keychain {
    static func exists(_ service: String) async -> Bool {
        let security = URL(fileURLWithPath: "/usr/bin/security")
        if await Shell.run(security, ["find-generic-password", "-s", service]).status == 0 { return true }
        // A key saved by the old `imagegen` CLI; imagegenkit copies it over on first use.
        let legacy = service.replacingOccurrences(of: "imagegenkit-", with: "imagegen-")
        return await Shell.run(security, ["find-generic-password", "-s", legacy]).status == 0
    }

    static func save(_ key: String, service: String, label: String) async -> Bool {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.range(of: #"[\s"\\]"#, options: .regularExpression) == nil else { return false }
        let cmd = "add-generic-password -U -a \"\(NSUserName())\" -s \"\(service)\" -l \"ImageGenKit \(label) API key\" -w \"\(clean)\"\n"
        let r = await Shell.run(URL(fileURLWithPath: "/usr/bin/security"), ["-i"], stdin: cmd)  // stdin keeps the key out of argv
        return r.status == 0
    }

    static func delete(_ service: String) async {
        let security = URL(fileURLWithPath: "/usr/bin/security")
        _ = await Shell.run(security, ["delete-generic-password", "-s", service])
        _ = await Shell.run(security, ["delete-generic-password", "-s", service.replacingOccurrences(of: "imagegenkit-", with: "imagegen-")])
    }
}

/// Setup steps that run in Terminal (catalog step "action" values).
enum SetupAction {
    static func command(_ action: String) -> String? {
        switch action {
        case "install-grok": "curl -fsSL https://x.ai/cli/install.sh | bash"
        case "login-grok": "grok login"
        case "install-codex": "if command -v brew >/dev/null 2>&1; then brew install --cask codex; else npm install -g @openai/codex; fi"
        case "login-codex": "codex login"
        default: nil
        }
    }

    /// Whether the step is already done on this Mac.
    @MainActor static func isDone(_ action: String) -> Bool {
        switch action {
        case "install-grok": ProviderStatus.grokBinary != nil
        case "login-grok": FileManager.default.fileExists(atPath: ProviderStatus.grokHome.appending(path: "auth.json").path)
        case "install-codex": ProviderStatus.codexBinary != nil
        case "login-codex": FileManager.default.fileExists(atPath: ProviderStatus.codexHome.appending(path: "auth.json").path)
        default: false
        }
    }
}

/// Opens Terminal and runs a command (for interactive steps like `grok login`).
enum TerminalRunner {
    static func run(_ command: String) {
        let url = FileManager.default.temporaryDirectory.appending(path: "imagegenkit-\(UUID().uuidString.prefix(8)).command")
        let script = "#!/bin/zsh -l\n\(command)\necho\nread -k1 \"?Done. Press any key to close.\"\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}

enum ProviderState: Equatable {
    case unknown, ready, missing(String), error(String)

    var isReady: Bool { self == .ready }
}

/// Live status of each provider: key stored, Grok installed and logged in, last test result.
@Observable
final class ProviderStatus {
    private(set) var states: [String: ProviderState] = [:]
    private(set) var testMessages: [String: String] = [:]
    private(set) var testing: Set<String> = []

    static let grokHome = Paths.home.appending(path: ".grok")

    var grokInstalled: Bool { Self.grokBinary != nil }
    var codexInstalled: Bool { Self.codexBinary != nil }

    static let codexHome = Paths.home.appending(path: ".codex")

    /// The Codex CLI, wherever npm/Homebrew put it (GUI apps don't get the shell's PATH).
    static var codexBinary: String? {
        var candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", Paths.home.appending(path: ".local/bin/codex").path]
        let nvm = Paths.home.appending(path: ".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            candidates += versions.sorted(by: >).map { nvm.appending(path: "\($0)/bin/codex").path }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var grokBinary: String? {
        let candidates = [grokHome.appending(path: "bin/grok").path, "/opt/homebrew/bin/grok", "/usr/local/bin/grok"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func state(_ id: String) -> ProviderState { states[id] ?? .unknown }

    func refresh(_ providers: [ProviderInfo]) async {
        for p in providers {
            if p.kind == .codex {
                if Self.codexBinary == nil {
                    states[p.id] = .missing("Not installed")
                } else if FileManager.default.fileExists(atPath: Self.codexHome.appending(path: "auth.json").path) {
                    states[p.id] = .ready
                } else {
                    states[p.id] = .missing("Not logged in")
                }
            } else if p.kind == .grokBuild {
                if Self.grokBinary == nil {
                    states[p.id] = .missing("Not installed")
                } else if FileManager.default.fileExists(atPath: Self.grokHome.appending(path: "auth.json").path) {
                    states[p.id] = .ready
                } else {
                    states[p.id] = .missing("Not logged in")
                }
            } else {
                states[p.id] = await Keychain.exists(p.keychainService) ? .ready : .missing("No API key")
            }
        }
    }

    /// Live check through imagegen (`imagegen check <id> --json`).
    func test(_ p: ProviderInfo, installer: Installer) async {
        testing.insert(p.id)
        defer { testing.remove(p.id) }
        let r = await installer.runCLI(["check", p.id, "--json"])
        guard let data = r.stdout.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else {
            testMessages[p.id] = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        let status = row["status"] as? String ?? ""
        let message = row["message"] as? String ?? ""
        testMessages[p.id] = message
        states[p.id] = status == "ok" ? .ready : status == "missing" ? .missing(message) : .error(message)
    }
}

/// Image models a provider's key can use right now (`imagegenkit models <id>`), merged into model menus,
/// so a new model shows up the day the provider releases it.
@Observable
final class LiveModels {
    static let shared = LiveModels()
    private(set) var models: [String: [String]] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    func load(_ p: ProviderInfo, installer: Installer) async {
        guard [.openai, .xai, .compatible].contains(p.kind), !asked.contains(p.id) else { return }
        asked.insert(p.id)
        let r = await installer.runCLI(["models", p.id])
        guard r.status == 0 else { asked.remove(p.id); return }
        models[p.id] = r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
