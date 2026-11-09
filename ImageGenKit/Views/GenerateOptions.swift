import ImageIO
import Foundation

/// Which options each provider kind supports (mirrors cli/imagegenkit.py).
enum GenerateSpec {
    static let auto = "Auto"

    static func aspects(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .openai, .compatible, .together, .fal: [auto, "1:1", "3:2", "2:3", "4:3", "3:4", "16:9", "9:16"]
        case .openrouter: [auto, "1:1", "3:2", "2:3", "4:3", "3:4", "4:5", "5:4", "16:9", "9:16", "21:9"]
        case .grokBuild: [auto, "1:1", "16:9", "9:16", "3:2", "2:3"]
        case .codex: [auto, "1:1", "3:2", "2:3"]
        case .xai: [auto, "1:1", "3:4", "4:3", "9:16", "16:9", "2:3", "3:2", "1:2", "2:1"]
        case .gemini: [auto, "1:1", "3:2", "2:3", "4:3", "3:4", "4:5", "5:4", "16:9", "9:16", "21:9"]
        }
    }

    static func sizes(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .grokBuild, .codex: []
        case .xai: ["1K", "2K"]
        default: ["1K", "2K", "4K"]
        }
    }

    static let counts = ["1", "2", "3", "4"]
    static let moderations = ["auto", "low"]

    /// Quality levels the provider understands ("" / "auto" = provider default). Codex gets it as a hint.
    static func qualities(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .openai, .openrouter, .codex: ["low", "medium", "high"]
        default: []
        }
    }

    /// Background options; Codex only understands a "transparent" hint.
    static func backgrounds(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .openai: ["auto", "opaque", "transparent"]
        case .codex: ["auto", "transparent"]
        default: []
        }
    }

    static func formats(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .openai, .openrouter: ["png", "jpeg", "webp"]
        case .together, .fal: ["png", "jpeg"]
        default: []
        }
    }

    static func hasModel(_ kind: ProviderKind) -> Bool { !kind.isSubscription }
    static func hasEditModel(_ kind: ProviderKind) -> Bool { kind == .openai }
    static func hasMore(_ kind: ProviderKind) -> Bool { kind != .grokBuild }

    /// Whether the provider has any image settings at all.
    static func hasSettings(_ kind: ProviderKind) -> Bool {
        hasModel(kind) || !sizes(kind).isEmpty || !qualities(kind).isEmpty || !backgrounds(kind).isEmpty || !formats(kind).isEmpty
    }

    static func formatLabel(_ f: String) -> String { f == "jpeg" ? "JPEG" : f == "webp" ? "WebP" : f.uppercased() }

    /// What the Generate panel starts with for a provider: its saved default, else a sensible fallback.
    static func initial(_ p: ProviderInfo, _ key: String, config: ConfigStore) -> String {
        let saved = config.providerDefault(p.id, key)
        switch key {
        case "quality":
            return qualities(p.kind).contains(saved) ? saved : (p.kind == .openai ? "medium" : "auto")
        case "resolution":
            let s = sizes(p.kind)
            return s.contains(saved) ? saved : (s.isEmpty ? "" : s[min(1, s.count - 1)])
        case "background":
            return backgrounds(p.kind).contains(saved) ? saved : "auto"
        case "format":
            return formats(p.kind).contains(saved) ? saved : "png"
        default:
            return saved
        }
    }

    /// Default model shown as the field's placeholder.
    static func defaultModel(_ p: ProviderInfo, config: ConfigStore, editing: Bool) -> String {
        switch p.kind {
        case .openai:
            config.providerDefault(p.id, editing ? "edit_model" : "model")
        case .xai, .gemini:
            config.providerDefault(p.id, "model")
        case .compatible, .openrouter, .together, .fal:
            [config.providerDefault(p.id, "model"), (editing ? p.editModel : nil) ?? p.model ?? ""].first { !$0.isEmpty } ?? ""
        case .grokBuild, .codex: ""
        }
    }

    static func modelSuggestions(_ p: ProviderInfo, catalog: Catalog, config: ConfigStore) -> [String] {
        var list = catalog.entry(p.catalogID ?? p.id)?.models ?? []
        for m in LiveModels.shared.models[p.id] ?? [] where !list.contains(m) { list.append(m) }
        for m in [defaultModel(p, config: config, editing: false), defaultModel(p, config: config, editing: true)]
        where !m.isEmpty && !list.contains(m) {
            list.insert(m, at: 0)
        }
        return list
    }
}

/// The options the user picked (persisted by GenerateView).
struct GenerateOptions: Equatable {
    var aspect = GenerateSpec.auto
    var size = "2K"
    var count = 1
    var quality = "medium"
    var background = "auto"
    var format = "png"
    var compression = 85.0
    var moderation = "auto"
    var model = ""

    /// Command line for `imagegenkit <provider> - ...`; the prompt goes to stdin.
    func arguments(for p: ProviderInfo, references: [URL], mask: URL?) -> [String] {
        var a = [p.id, "-"]
        if aspect != GenerateSpec.auto, GenerateSpec.aspects(p.kind).contains(aspect) { a += ["--aspect", aspect] }
        let sizes = GenerateSpec.sizes(p.kind)
        if !sizes.isEmpty { a += ["--resolution", sizes.contains(size) ? size : sizes[min(1, sizes.count - 1)]] }
        if count > 1 { a += ["-n", String(count)] }
        for r in references { a += ["-i", r.path] }
        switch p.kind {
        case .openai:
            a += ["--quality", GenerateSpec.qualities(p.kind).contains(quality) ? quality : "auto"]
            if background != "auto" { a += ["--background", background] }
            a += ["--format", format]
            if format != "png" { a += ["--compression", String(Int(compression))] }
            if moderation != "auto" { a += ["--moderation", moderation] }
            if let mask, !references.isEmpty { a += ["--mask", mask.path] }
        default:
            // Other providers: only send what the user picked; the CLI fills in saved defaults.
            if GenerateSpec.qualities(p.kind).contains(quality) { a += ["--quality", quality] }
            if background == "transparent", GenerateSpec.backgrounds(p.kind).contains(background) { a += ["--background", background] }
            if format != "png", GenerateSpec.formats(p.kind).contains(format) { a += ["--format", format] }
        }
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if GenerateSpec.hasModel(p.kind) && !m.isEmpty { a += ["-m", m] }
        return a
    }
}

/// Turns a finished CLI run into image files or a short error.
enum GenerateOutcome {
    static func images(_ stdout: String) -> [URL] {
        stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// The last meaningful stderr line, without the "imagegenkit:" prefix.
    static func message(_ stderr: String, status: Int32) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard var line = lines.last(where: { $0.hasPrefix("imagegenkit:") }) ?? lines.last else {
            return status == 0 ? "No image came back." : "Failed (exit \(status))."
        }
        if line.hasPrefix("imagegenkit:") { line = String(line.dropFirst("imagegenkit:".count)).trimmingCharacters(in: .whitespaces) }
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}

nonisolated enum GenerateImageLoader {
    static let imageTypes = ["png", "jpg", "jpeg", "webp", "heic", "gif", "tiff", "tif", "bmp"]

    static func isImage(_ url: URL) -> Bool { imageTypes.contains(url.pathExtension.lowercased()) }

    /// Downsampled image for display (results can be 4K).
    static func load(_ url: URL, maxPixel: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
    }
}
