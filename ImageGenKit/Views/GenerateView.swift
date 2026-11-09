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

    /// Fits under the toolbar of the window it opens on (the window can be as small as 860 × 560).
    @State private var height: CGFloat

    init(references: [URL] = []) {
        self.references = references
        _refs = State(initialValue: references)
        _height = State(initialValue: Self.fittingHeight())
    }

    private static func fittingHeight(_ window: NSWindow? = nil) -> CGFloat {
        let window = window ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.styleMask.contains(.titled) && $0.sheetParent == nil && $0.frame.height > 200 }
        return window.map { max(460, min(590, $0.frame.height - 64)) } ?? 590
    }

    // MARK: Derived

    private var ready: [ProviderInfo] { config.providers.filter { status.state($0.id).isReady } }
    private var provider: ProviderInfo? { ready.first { $0.id == providerID } ?? ready.first }
    /// Whether the first provider check has finished (so "no provider" isn't shown too early).
    private var statusChecked: Bool {
        config.providers.isEmpty || config.providers.contains { status.state($0.id) != .unknown }
    }
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
            VStack(alignment: .leading, spacing: 16) {
                switch phase {
                case .compose:
                    promptWell.generateEnter(0)
                    if let error { errorBanner(error).transition(.opacity.combined(with: .move(edge: .top))) }
                    settings
                case .running(let start):
                    promptSummary
                    GenerateStagePanel { placeholders(start) }
                        .transition(.opacity)
                case .done(let urls, _):
                    promptSummary
                    GenerateStagePanel { results(urls) }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 720, height: height)
        .background(Theme.card)
        .overlay(alignment: .topTrailing) { closeButton }
        .animation(.smooth(duration: 0.3), value: phase)
        .animation(.smooth(duration: 0.25), value: refs)
        .animation(.smooth(duration: 0.25), value: error)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            // Follow the window this sheet is attached to.
            if let window = note.object as? NSWindow, window.sheetParent == nil, window.attachedSheet != nil {
                height = Self.fittingHeight(window)
            }
        }
        .onChange(of: provider?.id, initial: true) { load(provider) }
        .onChange(of: [size, quality, background, format, model]) { remember() }
        .task {
            height = Self.fittingHeight()
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
        GenerateHeader(title: "Generate") {
            switch phase {
            case .compose:
                Text(ready.isEmpty && statusChecked ? "Add a provider to start." : "Describe an image, pick a provider.")
            case .running(let start):
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    Text("\(provider?.label ?? "Working") · \(Int(max(0, ctx.date.timeIntervalSince(start)))) s")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            case .done(let urls, let seconds):
                Text("\(urls.count == 1 ? "1 image" : "\(urls.count) images") in \(seconds) s").monospacedDigit()
            }
        } accessory: {
            switch phase {
            case .compose: EmptyView()
            case .running: GenerateTag(text: "Working", pulsing: true)
            case .done: GenerateTag(text: "Done", color: .green)
            }
        }
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(14)
    }

    // MARK: Prompt + references

    private var promptWell: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe an image…")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .focused($promptFocused)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .frame(minHeight: 70, maxHeight: .infinity)

            referenceBar
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 6)
        }
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(promptFocused ? Theme.accent.opacity(0.7) : Color.primary.opacity(0.05), lineWidth: promptFocused ? 1.5 : 1))
        .overlay { if dropTargeted { dropOverlay.transition(.opacity) } }
        .dropDestination(for: URL.self) { urls, _ in
            addReferences(urls)
            return urls.contains(where: GenerateImageLoader.isImage)
        } isTargeted: { dropTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .animation(.easeOut(duration: 0.15), value: promptFocused)
    }

    private var referenceBar: some View {
        HStack(spacing: 10) {
            ForEach(refs, id: \.self) { url in
                GenerateReferenceTile(url: url, size: 52) { remove(url) }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if refs.isEmpty {
                Button(action: pickReferences) {
                    Label("Add images", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("o")
                .help("Add reference images (⌘O), or drop them here")
                Text("or drop them here").font(.callout).foregroundStyle(.tertiary)
            } else if refs.count < 8 {
                GenerateAddTile(size: 52, action: pickReferences)
                    .keyboardShortcut("o")
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Theme.accent.opacity(0.1))
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text("Drop to add as reference").font(.headline)
                }
            }
            .allowsHitTesting(false)
    }

    /// The prompt, read-only, while running and on the results.
    private var promptSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "text.cursor").foregroundStyle(Theme.accent)
            Text(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 14))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .help(prompt)
            if !refs.isEmpty {
                HStack(spacing: -10) {
                    ForEach(refs.prefix(4), id: \.self) { url in
                        GenerateReferenceThumb(url: url, size: 32)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ error: GenerateError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(error.message)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if !error.details.isEmpty {
                Button("Details") { showDetails.toggle() }
                    .buttonStyle(.link)
                    .popover(isPresented: $showDetails, arrowEdge: .bottom) {
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
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Settings

    @ViewBuilder private var settings: some View {
        if ready.isEmpty {
            if statusChecked {
                noProvider.generateEnter(1)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 150)
            }
        } else if let provider {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    rowLabel("Provider")
                    GenerateFlowLayout(spacing: 8) {
                        ForEach(ready) { p in
                            GenerateProviderChip(provider: p, selected: p.id == provider.id) {
                                withAnimation(.snappy(duration: 0.2)) { providerID = p.id }
                            }
                        }
                    }
                }
                .generateEnter(1)
                GridRow {
                    rowLabel("Aspect")
                    let aspects = GenerateSpec.aspects(provider.kind)
                    let current = validated($aspect, aspects)
                    HStack(spacing: 10) {
                        GenerateAspectMenu(options: aspects, selection: current)
                        GenerateAspectShape(aspect: current.wrappedValue, box: 18)
                            .foregroundStyle(.secondary)
                            .animation(.snappy(duration: 0.2), value: current.wrappedValue)
                    }
                }
                .generateEnter(2)
                let sizes = GenerateSpec.sizes(provider.kind)
                if !sizes.isEmpty {
                    GridRow {
                        rowLabel("Size")
                        GenerateSegmented(options: sizes, selection: validated($size, sizes, fallback: sizes[min(1, sizes.count - 1)]))
                    }
                    .generateEnter(3)
                }
                GridRow {
                    rowLabel("Images")
                    GenerateSegmented(options: GenerateSpec.counts,
                                      selection: Binding(get: { String(count) }, set: { count = Int($0) ?? 1 }))
                }
                .generateEnter(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .leading)
    }

    /// Looks like a tour step: picture, title, one line, one action.
    private var noProvider: some View {
        HStack(spacing: 16) {
            IconBadge(symbol: "key.fill", size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("No provider yet").font(.system(size: 15, weight: .semibold))
                Text("Add a Grok, ChatGPT or API account.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            SettingsLink { Text("Add Provider") }
                .buttonStyle(.borderedProminent)
        }
        .card(padding: 18)
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

    // MARK: Running + results

    /// Rows of at most two: 1 → [1], 2 → [2], 3 → [2, 1], 4 → [2, 2].
    private func rows<T>(_ items: [T]) -> [[T]] {
        items.count <= 2 ? [items] : [Array(items.prefix(2)), Array(items.dropFirst(2))]
    }

    private func placeholders(_ start: Date) -> some View {
        let shown = provider.map { GenerateSpec.aspects($0.kind).contains(aspect) ? aspect : GenerateSpec.auto } ?? GenerateSpec.auto
        let slots = rows(Array(0..<max(1, count)))
        return VStack(spacing: 14) {
            ForEach(slots.indices, id: \.self) { r in
                HStack(spacing: 14) {
                    ForEach(slots[r], id: \.self) { i in
                        GenerateCanvasPlaceholder(aspect: shown)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .generatePop(0.05 + Double(i) * 0.08)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func results(_ urls: [URL]) -> some View {
        let grid = rows(urls)
        return VStack(spacing: 14) {
            ForEach(grid.indices, id: \.self) { r in
                HStack(spacing: 18) {
                    ForEach(grid[r], id: \.self) { url in
                        GenerateResultTile(url: url, compact: urls.count > 1) { useAsReference(url) }
                    }
                    if urls.count > 2 && grid[r].count == 1 { Color.clear }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            switch phase {
            case .compose:
                if let provider, GenerateSpec.hasMore(provider.kind), !ready.isEmpty {
                    Button { showMore.toggle() } label: {
                        Label("More", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showMore, arrowEdge: .top) { moreOptions(provider) }
                    .help("More options")
                    let extras = moreSummary(provider)
                    if !extras.isEmpty {
                        Text(extras).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            case .running:
                Text("Keeps running if you close this.").foregroundStyle(.tertiary)
            case .done:
                Button { phase = .compose } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .help("Change the prompt or options")
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
        .padding(.horizontal, 26)
        .frame(height: 62)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }

    /// What "More" changed from the provider's plain defaults, e.g. "High · Transparent · WebP".
    private func moreSummary(_ p: ProviderInfo) -> String {
        var parts: [String] = []
        if GenerateSpec.qualities(p.kind).contains(quality) { parts.append(quality.capitalized) }
        if background == "transparent", GenerateSpec.backgrounds(p.kind).contains(background) { parts.append("Transparent") }
        if format != "png", GenerateSpec.formats(p.kind).contains(format) { parts.append(GenerateSpec.formatLabel(format)) }
        let m = model.trimmingCharacters(in: .whitespaces)
        if GenerateSpec.hasModel(p.kind), !m.isEmpty { parts.append(m) }
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

