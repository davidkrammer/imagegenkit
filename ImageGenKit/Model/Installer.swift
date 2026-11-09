import AppKit
import Foundation
import Observation

enum InstallState: Equatable {
    case checking
    case missing
    case installed(String)
    case outdated(String)
    case custom  // something else is there; replacing needs confirmation
    case unavailable(String)

    var isOK: Bool { if case .installed = self { true } else { false } }
}

enum SkillTarget: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var label: String { self == .claude ? "Claude Code skill" : "Codex skill" }
    var folder: URL {
        self == .claude ? Paths.home.appending(path: ".claude/skills/imagegenkit")
            : Paths.home.appending(path: ".codex/skills/imagegenkit")
    }
    var appFolder: URL { Paths.home.appending(path: self == .claude ? ".claude" : ".codex") }
}

enum SnippetTarget: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { "snippet-\(rawValue)" }
    var label: String { self == .claude ? "CLAUDE.md" : "AGENTS.md" }
    var file: URL {
        self == .claude ? Paths.home.appending(path: ".claude/CLAUDE.md") : Paths.home.appending(path: ".codex/AGENTS.md")
    }
}

/// Installs and updates the bundled imagegen CLI and agent skill, and checks the pieces they need.
@Observable
final class Installer {
    private(set) var python: InstallState = .checking
    private(set) var cli: InstallState = .checking
    private(set) var inPath: Bool?
    private(set) var skills: [SkillTarget: InstallState] = [:]
    private(set) var snippets: [SnippetTarget: Bool] = [:]
    var lastError: String?

    static let snippet = """
    ## Images
    Use the `imagegenkit` command for any image task: `imagegenkit draft` for quick mockups, `imagegenkit final` for finished images, `imagegenkit edit -i <file>` to change an image, `imagegenkit transparent` for PNGs with alpha. Run `imagegenkit providers` once per session. Never ask for or print API keys.
    """

    let bundledCLI = Bundle.main.url(forResource: "imagegenkit", withExtension: "py")
    let bundledSkill = Bundle.main.url(forResource: "SKILL", withExtension: "md")
    let binLink = Paths.cli
    let shareFolder = Paths.home.appending(path: ".local/share/imagegenkit")
    let legacyLink = Paths.home.appending(path: ".local/bin/imagegen")
    private(set) var legacyFound = false
    @ObservationIgnored private var didAutoUpdate = false

    var bundledVersion: String { bundledCLI.flatMap { Self.version(inScript: $0) } ?? "?" }
    var skillVersion: String { bundledSkill.flatMap { Self.version(inSkill: $0) } ?? "?" }
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    /// Everything an agent needs is in place.
    var ready: Bool { cli.isOK && inPath == true && python.isOK && (skills[.claude]?.isOK ?? false || skills[.codex]?.isOK ?? false) }
    var needsAttention: Bool {
        if case .outdated = cli { return true }
        return !cli.isOK || python == .missing
    }

    // MARK: Status

    func refresh() async {
        let py = await Shell.run(URL(fileURLWithPath: "/usr/bin/env"),
                                 ["python3", "-c", "import sys;print('%d.%d.%d'%sys.version_info[:3])"])
        let v = py.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        python = py.status == 0 && Self.compare(v, "3.9") >= 0 ? .installed(v) : .missing

        cli = cliState()
        let shell = await Shell.run(URL(fileURLWithPath: "/bin/zsh"), ["-ilc", "print -r -- $PATH"])
        let pathLine = shell.stdout.split(separator: "\n").last.map(String.init) ?? ""
        inPath = pathLine.isEmpty ? nil : pathLine.split(separator: ":").contains { $0 == binLink.deletingLastPathComponent().path }

        for t in SkillTarget.allCases { skills[t] = skillState(t) }
        for t in SnippetTarget.allCases {
            let text = (try? String(contentsOf: t.file, encoding: .utf8)) ?? ""
            snippets[t] = text.localizedCaseInsensitiveContains("imagegenkit")
        }
        legacyFound = FileManager.default.fileExists(atPath: legacyLink.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: legacyLink.path)) != nil
        await autoUpdateOnce()
    }

    private func cliState() -> InstallState {
        guard let target = resolvedCLI(), let text = try? String(contentsOf: target, encoding: .utf8) else { return .missing }
        guard text.contains("imagegenkit") && text.contains("python") else { return .custom }
        let installed = Self.version(inScript: target) ?? "0"
        return Self.compare(installed, bundledVersion) < 0 ? .outdated(installed) : .installed(installed)
    }

    private func skillState(_ t: SkillTarget) -> InstallState {
        guard FileManager.default.fileExists(atPath: t.appFolder.path) else {
            return .unavailable(t == .claude ? "Claude Code not found" : "Codex not found")
        }
        let file = t.folder.appending(path: "SKILL.md")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return .missing }
        guard text.contains("managed-by: ImageGenKit") else { return .custom }
        let installed = Self.version(inSkill: file) ?? "0"
        return Self.compare(installed, skillVersion) < 0 ? .outdated(installed) : .installed(installed)
    }

    /// The real file behind ~/.local/bin/imagegen (following a symlink).
    private func resolvedCLI() -> URL? {
        let fm = FileManager.default
        if let dest = try? fm.destinationOfSymbolicLink(atPath: binLink.path) {
            let url = dest.hasPrefix("/") ? URL(fileURLWithPath: dest)
                : binLink.deletingLastPathComponent().appending(path: dest).standardizedFileURL
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        return fm.fileExists(atPath: binLink.path) ? binLink : nil
    }

    /// Once per launch: bring the installed CLI and ImageGenKit-managed skills up to the versions in this app.
    /// Only touches things ImageGenKit installed (custom files are left alone).
    private func autoUpdateOnce() async {
        guard !didAutoUpdate else { return }
        didAutoUpdate = true
        if case .outdated = cli { await installCLI() }
        for t in SkillTarget.allCases {
            if case .outdated = skills[t] ?? .checking { await installSkill(t) }
        }
    }

    // MARK: Actions

    /// Installs or updates the CLI. Keeps an existing location (e.g. a symlink into a skill folder).
    func installCLI() async {
        guard let bundledCLI, let data = try? Data(contentsOf: bundledCLI) else { return fail("CLI missing from the app bundle") }
        let fm = FileManager.default
        do {
            let target: URL
            if let existing = resolvedCLI() {
                target = existing
            } else {
                try fm.createDirectory(at: shareFolder, withIntermediateDirectories: true)
                target = shareFolder.appending(path: "imagegenkit.py")
                try fm.createDirectory(at: binLink.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? fm.destinationOfSymbolicLink(atPath: binLink.path)) != nil { try fm.removeItem(at: binLink) }
                try data.write(to: target, options: .atomic)
                try fm.createSymbolicLink(at: binLink, withDestinationURL: target)
            }
            try data.write(to: target, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        } catch {
            fail("Install failed: \(error.localizedDescription)")
        }
        await refresh()
    }

    func addToPath() async {
        let rc = Paths.home.appending(path: ".zshrc")
        let line = "\n# Added by ImageGenKit\nexport PATH=\"$HOME/.local/bin:$PATH\"\n"
        do {
            var text = (try? String(contentsOf: rc, encoding: .utf8)) ?? ""
            if !text.contains("$HOME/.local/bin") && !text.contains("~/.local/bin") {
                text += line
                try text.write(to: rc, atomically: true, encoding: .utf8)
            }
        } catch {
            fail("Could not update ~/.zshrc: \(error.localizedDescription)")
        }
        await refresh()
    }

    func installSkill(_ t: SkillTarget) async {
        guard let bundledSkill, let data = try? Data(contentsOf: bundledSkill) else { return fail("Skill missing from the app bundle") }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: t.folder, withIntermediateDirectories: true)
            try data.write(to: t.folder.appending(path: "SKILL.md"), options: .atomic)
            if t == .claude {
                // Extra Claude Code profiles (CLAUDE_CONFIG_DIR=~/.claude-*) get a link to the same skill.
                for dir in extraClaudeFolders() {
                    let skills = dir.appending(path: "skills")
                    let link = skills.appending(path: "imagegenkit")
                    guard !fm.fileExists(atPath: link.path) else { continue }
                    try? fm.createDirectory(at: skills, withIntermediateDirectories: true)
                    try? fm.createSymbolicLink(at: link, withDestinationURL: t.folder)
                }
            }
        } catch {
            fail("Could not write the skill: \(error.localizedDescription)")
        }
        await refresh()
    }

    private func extraClaudeFolders() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: Paths.home, includingPropertiesForKeys: nil,
                                                                   options: [])) ?? []
        return items.filter { $0.lastPathComponent.hasPrefix(".claude-") && FileManager.default.fileExists(atPath: $0.appending(path: "settings.json").path) || $0.lastPathComponent.hasPrefix(".claude-") && FileManager.default.fileExists(atPath: $0.appending(path: "skills").path) }
    }

    /// Moves the old `imagegen` command and its `image-gen` skills to the Trash.
    func removeLegacy() async {
        let fm = FileManager.default
        var targets: [URL] = []
        if let dest = try? fm.destinationOfSymbolicLink(atPath: legacyLink.path) {
            targets.append(legacyLink)
            let real = dest.hasPrefix("/") ? URL(fileURLWithPath: dest) : legacyLink.deletingLastPathComponent().appending(path: dest)
            if real.path.contains("/skills/image-gen/") { targets.append(real.deletingLastPathComponent().deletingLastPathComponent()) }
        } else if fm.fileExists(atPath: legacyLink.path) {
            targets.append(legacyLink)
        }
        for dir in [Paths.home.appending(path: ".claude")] + extraClaudeFolders() + [Paths.home.appending(path: ".codex")] {
            let old = dir.appending(path: "skills/image-gen")
            if fm.fileExists(atPath: old.path) || (try? fm.destinationOfSymbolicLink(atPath: old.path)) != nil {
                if !targets.contains(old) { targets.append(old) }
            }
        }
        for t in targets {
            if (try? fm.destinationOfSymbolicLink(atPath: t.path)) != nil {
                try? fm.removeItem(at: t)  // just a link
            } else {
                try? fm.trashItem(at: t, resultingItemURL: nil)
            }
        }
        await refresh()
    }

    func addSnippet(_ t: SnippetTarget) async {
        do {
            try FileManager.default.createDirectory(at: t.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = (try? String(contentsOf: t.file, encoding: .utf8)) ?? ""
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += "\n<!-- imagegenkit -->\n\(Self.snippet)\n<!-- /imagegenkit -->\n"
            try text.write(to: t.file, atomically: true, encoding: .utf8)
        } catch {
            fail("Could not update \(t.label): \(error.localizedDescription)")
        }
        await refresh()
    }

    func installCommandLineTools() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }

    /// Runs the bundled CLI (always the version this app understands) with the user's config and keys.
    func runCLI(_ args: [String], stdin: String? = nil) async -> Shell.Result {
        guard let bundledCLI else { return Shell.Result(status: -1, stdout: "", stderr: "CLI missing from the app bundle") }
        return await Shell.run(URL(fileURLWithPath: "/usr/bin/env"), ["python3", bundledCLI.path] + args, stdin: stdin)
    }

    private func fail(_ message: String) {
        lastError = message
    }

    // MARK: Helpers

    nonisolated static func version(inScript url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let r = text.range(of: #"(?m)^VERSION = "([^"]+)""#, options: .regularExpression) else { return nil }
        return text[r].split(separator: "\"").dropFirst().first.map(String.init)
    }

    nonisolated static func version(inSkill url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let r = text.range(of: #"(?m)^\s*version:\s*\S+"#, options: .regularExpression) else { return nil }
        return text[r].split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
    }

    /// Numeric dotted-version compare: -1, 0, 1.
    nonisolated static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }
}
