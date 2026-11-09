import AppKit
import Foundation
import Observation
import SwiftUI

/// The tasks imagegen routes to a provider (`imagegen draft|final|edit|transparent`).
enum ImageTask: String, CaseIterable, Identifiable {
    case draft, final, edit, transparent
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .draft: "scribble"
        case .final: "sparkles"
        case .edit: "wand.and.stars"
        case .transparent: "square.dashed"
        }
    }
}

nonisolated enum ProviderKind: String, Sendable {
    case openai, grokBuild = "grok-build", xai, gemini, compatible = "openai-compatible", openrouter, together, fal
}

/// One provider imagegen can use: built-in or the user's own OpenAI-compatible endpoint.
struct ProviderInfo: Identifiable, Hashable {
    let id: String
    var label: String
    let kind: ProviderKind
    var baseURL: String?
    var model: String?
    var editModel: String?
    var keyURL: URL?
    var builtin: Bool
    var catalogID: String?

    var needsKey: Bool { kind != .grokBuild }
    var keychainService: String { "imagegenkit-\(id)" }
    var canTransparent: Bool { kind == .openai }
    var color: Color { ProviderStyle.color(id) }

    static let builtins: [ProviderInfo] = [
        ProviderInfo(id: "grok", label: "Grok subscription", kind: .grokBuild, keyURL: URL(string: "https://grok.com"), builtin: true),
        ProviderInfo(id: "openai", label: "OpenAI", kind: .openai, baseURL: "https://api.openai.com/v1",
                     keyURL: URL(string: "https://platform.openai.com/api-keys"), builtin: true),
        ProviderInfo(id: "xai", label: "xAI API", kind: .xai, baseURL: "https://api.x.ai/v1",
                     keyURL: URL(string: "https://console.x.ai"), builtin: true),
        ProviderInfo(id: "gemini", label: "Google Gemini", kind: .gemini,
                     baseURL: "https://generativelanguage.googleapis.com/v1beta",
                     keyURL: URL(string: "https://aistudio.google.com/apikey"), builtin: true),
    ]
}

/// Labels and series colors for provider ids seen in the log (fixed per provider, never by rank).
enum ProviderStyle {
    static var customLabels: [String: String] = [:]
    static var customOrder: [String] = []

    static func label(_ id: String) -> String {
        switch id {
        case "openai": "OpenAI"
        case "grok": "Grok"
        case "xai": "xAI API"
        case "gemini": "Gemini"
        default: customLabels[id] ?? id.capitalized
        }
    }

    // Validated categorical slots 1-8 (light, dark).
    private static let slots: [(UInt32, UInt32)] = [
        (0x2A78D6, 0x3987E5), (0xEB6834, 0xD95926), (0x1BAF7A, 0x199E70), (0xEDA100, 0xC98500),
        (0xE87BA4, 0xD55181), (0x008300, 0x008300), (0x6250D6, 0x9085E9), (0xE34948, 0xE66767),
    ]

    static func color(_ id: String) -> Color {
        let index: Int? = switch id {
        case "openai": 0
        case "grok": 1
        case "gemini": 2
        case "xai": 3
        default: customOrder.firstIndex(of: id).map { 4 + $0 % 4 }
        }
        guard let index else { return .gray }
        return Color(light: slots[index].0, dark: slots[index].1)
    }
}

/// Reads and writes ~/.config/imagegen/config.json, the settings file the imagegen CLI uses.
/// Only keys the user changed are written; defaults mirror DEFAULTS in cli/imagegen.py.
@Observable
final class ConfigStore {
    private(set) var user: [String: Any] = [:]
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var lastModified: Date?
    /// Default prices from the provider catalog (set by the app at launch).
    var catalogPrices: [String: [String: Double]] = [:]

    static let defaults: [String: Any] = [
        "openai_model": "gpt-image-2.5-flare",
        "openai_edit_model": "gpt-image-2.5-sunburst",
        "xai_model": "grok-imagine-image",
        "gemini_model": "gemini-nano-banana-2.1",
        "resolution": "2K",
        "quality": "medium",
        "output_dir": "~/Pictures/ImageGenKit",
        "order": ["grok", "openai", "xai", "gemini"],
    ]
    static let defaultTasks: [String: [String: String]] = [
        "draft": ["provider": "grok", "quality": "low", "resolution": "1K"],
        "final": ["provider": "openai"],
        "edit": ["provider": "openai"],
        "transparent": ["provider": "openai"],
    ]
    /// Price estimates (USD). Checked 2026-11-09: OpenAI GPT Image 2.5 per 1M tokens (developers.openai.com/api/docs/pricing),
    /// xAI grok-imagine-image per image (docs.x.ai/docs/models), Gemini Nano Banana 2.1 at 1K per image (ai.google.dev pricing).
    static let defaultPrices: [String: [String: Double]] = [
        "openai": ["text_in": 5, "image_in": 8, "image_out": 30],
        "xai": ["per_image": 0.02],
        "gemini": ["per_image": 0.0336],
    ]

    init(url: URL = Paths.config.appending(path: "config.json")) {
        self.url = url
        reload()
    }

    // MARK: File

    func reload() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard modified != lastModified || modified == nil else { return }
        lastModified = modified
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            user = obj
        } else {
            user = [:]
        }
        ProviderStyle.customLabels = Dictionary(uniqueKeysWithValues: customProviders.map { ($0.id, $0.label) })
        ProviderStyle.customOrder = customProviders.map(\.id)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: user, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try (data + Data("\n".utf8)).write(to: url, options: .atomic)
            lastModified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        } catch {
            NSSound.beep()
        }
        ProviderStyle.customLabels = Dictionary(uniqueKeysWithValues: customProviders.map { ($0.id, $0.label) })
        ProviderStyle.customOrder = customProviders.map(\.id)
    }

    // MARK: Simple values

    func string(_ key: String) -> String {
        user[key] as? String ?? Self.defaults[key] as? String ?? ""
    }

    func set(_ key: String, _ value: String) {
        if value == Self.defaults[key] as? String { user.removeValue(forKey: key) } else { user[key] = value }
        save()
    }

    func binding(_ key: String) -> Binding<String> {
        Binding(get: { self.string(key) }, set: { self.set(key, $0) })
    }

    // MARK: Providers

    var customProviders: [ProviderInfo] {
        let dict = user["providers"] as? [String: Any] ?? [:]
        return dict.keys.sorted().compactMap { id in
            guard let s = dict[id] as? [String: Any], ProviderInfo.builtins.allSatisfy({ $0.id != id }) else { return nil }
            return ProviderInfo(id: id, label: s["label"] as? String ?? id,
                                kind: ProviderKind(rawValue: s["type"] as? String ?? "") ?? .compatible,
                                baseURL: s["base_url"] as? String, model: s["model"] as? String,
                                editModel: s["edit_model"] as? String, keyURL: nil, builtin: false,
                                catalogID: s["catalog"] as? String)
        }
    }

    /// All providers in fallback order.
    var providers: [ProviderInfo] {
        let all = ProviderInfo.builtins + customProviders
        let order = self.order
        return all.sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
    }

    func provider(_ id: String) -> ProviderInfo? { providers.first { $0.id == id } }

    /// Providers the user added, in order. Until they arrange the list, every provider that is set up.
    func enabled(ready: (String) -> Bool) -> [ProviderInfo] {
        if let explicit = user["order"] as? [String] {
            return explicit.compactMap { id in providers.first { $0.id == id } }
        }
        return providers.filter { ready($0.id) }
    }

    func setEnabled(_ ids: [String]) {
        user["order"] = ids
        save()
    }

    var order: [String] {
        let stored = user["order"] as? [String] ?? Self.defaults["order"] as? [String] ?? []
        let all = (ProviderInfo.builtins + customProviders).map(\.id)
        return stored.filter(all.contains) + all.filter { !stored.contains($0) }
    }

    func moveProviders(from source: IndexSet, to destination: Int) {
        var ids = providers.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        user["order"] = ids
        save()
    }

    func saveCustomProvider(_ p: ProviderInfo) {
        var dict = user["providers"] as? [String: Any] ?? [:]
        var existing = (user["providers"] as? [String: Any])?[p.id] as? [String: Any] ?? [:]
        existing.removeValue(forKey: "edit_model")
        var spec: [String: Any] = existing.merging(["type": p.kind.rawValue, "label": p.label,
                                   "base_url": (p.baseURL ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))]) { $1 }
        spec["model"] = p.model
        if let e = p.editModel, !e.isEmpty { spec["edit_model"] = e }
        if let c = p.catalogID { spec["catalog"] = c }
        dict[p.id] = spec
        user["providers"] = dict
        if let explicit = user["order"] as? [String], !explicit.contains(p.id) {
            user["order"] = explicit + [p.id]  // callers that manage the list set it themselves
        }
        save()
    }

    /// Adds a catalog provider that isn't built into the CLI (OpenRouter, Recraft, ...) and puts it in the order.
    /// Built-in ones (openai, grok, xai, gemini) only need to be added to the order.
    func addCatalogProvider(_ entry: CatalogProvider) {
        if !entry.isBuiltin {
            var dict = user["providers"] as? [String: Any] ?? [:]
            var spec: [String: Any] = ["type": entry.adapter, "label": entry.name, "catalog": entry.id]
            spec["base_url"] = entry.baseURL
            spec["model"] = entry.model
            spec["edit_model"] = entry.editModel
            spec["size_style"] = entry.sizeStyle
            dict[entry.id] = spec
            user["providers"] = dict
        }
        let current = user["order"] as? [String] ?? []
        if !current.contains(entry.id) { user["order"] = current + [entry.id] }
        save()
    }

    func removeCustomProvider(_ id: String) {
        var dict = user["providers"] as? [String: Any] ?? [:]
        dict.removeValue(forKey: id)
        user["providers"] = dict
        if var o = user["order"] as? [String] { o.removeAll { $0 == id }; user["order"] = o }
        var tasks = user["tasks"] as? [String: Any] ?? [:]
        for (t, v) in tasks { if (v as? [String: Any])?["provider"] as? String == id { tasks.removeValue(forKey: t) } }
        user["tasks"] = tasks
        save()
    }

    // MARK: Tasks

    func taskValue(_ task: ImageTask, _ key: String) -> String {
        let t = (user["tasks"] as? [String: Any])?[task.rawValue] as? [String: Any]
        return t?[key] as? String ?? Self.defaultTasks[task.rawValue]?[key] ?? ""
    }

    func setTask(_ task: ImageTask, _ key: String, _ value: String) {
        var tasks = user["tasks"] as? [String: Any] ?? [:]
        var t = tasks[task.rawValue] as? [String: Any] ?? [:]
        if value.isEmpty { t.removeValue(forKey: key) } else { t[key] = value }
        tasks[task.rawValue] = t
        user["tasks"] = tasks
        save()
    }

    func taskBinding(_ task: ImageTask, _ key: String) -> Binding<String> {
        Binding(get: { self.taskValue(task, key) }, set: { self.setTask(task, key, $0) })
    }

    // MARK: Prices

    func price(_ provider: String, _ key: String) -> Double? {
        let p = (user["prices"] as? [String: Any])?[provider] as? [String: Any]
        return (p?[key] as? NSNumber)?.doubleValue ?? catalogPrices[provider]?[key] ?? Self.defaultPrices[provider]?[key]
    }

    func setPrice(_ provider: String, _ key: String, _ value: Double) {
        var prices = user["prices"] as? [String: Any] ?? [:]
        var p = prices[provider] as? [String: Any] ?? [:]
        p[key] = value
        prices[provider] = p
        user["prices"] = prices
        save()
    }

    func priceBinding(_ provider: String, _ key: String) -> Binding<Double> {
        Binding(get: { self.price(provider, key) ?? 0 }, set: { self.setPrice(provider, key, $0) })
    }

    func resetPrices() {
        user.removeValue(forKey: "prices")
        save()
    }

    /// Estimated cost of one run in USD. nil = covered by a subscription.
    func cost(_ e: LogEntry) -> Double? {
        if e.provider == "grok" { return nil }
        if let reported = e.reportedCostUSD { return reported }
        if let u = e.openAIUsage, let out = price(e.provider, "image_out") ?? (e.type == "openai" ? price("openai", "image_out") : nil) {
            let pid = price(e.provider, "image_out") != nil ? e.provider : "openai"
            let textIn = price(pid, "text_in") ?? 0, imageIn = price(pid, "image_in") ?? 0
            let text = u.inputTextTokens ?? 0
            let image = u.inputImageTokens ?? (u.inputTextTokens == nil ? u.inputTokens : max(0, u.inputTokens - text))
            return (Double(text) * textIn + Double(image) * imageIn + Double(u.outputTokens) * out) / 1_000_000
        }
        if let perImage = price(e.provider, "per_image") { return perImage * Double(e.imageCount) }
        return 0
    }
}
