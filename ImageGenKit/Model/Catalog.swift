import Foundation
import Observation

/// A provider ImageGenKit knows how to set up, with a step-by-step guide. Loaded from catalog/providers.json:
/// the copy bundled with the app, refreshed from GitHub so new providers and prices arrive without an app update.
nonisolated struct CatalogProvider: Identifiable, Hashable, Sendable {
    struct Step: Hashable, Sendable {
        let text: String
        let button: String?
        let url: URL?
        let action: String?  // "install-grok", "login-grok"
    }

    let id: String
    let name: String
    let adapter: String
    let auth: String  // "key" or "login"
    let tagline: String
    let priceHint: String
    let keyURL: URL?
    let steps: [Step]
    let prices: [String: Double]
    let models: [String]
    let transparent: Bool
    /// Verified with real images. Untested providers show an "Untested" label.
    let tested: Bool
    var beta: Bool { !tested }
    let baseURL: String?
    let model: String?
    let editModel: String?
    let sizeStyle: String?
    /// Optional prices per model (override the provider's prices), e.g. a new model with a different rate.
    let modelPrices: [String: [String: Double]]

    var needsKey: Bool { auth == "key" }
    var isBuiltin: Bool { ["openai", "grok", "codex", "xai", "gemini"].contains(id) }

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String, let name = d["name"] as? String, let adapter = d["adapter"] as? String else { return nil }
        self.id = id
        self.name = name
        self.adapter = adapter
        auth = d["auth"] as? String ?? "key"
        tagline = d["tagline"] as? String ?? ""
        priceHint = d["price_hint"] as? String ?? ""
        keyURL = (d["key_url"] as? String).flatMap(URL.init(string:))
        steps = (d["steps"] as? [[String: Any]] ?? []).map {
            Step(text: $0["text"] as? String ?? "", button: $0["button"] as? String,
                 url: ($0["url"] as? String).flatMap(URL.init(string:)), action: $0["action"] as? String)
        }
        prices = (d["prices"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        models = d["models"] as? [String] ?? []
        transparent = d["transparent"] as? Bool ?? false
        tested = d["tested"] as? Bool ?? !(d["beta"] as? Bool ?? true)
        baseURL = d["base_url"] as? String
        model = d["model"] as? String
        editModel = d["edit_model"] as? String
        sizeStyle = d["size_style"] as? String
        modelPrices = (d["model_prices"] as? [String: Any] ?? [:]).compactMapValues { v in
            (v as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
    }
}

@Observable
final class Catalog {
    private(set) var providers: [CatalogProvider] = []
    private(set) var updated = ""

    static let remote = URL(string: "https://raw.githubusercontent.com/strics-at/imagegenkit/main/catalog/providers.json")!
    private let cache = Paths.config.appending(path: "catalog.json")

    init() {
        if let best = Self.newestLocal() { apply(best) }
    }

    /// The newer of the downloaded catalog and the copy bundled with the app.
    nonisolated static func newestLocal() -> (providers: [CatalogProvider], updated: String)? {
        let bundled = Bundle.main.url(forResource: "providers", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        let cached = try? Data(contentsOf: Paths.config.appending(path: "catalog.json"))
        let candidates = [cached, bundled].compactMap { $0 }.compactMap(parse)
        return candidates.max(by: { $0.updated < $1.updated })
    }

    func entry(_ id: String) -> CatalogProvider? { providers.first { $0.id == id } }

    func refresh() async {
        var req = URLRequest(url: Self.remote)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = Self.parse(data), parsed.updated >= updated else { return }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cache, options: .atomic)
        apply(parsed)
    }

    private func apply(_ parsed: (providers: [CatalogProvider], updated: String)) {
        providers = parsed.providers
        updated = parsed.updated
    }

    nonisolated static func parse(_ data: Data) -> (providers: [CatalogProvider], updated: String)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["providers"] as? [[String: Any]] else { return nil }
        let providers = list.compactMap(CatalogProvider.init)
        return providers.isEmpty ? nil : (providers, obj["updated"] as? String ?? "")
    }
}
