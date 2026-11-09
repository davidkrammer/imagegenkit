import Foundation

/// Token usage the OpenAI Images API returns for one request (all images of that request).
nonisolated struct OpenAIUsage: Sendable, Hashable {
    var inputTokens: Int
    var inputTextTokens: Int?
    var inputImageTokens: Int?
    var outputTokens: Int
    var totalTokens: Int
}

/// Usage that `grok usage <session>` reports for one headless Grok Build run.
nonisolated struct GrokUsage: Sendable, Hashable {
    var inputTokens: Int
    var outputTokens: Int
    var cachedReadTokens: Int
    var costUsdTicks: Int?
    var modelId: String?

    /// API-equivalent value in USD (10^10 ticks per USD). Covered by the grok.com subscription, not billed.
    var apiValueUSD: Double? { costUsdTicks.map { Double($0) / 1e10 } }
}

/// Who started the run (logged by imagegen since 2026-11-09).
nonisolated struct Caller: Sendable, Hashable {
    var agent: String?
    var account: Int?
    var entrypoint: String?
    var session: String?
    var t3Thread: String?

    var label: String {
        var parts: [String] = []
        switch agent {
        case "claude": parts.append("Claude" + (account.map { " · account \($0)" } ?? ""))
        case "codex": parts.append("Codex")
        case "terminal": parts.append("Terminal")
        case let other?: parts.append(other.capitalized)
        case nil: break
        }
        if entrypoint == "t3-code" || t3Thread != nil { parts.append("T3 Code") }
        return parts.joined(separator: " · ")
    }
}

nonisolated struct Param: Sendable, Hashable {
    let key: String
    let value: String
}

/// One line of ~/.config/imagegen/log.jsonl, i.e. one imagegen run.
nonisolated struct LogEntry: Identifiable, Sendable, Hashable {
    let id: Int  // line number in the log, stable because the log is append-only
    let date: Date
    let ts: String
    let provider: String  // "openai", "grok", "xai", "gemini" or a custom provider name
    let type: String      // provider type: openai, grok-build, xai, gemini, openai-compatible
    let task: String?     // draft / final / edit / transparent (imagegen 1.0+)
    let model: String
    let prompt: String
    let params: [Param]
    let refs: [String]
    let outputs: [String]  // absolute paths
    let thumbs: [String?]  // preview copies written by the CLI (index-aligned with outputs)
    let seconds: Double?
    let cwd: String
    let grokSession: String?
    let caller: Caller?
    let openAIUsage: OpenAIUsage?
    let grokUsage: GrokUsage?
    let reportedCostUSD: Double?  // billed cost the provider reported, if any
    let project: String

    var imageCount: Int { outputs.count }

    func param(_ key: String) -> String? { params.first { $0.key == key }?.value }

    /// Pixel size or aspect, whichever the run recorded.
    var sizeLabel: String {
        if let s = param("size") { return s.replacingOccurrences(of: "x", with: "×") }
        if let a = param("aspect"), a != "null" { return a }
        return "auto"
    }

    var kindLabel: String {
        if let task { return task.capitalized }
        if type == "grok-build" { return param("tool") == "image_edit" ? "Edit" : "Generate" }
        return refs.isEmpty ? "Generate" : "Edit"
    }

    var modelLabel: String {
        if type == "grok-build" { return model == "default" ? "Grok Imagine" : model }
        return model
    }

    var isSubscription: Bool { type == "grok-build" }

    /// A shell command that runs the same request again.
    var rerunCommand: String {
        var parts = ["imagegenkit", provider, shellQuote(prompt)]
        for r in refs { parts += ["-i", shellQuote(r)] }
        if type == "grok-build" {
            if let a = param("aspect"), a != "null" { parts += ["--aspect", a] }
        } else {
            if let s = param("size") { parts += ["--size", s] }
            for key in ["quality", "background"] {
                if let v = param(key) { parts += ["--\(key)", v] }
            }
            if let f = param("output_format") { parts += ["--format", f] }
            if type != "openai" || !model.hasPrefix("gpt-image-2.5") { parts += ["-m", model] }
        }
        if let n = param("n"), n != "1" { parts += ["-n", n] }
        return parts.joined(separator: " ")
    }
}

nonisolated func shellQuote(_ s: String) -> String {
    if s.range(of: #"^[A-Za-z0-9_./:=@%+-]+$"#, options: .regularExpression) != nil { return s }
    return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}
