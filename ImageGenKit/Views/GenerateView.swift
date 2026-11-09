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
    @AppStorage("generate.count") private var count = 1
    @AppStorage("generate.compression") private var compression = 85.0
    @AppStorage("generate.moderation") private var moderation = "auto"
    // Per provider: prefilled from Settings › Images, edits kept for this app session (GenerateSession).
    @State private var size = "2K"
    @State private var quality = "medium"
    @State private var background = "auto"
    @State private var format = "png"
    @State private var model = ""
    @State private var loadedFor = ""
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

    private var options: GenerateOptions {
        GenerateOptions(aspect: aspect, size: size, count: count, quality: quality, background: background,
                        format: format, compression: compression, moderation: moderation, model: model)
    }

    /// Loads a provider's options: this session's edits, else its saved defaults.
    private func load(_ p: ProviderInfo?) {
        guard let p, p.id != loadedFor else { return }
        let edited = GenerateSession.values[p.id] ?? [:]
        size = edited["resolution"] ?? GenerateSpec.initial(p, "resolution", config: config)
        quality = edited["quality"] ?? GenerateSpec.initial(p, "quality", config: config)
        background = edited["background"] ?? GenerateSpec.initial(p, "background", config: config)
        format = edited["format"] ?? GenerateSpec.initial(p, "format", config: config)
        model = edited["model"] ?? ""
        loadedFor = p.id
    }

    private func remember() {
        guard !loadedFor.isEmpty else { return }
        GenerateSession.values[loadedFor] = ["resolution": size, "quality": quality, "background": background,
                                             "format": format, "model": model]
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
        .onChange(of: provider?.id, initial: true) { load(provider) }
        .onChange(of: [size, quality, background, format, model]) { remember() }
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
            AppIconView(size: 30)
            Text("Generate").font(.title3.weight(.semibold))
            Spacer()
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
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
                    }
                    .buttonStyle(.bordered)
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
                    Label("More", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showMore, arrowEdge: .bottom) { moreOptions(p) }
                .help("More options")
            }
        }
    }

    private func moreOptions(_ p: ProviderInfo) -> some View {
        let qualities = GenerateSpec.qualities(p.kind)
        let backgrounds = GenerateSpec.backgrounds(p.kind)
        let formats = GenerateSpec.formats(p.kind)
        let openai = p.kind == .openai
        return VStack(alignment: .leading, spacing: 0) {
            if !qualities.isEmpty {
                row("Quality") {
                    GenerateSegmented(options: ["auto"] + qualities, selection: $quality, label: \.capitalized)
                }
            }
            if !backgrounds.isEmpty {
                if !qualities.isEmpty { divider }
                row("Background") {
                    GenerateSegmented(options: backgrounds, selection: Binding(get: { background }, set: {
                        background = $0
                        if $0 == "transparent" && format == "jpeg" { format = "png" }
                    }), label: \.capitalized)
                }
            }
            if !formats.isEmpty {
                if !qualities.isEmpty || !backgrounds.isEmpty { divider }
                row("Format") {
                    HStack(spacing: 14) {
                        GenerateSegmented(options: formats, selection: Binding(get: { format }, set: {
                            format = $0
                            if $0 == "jpeg" && background == "transparent" { background = "auto" }
                        }), label: GenerateSpec.formatLabel)
                        if openai && format != "png" {
                            Slider(value: $compression, in: 0...100, step: 5).frame(width: 110)
                            Text("\(Int(compression))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                        }
                    }
                }
            }
            if openai {
                divider
                row("Moderation") {
                    GenerateSegmented(options: GenerateSpec.moderations, selection: $moderation, label: \.capitalized)
                }
                if !refs.isEmpty {
                    divider
                    row("Mask") { maskControl }
                }
            }
            if GenerateSpec.hasModel(p.kind) {
                if !qualities.isEmpty || !backgrounds.isEmpty || !formats.isEmpty { divider }
                row("Model") { modelField(p) }
            }
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
            TextField("Model", text: $model, prompt: Text(placeholder.isEmpty ? "Default" : placeholder))
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 270)
            if !suggestions.isEmpty {
                Menu {
                    Button("Default") { model = "" }
                    Divider()
                    ForEach(suggestions, id: \.self) { m in Button(m) { model = m } }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
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
            }
            .buttonStyle(.bordered)
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
                    Label("Options", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
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
                if running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating")
                    }
                } else {
                    Label(phase == .compose ? "Generate" : "Generate Again", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Generate (⌘↩)")
            .disabled(!canGenerate)
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
        if GenerateSpec.qualities(p.kind).contains(quality) { parts.append(quality.capitalized) }
        if background == "transparent", GenerateSpec.backgrounds(p.kind).contains(background) { parts.append("Transparent") }
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

/// Options the user changed in the Generate panel, per provider id, until the app quits.
enum GenerateSession {
    static var values: [String: [String: String]] = [:]
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
