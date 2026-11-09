import ImageIO
import Foundation

/// Which options each provider kind supports (mirrors cli/imagegenkit.py).
enum GenerateSpec {
    static let auto = "Auto"

    static func aspects(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .openai, .compatible: [auto, "1:1", "3:2", "2:3", "4:3", "3:4", "16:9", "9:16"]
        case .grokBuild: [auto, "1:1", "16:9", "9:16", "3:2", "2:3"]
        case .xai: [auto, "1:1", "3:4", "4:3", "9:16", "16:9", "2:3", "3:2", "1:2", "2:1"]
        case .gemini: [auto, "1:1", "3:2", "2:3", "4:3", "3:4", "4:5", "5:4", "16:9", "9:16", "21:9"]
        }
    }

    static func sizes(_ kind: ProviderKind) -> [String] {
        switch kind {
        case .grokBuild: []
        case .xai: ["1K", "2K"]
        default: ["1K", "2K", "4K"]
        }
    }

    static let counts = ["1", "2", "3", "4"]
    static let qualities = ["auto", "low", "medium", "high"]
    static let backgrounds = ["auto", "opaque", "transparent"]
    static let formats = ["png", "jpeg", "webp"]
    static let moderations = ["auto", "low"]

    static func hasModel(_ kind: ProviderKind) -> Bool { kind != .grokBuild }
    static func hasMore(_ kind: ProviderKind) -> Bool { kind != .grokBuild }

    /// Default model shown as the field's placeholder.
    static func defaultModel(_ p: ProviderInfo, config: ConfigStore, editing: Bool) -> String {
        switch p.kind {
        case .openai: config.string(editing ? "openai_edit_model" : "openai_model")
        case .xai: config.string("xai_model")
        case .gemini: config.string("gemini_model")
        case .compatible: (editing ? p.editModel : nil) ?? p.model ?? ""
        case .grokBuild: ""
        }
    }

    static func modelSuggestions(_ p: ProviderInfo, catalog: Catalog, config: ConfigStore) -> [String] {
        var list = catalog.entry(p.catalogID ?? p.id)?.models ?? []
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
        if p.kind == .openai {
            a += ["--quality", quality]
            if background != "auto" { a += ["--background", background] }
            a += ["--format", format]
            if format != "png" { a += ["--compression", String(Int(compression))] }
            if moderation != "auto" { a += ["--moderation", moderation] }
            if let mask, !references.isEmpty { a += ["--mask", mask.path] }
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
