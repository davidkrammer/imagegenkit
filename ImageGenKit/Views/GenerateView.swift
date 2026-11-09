import AppKit
import SwiftUI

/// Manual image generation panel. Present it as a sheet:
/// `.sheet(isPresented: $show) { GenerateView(references: [url]) }`
struct GenerateView: View {
    var references: [URL] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @Environment(Catalog.self) private var catalog
    @Environment(LogStore.self) private var store

    @AppStorage("generate.prompt") private var prompt = ""
    @AppStorage("generate.provider") private var providerID = ""
    @AppStorage("generate.aspect") private var aspect = GenerateSpec.auto
    @AppStorage("generate.size") private var size = "2K"
    @AppStorage("generate.count") private var count = 1
    @AppStorage("generate.quality") private var quality = "medium"
    @AppStorage("generate.background") private var background = "auto"
    @AppStorage("generate.format") private var format = "png"
    @AppStorage("generate.compression") private var compression = 85.0
    @AppStorage("generate.moderation") private var moderation = "auto"
    @AppStorage("generate.models") private var modelsJSON = "{}"
    @State private var showMore = false

    @State private var refs: [URL] = []
    @State private var mask: URL?
    @State private var phase = Phase.compose
    @State private var error: GenerateError?
    @State private var showDetails = false
    @State private var dropTargeted = false
    @FocusState private var promptFocused: Bool

    enum Phase: Equatable {
        case compose
        case running(Date)
        case done([URL], seconds: Int)
    }

    struct GenerateError: Equatable {
        let message: String
        let details: String
    }

    init(references: [URL] = []) {
        self.references = references
        _refs = State(initialValue: references)
    }

    // MARK: Derived

    private var ready: [ProviderInfo] { config.providers.filter { status.state($0.id).isReady } }
    private var provider: ProviderInfo? { ready.first { $0.id == providerID } ?? ready.first }
    private var running: Bool { if case .running = phase { true } else { false } }
    private var canGenerate: Bool {
        provider != nil && !running && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var models: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(modelsJSON.utf8))) ?? [:]
    }

    private var modelBinding: Binding<String> {
        Binding(get: { models[provider?.id ?? ""] ?? "" }, set: { value in
            guard let id = provider?.id else { return }
            var m = models
            m[id] = value.isEmpty ? nil : value
            modelsJSON = (try? String(decoding: JSONEncoder().encode(m), as: UTF8.self)) ?? "{}"
        })
    }

    private var options: GenerateOptions {
        GenerateOptions(aspect: aspect, size: size, count: count, quality: quality, background: background,
                        format: format, compression: compression, moderation: moderation, model: modelBinding.wrappedValue)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 18) {
                promptCard
                switch phase {
                case .compose:
                    settings
                case .running(let start):
                    GenerateProgressView(start: start, provider: provider?.label ?? "")
                        .transition(.opacity)
                case .done(let urls, let seconds):
                    results(urls, seconds: seconds)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 760, height: 620)
        .background(Theme.background)
        .animation(.smooth(duration: 0.3), value: phase)
        .animation(.smooth(duration: 0.25), value: refs)
        .task {
            if config.providers.contains(where: { status.state($0.id) == .unknown }) {
                await status.refresh(config.providers)
            }
            if refs.isEmpty == false || prompt.isEmpty { promptFocused = true }
            #if DEBUG
            debugState()
            #endif
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "sparkles", size: 28)
            Text("Generate").font(.title3.weight(.semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Theme.well, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Prompt + references

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe the image…")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .focused($promptFocused)
                    .disabled(running)
            }
            .frame(minHeight: phase == .compose ? 90 : 44, maxHeight: phase == .compose ? .infinity : 44)

            if phase == .compose || !refs.isEmpty {
            HStack(spacing: 10) {
                ForEach(refs, id: \.self) { url in
                    GenerateReferenceTile(url: url) { remove(url) }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if refs.isEmpty {
                    Button(action: pickReferences) {
                        Label("Add images", systemImage: "photo.badge.plus")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Theme.well, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Add reference images, or drop them here")
                } else if refs.count < 8 {
                    GenerateAddTile(action: pickReferences)
                }
                Spacer(minLength: 0)
            }
            .disabled(running)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(dropTargeted ? Theme.accent : Color.primary.opacity(promptFocused ? 0.14 : 0.07),
                              lineWidth: dropTargeted ? 2 : 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .dropDestination(for: URL.self) { urls, _ in
            addReferences(urls)
            return urls.contains(where: GenerateImageLoader.isImage)
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
    }

    // MARK: Settings

    @ViewBuilder private var settings: some View {
        if ready.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                Text("No provider set up yet.").foregroundStyle(.secondary)
                SettingsLink { Text("Open Settings") }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: 120)
        } else if let provider {
            VStack(alignment: .leading, spacing: 18) {
                GenerateField(title: "Provider") {
                    HStack(spacing: 8) {
                        ForEach(ready) { p in
                            GenerateProviderChip(provider: p, selected: p.id == provider.id) {
                                providerID = p.id
                            }
                        }
                    }
                }
                commonOptions(provider)
            }
        }
    }

    private func commonOptions(_ p: ProviderInfo) -> some View {
        HStack(alignment: .bottom, spacing: 22) {
            GenerateField(title: "Aspect") {
                GenerateAspectMenu(options: GenerateSpec.aspects(p.kind), selection: validated($aspect, GenerateSpec.aspects(p.kind)))
            }
            let sizes = GenerateSpec.sizes(p.kind)
            if !sizes.isEmpty {
                GenerateField(title: "Size") {
                    GenerateSegmented(options: sizes, selection: validated($size, sizes, fallback: sizes[min(1, sizes.count - 1)]))
                }
            }
            GenerateField(title: "Images") {
                GenerateSegmented(options: GenerateSpec.counts,
                                  selection: Binding(get: { String(count) }, set: { count = Int($0) ?? 1 }))
            }
            Spacer(minLength: 0)
            if GenerateSpec.hasMore(p.kind) {
                Button {
                    showMore.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text("More")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showMore ? 180 : 0))
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(showMore ? Theme.accent : .secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showMore, arrowEdge: .bottom) { moreOptions(p) }
                .help("More options")
            }
        }
    }

    private func moreOptions(_ p: ProviderInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if p.kind == .openai {
                row("Quality") {
                    GenerateSegmented(options: GenerateSpec.qualities, selection: $quality, label: \.capitalized)
                }
                divider
                row("Background") {
                    GenerateSegmented(options: GenerateSpec.backgrounds, selection: Binding(get: { background }, set: {
                        background = $0
                        if $0 == "transparent" && format == "jpeg" { format = "png" }
                    }), label: \.capitalized)
                }
                divider
                row("Format") {
                    HStack(spacing: 14) {
                        GenerateSegmented(options: GenerateSpec.formats, selection: Binding(get: { format }, set: {
                            format = $0
                            if $0 == "jpeg" && background == "transparent" { background = "auto" }
                        }), label: { $0 == "jpeg" ? "JPEG" : $0 == "webp" ? "WebP" : "PNG" })
                        if format != "png" {
                            Slider(value: $compression, in: 0...100, step: 5).frame(width: 110)
                            Text("\(Int(compression))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                        }
                    }
                }
                divider
                row("Moderation") {
                    GenerateSegmented(options: GenerateSpec.moderations, selection: $moderation, label: \.capitalized)
                }
                if !refs.isEmpty {
                    divider
                    row("Mask") { maskControl }
                }
                divider
            }
            row("Model") { modelField(p) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .fixedSize()
        .presentationBackground(Theme.card)
    }

    private var divider: some View { Divider().opacity(0.6) }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .font(.callout)
        .frame(minHeight: 46)
    }

    private func modelField(_ p: ProviderInfo) -> some View {
        let suggestions = GenerateSpec.modelSuggestions(p, catalog: catalog, config: config)
        let placeholder = GenerateSpec.defaultModel(p, config: config, editing: !refs.isEmpty)
        return HStack(spacing: 6) {
            TextField("Model", text: modelBinding, prompt: Text(placeholder.isEmpty ? "Default" : placeholder))
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(width: 270, height: 30)
                .background(Theme.well, in: Capsule())
            if !suggestions.isEmpty {
                Menu {
                    Button("Default") { modelBinding.wrappedValue = "" }
                    Divider()
                    ForEach(suggestions, id: \.self) { m in Button(m) { modelBinding.wrappedValue = m } }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Theme.well, in: Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Models")
            }
        }
    }

    @ViewBuilder private var maskControl: some View {
        if let mask {
            HStack(spacing: 8) {
                GenerateReferenceTile(url: mask, size: 30) { self.mask = nil }
                Text(mask.lastPathComponent).lineLimit(1).truncationMode(.middle).frame(maxWidth: 200, alignment: .leading)
            }
        } else {
            Button { mask = GenerateFilePicker.images(multiple: false).first } label: {
                Label("Choose…", systemImage: "square.dashed")
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.well, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("PNG with transparent areas to change")
        }
    }

    // MARK: Results

    private func results(_ urls: [URL], seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(urls.count == 1 ? "1 image · \(seconds) s" : "\(urls.count) images · \(seconds) s",
                      systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .labelStyle(GenerateTintedIconLabelStyle(tint: .green))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    phase = .compose
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3").font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            let rows = urls.count <= 2 ? [Array(urls)] : [Array(urls.prefix(2)), Array(urls.dropFirst(2))]
            VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 16) {
                        ForEach(rows[r], id: \.self) { url in
                            GenerateResultTile(url: url, compact: urls.count > 1) { useAsReference(url) }
                        }
                        if urls.count > 2 && rows[r].count == 1 { Color.clear }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error.message).lineLimit(1).truncationMode(.tail).help(error.message)
                if !error.details.isEmpty {
                    Button("Details") { showDetails.toggle() }
                        .buttonStyle(.link)
                        .popover(isPresented: $showDetails, arrowEdge: .top) {
                            ScrollView {
                                Text(error.details)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            }
                            .frame(width: 460, height: 220)
                        }
                }
            } else if running {
                Text("Keeps running if you close this.").foregroundStyle(.tertiary)
            } else if let provider, provider.kind != .grokBuild, case .compose = phase {
                Text(summary(provider)).foregroundStyle(.tertiary).monospacedDigit()
            }
            Spacer(minLength: 8)
            Button(action: generate) {
                HStack(spacing: 8) {
                    if running {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Generating")
                    } else {
                        Image(systemName: "sparkles")
                        Text(phase == .compose ? "Generate" : "Generate Again")
                    }
                    Text("⌘↩").font(.callout).opacity(0.65)
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canGenerate)
            .opacity(canGenerate || running ? 1 : 0.45)
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.background)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private func summary(_ p: ProviderInfo) -> String {
        var parts = [GenerateSpec.aspects(p.kind).contains(aspect) ? aspect : GenerateSpec.auto]
        let sizes = GenerateSpec.sizes(p.kind)
        if !sizes.isEmpty { parts.append(sizes.contains(size) ? size : sizes[min(1, sizes.count - 1)]) }
        if p.kind == .openai { parts.append(quality.capitalized) }
        parts.append(count == 1 ? "1 image" : "\(count) images")
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func generate() {
        guard canGenerate, let provider else { return }
        let args = options.arguments(for: provider, references: refs, mask: mask)
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = Date()
        error = nil
        showDetails = false
        phase = .running(start)
        Task {
            let r = await installer.runCLI(args, stdin: text)
            let urls = GenerateOutcome.images(r.stdout)
            store.poll()
            if r.status == 0 && !urls.isEmpty {
                phase = .done(urls, seconds: Int(Date().timeIntervalSince(start).rounded()))
            } else {
                error = GenerateError(message: GenerateOutcome.message(r.stderr, status: r.status),
                                      details: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                phase = .compose
            }
        }
    }

    private func pickReferences() { addReferences(GenerateFilePicker.images()) }

    private func addReferences(_ urls: [URL]) {
        for url in urls where GenerateImageLoader.isImage(url) && !refs.contains(url) { refs.append(url) }
    }

    private func remove(_ url: URL) {
        refs.removeAll { $0 == url }
        if refs.isEmpty { mask = nil }
    }

    private func useAsReference(_ url: URL) {
        addReferences([url])
        phase = .compose
        promptFocused = true
    }

    /// A binding that shows `fallback` (or the first option) when the stored value doesn't fit this provider.
    private func validated(_ b: Binding<String>, _ options: [String], fallback: String? = nil) -> Binding<String> {
        Binding(get: { options.contains(b.wrappedValue) ? b.wrappedValue : (fallback ?? options.first ?? "") },
                set: { b.wrappedValue = $0 })
    }

    #if DEBUG
    /// `-debugGenerateState results|running|error`, `-debugGenerateCount N`, `-debugGenerateRefs N`,
    /// `-debugGenerateMore YES`, `-debugGeneratePrompt "…"` (screenshots).
    private func debugState() {
        switch UserDefaults.standard.string(forKey: "debugGenerateState") {
        case "results":
            let urls = store.entries.reversed().flatMap(\.outputs).map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            let n = max(1, UserDefaults.standard.integer(forKey: "debugGenerateCount"))
            if !urls.isEmpty { phase = .done(Array(urls.prefix(n)), seconds: 23) }
        case "running":
            phase = .running(Date().addingTimeInterval(-12))
        case "error":
            error = GenerateError(message: "OpenAI: billing hard limit reached", details: "openai -> request failed (HTTP 400)\nimagegenkit: OpenAI: billing hard limit reached")
        default: break
        }
        if let p = UserDefaults.standard.string(forKey: "debugGeneratePrompt") { prompt = p }
        let latest = store.entries.reversed().flatMap(\.outputs).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let refCount = UserDefaults.standard.integer(forKey: "debugGenerateRefs")
        if refCount > 0 { refs = Array(latest.dropFirst(4).prefix(refCount)) }
        if UserDefaults.standard.bool(forKey: "debugGenerateMore") {
            Task { try? await Task.sleep(for: .seconds(1)); showMore = true }
        }
    }
    #endif
}

/// DEBUG-only: opens GenerateView at launch with `-debugGenerate YES` (for screenshots).
/// Attach once in RootView: `.background(GenerateDebugPresenter())`. Does nothing in Release builds.
struct GenerateDebugPresenter: View {
    #if DEBUG
    @State private var show = UserDefaults.standard.bool(forKey: "debugGenerate")
    #endif

    var body: some View {
        #if DEBUG
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: $show) { GenerateView() }
        #else
        EmptyView()
        #endif
    }
}
