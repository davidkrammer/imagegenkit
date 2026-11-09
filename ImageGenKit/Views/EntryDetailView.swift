import SwiftUI

struct EntryDetailView: View {
    let entry: LogEntry
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config
    @State private var reference: DetailReference?

    var body: some View {
        let index = min(store.selectedImageIndex, max(entry.outputs.count - 1, 0))
        let ref: ImageRef? = entry.outputs.isEmpty ? nil : entry.imageRef(index)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let ref {
                    LargePreview(ref: ref)
                    if entry.outputs.count > 1 { strip(selected: index) }
                }

                DetailFlow(spacing: 6) {
                    ProviderBadge(provider: entry.provider)
                    Pill(text: entry.modelLabel)
                    Pill(text: entry.sizeLabel)
                    if let q = entry.param("quality") { Pill(text: q.capitalized) }
                    if let c = config.cost(entry) {
                        Pill(text: Format.usd(c, precise: true), color: .primary)
                    } else {
                        Pill(text: "Subscription")
                    }
                    Pill(text: Format.seconds(entry.seconds))
                }

                DetailPromptCard(prompt: entry.prompt)

                actions(ref: ref, index: index)

                details

                if !entry.refs.isEmpty { references }
            }
            .padding(20)
        }
        .background(Theme.background)
        .sheet(item: $reference) { ref in
            GenerateView(references: [ref.url])
        }
    }

    // MARK: Pieces

    private func strip(selected: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entry.outputs.indices, id: \.self) { i in
                    ThumbnailView(ref: entry.imageRef(i))
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(i == selected ? Theme.accent : Color.primary.opacity(0.08),
                                              lineWidth: i == selected ? 2.5 : 1)
                        }
                        .opacity(i == selected ? 1 : 0.75)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { store.selectedImageIndex = i } }
                }
            }
            .padding(2)
        }
    }

    private func actions(ref: ImageRef?, index: Int) -> some View {
        let path = ref.map { entry.outputs[$0.index] }
        let fileExists = path.map(ImageLocator.exists) ?? false
        let referenceSource: URL? = ref.flatMap { ImageLocator.source(for: $0)?.url ?? ImageLocator.existingThumb(for: $0) }
        return HStack(spacing: 8) {
            DetailActionButton(symbol: "arrow.up.forward.app", help: "Open") {
                if let ref { Actions.open(ref) }
            }
            .disabled(ref == nil)
            DetailActionButton(symbol: "folder", help: "Show in Finder") {
                if let path { Actions.reveal(path) }
            }
            .disabled(!fileExists)
            DetailActionButton(symbol: "text.quote", help: "Copy prompt", copies: true) {
                Actions.copy(entry.prompt)
            }
            DetailActionButton(symbol: "terminal", help: "Copy command", copies: true) {
                Actions.copy(entry.rerunCommand)
            }
            Spacer(minLength: 0)
            DetailActionButton(symbol: "wand.and.sparkles", help: "Use as reference", prominent: true) {
                reference = referenceSource.map(DetailReference.init)
            }
            .disabled(referenceSource == nil)
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            row("Date", entry.date.formatted(date: .abbreviated, time: .shortened))
            row("Project", entry.project)
            if let c = entry.caller, !c.label.isEmpty { row("Started by", c.label) }
            if let u = entry.openAIUsage {
                row("Tokens", "\(Format.tokens(u.inputTokens)) in · \(Format.tokens(u.outputTokens)) out")
            }
            row("Folder", (entry.cwd as NSString).abbreviatingWithTildeInPath, middle: true)
            if let note = missingNote {
                row("File", note)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func row(_ label: String, _ value: String, middle: Bool = false) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.tertiary).gridColumnAlignment(.leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(middle ? 1 : 2)
                .truncationMode(middle ? .middle : .tail)
                .help(value)
        }
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("References").font(.callout).foregroundStyle(.tertiary)
            DetailFlow(spacing: 8) {
                ForEach(entry.refs, id: \.self) { DetailReferenceThumb(path: $0) }
            }
        }
        .padding(.horizontal, 2)
    }

    private var missingNote: String? {
        let i = min(store.selectedImageIndex, max(entry.outputs.count - 1, 0))
        guard i < entry.outputs.count, !ImageLocator.exists(entry.outputs[i]) else { return nil }
        let ref = entry.imageRef(i)
        if ImageLocator.source(for: ref)?.kind == .grokCopy { return "Deleted · Grok copy left" }
        if ImageLocator.existingThumb(for: ref) != nil { return "Deleted · preview left" }
        return "Deleted"
    }
}

/// The image handed to GenerateView as a reference.
private struct DetailReference: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Components

/// Prompt text in a card, with a copy icon.
private struct DetailPromptCard: View {
    let prompt: String
    @State private var copied = false

    var body: some View {
        Text(prompt)
            .font(.callout)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 22)
            .card(padding: 14, radius: 14)
            .overlay(alignment: .topTrailing) {
                Button {
                    Actions.copy(prompt)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("Copy prompt")
                .padding(8)
            }
    }
}

/// Square icon button on a card surface, with hover and an optional "copied" checkmark.
private struct DetailActionButton: View {
    let symbol: String
    let help: String
    var copies = false
    var prominent = false
    let action: () -> Void
    @State private var hovering = false
    @State private var done = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let button = Button {
            action()
            guard copies else { return }
            done = true
            Task { try? await Task.sleep(for: .seconds(1.2)); done = false }
        } label: {
            Label(help, systemImage: done ? "checkmark" : symbol)
                .labelStyle(.iconOnly)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: 20)
        }
        .controlSize(.large)
        .help(help)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

/// Small thumbnail of a reference image; click shows it in Finder.
private struct DetailReferenceThumb: View {
    let path: String
    @State private var image: CGImage?

    var body: some View {
        Theme.well
            .frame(width: 44, height: 44)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .help((path as NSString).lastPathComponent)
            .onTapGesture { if ImageLocator.exists(path) { Actions.reveal(path) } }
            .task(id: path) {
                let url = URL(fileURLWithPath: path)
                image = await Task.detached(priority: .utility) { Thumbnails.downsample(url, maxPixel: 120) }.value
            }
    }
}

/// Wrapping row layout for chips.
struct DetailFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: - Large preview

private struct LargePreview: View {
    let ref: ImageRef
    @State private var result: (image: CGImage, kind: SourceKind)?
    @State private var loaded = false

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        ZStack {
            if let result {
                Image(decorative: result.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.07)))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: 340)
                    .onTapGesture(count: 2) { Actions.open(ref) }
                    .help("Double-click to open")
                    .overlay(alignment: .bottomLeading) {
                        if let note = note(result.kind) {
                            Text(note)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .padding(10)
                        }
                    }
                    .transition(.opacity)
            } else {
                shape.fill(Theme.well)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .overlay {
                        if loaded {
                            VStack(spacing: 6) {
                                Image(systemName: "photo").font(.system(size: 30, weight: .light))
                                Text("Deleted").font(.callout)
                            }
                            .foregroundStyle(.tertiary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .task(id: ref) {
            let r = await Thumbnails.preview(ref)
            withAnimation(.easeOut(duration: 0.18)) {
                result = r
                loaded = true
            }
        }
    }

    private func note(_ kind: SourceKind) -> String? {
        switch kind {
        case .original: nil
        case .grokCopy: "Grok copy"
        case .preview: "Preview"
        }
    }
}
