import Foundation
import Testing
@testable import ImageGenKit

@MainActor
struct ParserTests {
    let parser = LogParser()

    @Test func parsesOpenAIRunWithRelativeOutputs() throws {
        let line = #"{"ts": "2026-11-07T12:01:44", "provider": "openai", "model": "gpt-image-2.5-sunburst", "prompt": "a box", "params": {"size": "3840x1280", "quality": "medium", "n": 2}, "refs": ["ref.png"], "outputs": ["out.png"], "usage": {"input_tokens": 2482, "input_tokens_details": {"image_tokens": 2220, "text_tokens": 262}, "output_tokens": 332, "total_tokens": 2814}, "seconds": 19.3, "cwd": "/Users/me/App Projects/SpliX"}"#
        let e = try #require(parser.parse(line: Substring(line), id: 7))
        #expect(e.id == 7)
        #expect(e.provider == "openai")
        #expect(e.type == "openai")
        #expect(e.outputs == ["/Users/me/App Projects/SpliX/out.png"])
        #expect(e.refs == ["/Users/me/App Projects/SpliX/ref.png"])
        #expect(e.project == "SpliX")
        #expect(e.sizeLabel == "3840×1280")
        #expect(e.kindLabel == "Edit")
        #expect(e.openAIUsage?.inputImageTokens == 2220)
        // (262 × $5 + 2220 × $8 + 332 × $30) / 1M = $0.02903
        let cost = try #require(ConfigStore(url: URL(fileURLWithPath: "/nonexistent/config.json")).cost(e))
        #expect(abs(cost - 0.02903) < 0.00001)
        #expect(e.rerunCommand.contains("--size 3840x1280"))
        #expect(e.rerunCommand.contains("-n 2"))
    }

    @Test func parsesGrokRunWithCaller() throws {
        let line = #"{"ts": "2026-11-06T20:00:00", "provider": "grok", "model": "default", "prompt": "it's a test", "params": {"tool": "image_edit", "aspect": "9:16", "n": 1}, "refs": [], "outputs": ["/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Videos/INFFNI/2026-11/Proposed/03.png"], "thumbs": [null], "usage": {"inputTokens": 24253, "outputTokens": 614, "cachedReadTokens": 2304, "costUsdTicks": 165695600, "primaryModelId": "grok-4.7-build"}, "grok_session": "abc", "seconds": 20.4, "cwd": "/tmp/x", "caller": {"agent": "claude", "account": 3, "entrypoint": "t3-code"}}"#
        let e = try #require(parser.parse(line: Substring(line), id: 0))
        #expect(e.provider == "grok")
        #expect(e.isSubscription)
        #expect(ConfigStore(url: URL(fileURLWithPath: "/nonexistent/config.json")).cost(e) == nil)
        #expect(e.project == "Videos · INFFNI")
        #expect(abs((e.grokUsage?.apiValueUSD ?? 0) - 0.01656956) < 1e-8)
        #expect(e.caller?.label == "Claude · account 3 · T3 Code")
        #expect(e.thumbs == [nil])
        #expect(e.rerunCommand.hasPrefix("imagegenkit grok 'it'\\''s a test'"))
    }

    @Test func ignoresBrokenLines() {
        #expect(parser.parse(line: "not json", id: 0) == nil)
        #expect(parser.parse(line: "{}", id: 0) == nil)
    }

    @Test func namesProjectsFromScratchpads() {
        let encodedHome = NSHomeDirectory().replacingOccurrences(of: "/", with: "-")
        let scratch = "/private/tmp/claude-501/\(encodedHome)-Projects-Video-Ideas/c8ced2ad/scratchpad/assets"
        #expect(ProjectNamer.name(cwd: scratch, outputs: ["\(scratch)/a.png"]) == "Video Ideas")
        #expect(ProjectNamer.name(cwd: "/private/tmp/michiller-work3", outputs: ["a.png"]) == "tmp · michiller-work3")
    }

    @Test func thumbKeyMatchesCLI() {
        // python3: hashlib.sha1(b"2026-11-09T00:37:24|/x/y.png").hexdigest()[:16]
        #expect(ImageLocator.thumbKey(ts: "2026-11-09T00:37:24", path: "/x/y.png") == "3247822b278f1fda")
    }
}

@MainActor
struct StoreTests {
    @Test func followsAppendedLinesIncludingPartialWrites() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "imagelog-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = #"{"ts": "2026-11-01T10:00:00", "provider": "grok", "model": "default", "prompt": "a", "params": {}, "refs": [], "outputs": [], "cwd": "/tmp"}"#
        let b = #"{"ts": "2026-11-02T10:00:00", "provider": "openai", "model": "m", "prompt": "b", "params": {}, "refs": [], "outputs": [], "cwd": "/tmp"}"#
        try (a + "\n" + String(b.prefix(20))).write(to: url, atomically: true, encoding: .utf8)
        let store = LogStore(logURL: url)
        store.poll()
        #expect(store.entries.map(\.prompt) == ["a"])

        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data((String(b.dropFirst(20)) + "\n").utf8))
        try h.close()
        store.poll()
        #expect(store.entries.map(\.prompt) == ["a", "b"])
        #expect(store.entries.map(\.id) == [0, 1])
    }

    @Test func statsSplitProviders() throws {
        let parser = LogParser()
        let lines = [
            #"{"ts": "2026-11-01T10:00:00", "provider": "grok", "model": "default", "prompt": "a", "params": {}, "refs": [], "outputs": ["/a.jpg"], "usage": {"costUsdTicks": 100000000}, "cwd": "/tmp/p", "seconds": 20}"#,
            #"{"ts": "2026-11-01T11:00:00", "provider": "openai", "model": "gpt-image-2.5-flare", "prompt": "b", "params": {}, "refs": [], "outputs": ["/b.png", "/c.png"], "usage": {"input_tokens": 100, "output_tokens": 1000, "total_tokens": 1100}, "cwd": "/tmp/p", "seconds": 30}"#,
        ]
        let entries = lines.enumerated().compactMap { parser.parse(line: Substring($1), id: $0) }
        let config = ConfigStore(url: URL(fileURLWithPath: "/nonexistent/config.json"))
        let s = Stats(entries: entries, rangeStart: nil, cost: config.cost)
        #expect(s.images == 3)
        #expect(s.paidImages == 2)
        #expect(s.providers == ["openai", "grok"])
        // no input details: all 100 input tokens priced as image input ($8) + 1000 × $30
        #expect(abs(s.cost - 0.0308) < 1e-9)
        #expect(s.months.count == 1)
    }
}

@MainActor
struct ConfigTests {
    @Test func writesOnlyChangedKeysAndRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "igk-\(UUID().uuidString)/config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let c = ConfigStore(url: url)
        #expect(c.taskValue(.draft, "provider") == "grok")
        #expect(c.order.prefix(2) == ["grok", "openai"])
        c.setTask(.draft, "provider", "openai")
        c.set("resolution", "2K")  // default: not written
        c.setPrice("xai", "per_image", 0.04)
        c.saveCustomProvider(ProviderInfo(id: "together", label: "Together", kind: .compatible,
                                          baseURL: "https://api.together.xyz/v1/", model: "flux", builtin: false))
        let reread = ConfigStore(url: url)
        #expect(reread.taskValue(.draft, "provider") == "openai")
        #expect(reread.taskValue(.draft, "quality") == "low")  // default preset still applies
        #expect(reread.user["resolution"] == nil)
        #expect(reread.price("xai", "per_image") == 0.04)
        #expect(reread.provider("together")?.baseURL == "https://api.together.xyz/v1")
        #expect(reread.order.last == "together")
        reread.moveProviders(from: IndexSet(integer: reread.order.count - 1), to: 0)
        #expect(ConfigStore(url: url).order.first == "together")
        reread.removeCustomProvider("together")
        #expect(ConfigStore(url: url).provider("together") == nil)
    }

    @Test func versionCompare() {
        #expect(Installer.compare("1.0.0", "1.0") == 0)
        #expect(Installer.compare("1.2", "1.10") == -1)
        #expect(Installer.compare("2.0.1", "2.0.0") == 1)
    }
}
