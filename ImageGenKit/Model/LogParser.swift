import Foundation

/// Turns log.jsonl lines into `LogEntry` values. Tolerant of old entries (relative paths,
/// no thumbs/caller) and of unknown keys added later.
nonisolated struct LogParser {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    func parse(line: Substring, id: Int) -> LogEntry? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["ts"] as? String
        else { return nil }

        let date = formatter.date(from: String(ts.prefix(19))) ?? .distantPast
        let provider = obj["provider"] as? String ?? "other"
        let type = obj["type"] as? String ?? (provider == "grok" ? "grok-build" : provider)
        let cwd = obj["cwd"] as? String ?? ""
        let outputs = (obj["outputs"] as? [String] ?? []).map { resolve($0, cwd: cwd) }
        let refs = (obj["refs"] as? [String] ?? []).map { resolve($0, cwd: cwd) }
        let thumbs = (obj["thumbs"] as? [Any] ?? []).map { $0 as? String }

        var params: [Param] = []
        if let p = obj["params"] as? [String: Any] {
            params = p.keys.sorted().map { Param(key: $0, value: Self.string(p[$0])) }
        }

        var openAIUsage: OpenAIUsage?
        var grokUsage: GrokUsage?
        var reportedCost: Double?
        if let u = obj["usage"] as? [String: Any] {
            if let ticks = Self.int(u["cost_in_usd_ticks"]) { reportedCost = Double(ticks) / 1e10 }
            if type == "grok-build" {
                grokUsage = GrokUsage(
                    inputTokens: Self.int(u["inputTokens"]) ?? 0,
                    outputTokens: Self.int(u["outputTokens"]) ?? 0,
                    cachedReadTokens: Self.int(u["cachedReadTokens"]) ?? 0,
                    costUsdTicks: Self.int(u["costUsdTicks"]),
                    modelId: u["primaryModelId"] as? String)
            } else if u["input_tokens"] != nil || u["output_tokens"] != nil {
                let inDetails = u["input_tokens_details"] as? [String: Any]
                openAIUsage = OpenAIUsage(
                    inputTokens: Self.int(u["input_tokens"]) ?? 0,
                    inputTextTokens: Self.int(inDetails?["text_tokens"]),
                    inputImageTokens: Self.int(inDetails?["image_tokens"]),
                    outputTokens: Self.int(u["output_tokens"]) ?? 0,
                    totalTokens: Self.int(u["total_tokens"]) ?? 0)
            }
        }

        var caller: Caller?
        if let c = obj["caller"] as? [String: Any] {
            caller = Caller(agent: c["agent"] as? String, account: Self.int(c["account"]),
                            entrypoint: c["entrypoint"] as? String, session: c["session"] as? String,
                            t3Thread: c["t3_thread"] as? String)
        }

        return LogEntry(
            id: id, date: date, ts: ts, provider: provider, type: type, task: obj["task"] as? String,
            model: obj["model"] as? String ?? "?", prompt: obj["prompt"] as? String ?? "",
            params: params, refs: refs, outputs: outputs, thumbs: thumbs,
            seconds: (obj["seconds"] as? NSNumber)?.doubleValue, cwd: cwd,
            grokSession: obj["grok_session"] as? String, caller: caller,
            openAIUsage: openAIUsage, grokUsage: grokUsage, reportedCostUSD: reportedCost,
            project: ProjectNamer.name(cwd: cwd, outputs: outputs))
    }

    private func resolve(_ path: String, cwd: String) -> String {
        if path.hasPrefix("/") { return path }
        if path.hasPrefix("~/") { return NSHomeDirectory() + path.dropFirst(1) }
        return cwd.isEmpty ? path : cwd + "/" + path
    }

    private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

    private static func string(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case nil, is NSNull: return "null"
        case let other?:
            if let d = try? JSONSerialization.data(withJSONObject: other, options: [.sortedKeys]),
               let s = String(data: d, encoding: .utf8) { return s }
            return String(describing: other)
        }
    }
}

/// Derives a readable project name from where a run happened or where its images went.
nonisolated enum ProjectNamer {
    static func name(cwd: String, outputs: [String]) -> String {
        // Where the images were saved is usually the more meaningful place.
        if let out = outputs.first, let named = named(out) { return named }
        if let named = named(cwd) { return named }
        return fallback(cwd)
    }

    /// Recognised project locations, or nil.
    static func named(_ path: String) -> String? {
        if let brand = component(after: "/com~apple~CloudDocs/Videos/", in: path) { return "Videos · \(brand)" }
        for root in ["/App Projects/", "/Web Projects/", "/Random Projects/"] {
            if let name = component(after: root, in: path) { return name }
        }
        // Claude Code scratchpads: /private/tmp/claude-<uid>/-Users-<me>-Random-Projects-Video-Ideas/<session>/scratchpad
        if let r = path.range(of: #"/tmp/claude-\d+/"#, options: .regularExpression),
           let encoded = path[r.upperBound...].split(separator: "/").first.map(String.init) {
            let home = NSHomeDirectory().replacingOccurrences(of: "/", with: "-") + "-"
            let s = encoded.hasPrefix(home) ? String(encoded.dropFirst(home.count)) : encoded
            for root in ["App-Projects-", "Web-Projects-", "Random-Projects-"] where s.hasPrefix(root) {
                return String(s.dropFirst(root.count)).replacingOccurrences(of: "-", with: " ")
            }
            if s.hasPrefix("-t3-scratch") { return "T3 scratch" }
        }
        if path.contains("/.t3/scratch/") { return "T3 scratch" }
        return nil
    }

    static func fallback(_ path: String) -> String {
        if let tmp = component(after: "/private/tmp/", in: path) ?? component(after: "/tmp/", in: path) {
            return "tmp · \(tmp)"
        }
        if path == NSHomeDirectory() { return "Home" }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? "Unknown" : last
    }

    private static func component(after marker: String, in path: String) -> String? {
        guard let r = path.range(of: marker) else { return nil }
        let rest = path[r.upperBound...]
        let comp = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        return comp.isEmpty ? nil : comp
    }
}
