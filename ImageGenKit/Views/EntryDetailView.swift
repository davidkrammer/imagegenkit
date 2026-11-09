import SwiftUI

struct EntryDetailView: View {
    let entry: LogEntry
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config
    @State private var reference: DetailReference?
    @State private var promptExpanded = false
    @State private var copied = false

    var body: some View {
        let index = min(store.selectedImageIndex, max(entry.outputs.count - 1, 0))
        let ref: ImageRef? = entry.outputs.isEmpty ? nil : entry.imageRef(index)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHero(entry: entry, ref: ref, selected: index) { i in
                    withAnimation(.easeOut(duration: 0.15)) { store.selectedImageIndex = i }
                }

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        prompt.galleryEnter(0)
                        chips.galleryEnter(1)
                    }
                    actions(ref: ref, index: index).galleryEnter(2)
                    details.galleryEnter(3)
                    if !entry.refs.isEmpty { references.galleryEnter(4) }
                }
                .padding(20)
                .id(entry.id)
            }
        }
        .background(Theme.background)
        .sheet(item: $reference) { ref in
            GenerateView(references: [ref.url])
        }
        .onChange(of: entry.id) { promptExpanded = false }
    }

    // MARK: Pieces

    private var prompt: some View {
        let long = entry.prompt.count > 160
        return VStack(alignment: .leading, spacing: 6) {
            Text(entry.prompt.isEmpty ? "No prompt" : entry.prompt)
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(2)
                .foregroundStyle(entry.prompt.isEmpty ? .secondary : .primary)
                .lineLimit(promptExpanded ? nil : 4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if long {
                Button(promptExpanded ? "Less" : "More") {
                    withAnimation(.smooth(duration: 0.25)) { promptExpanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private var chips: some View {
        DetailFlow(spacing: 6) {
            ProviderBadge(provider: entry.provider)
            Pill(text: entry.modelLabel)
            Pill(text: entry.sizeLabel)
            if let q = entry.param("quality") { Pill(text: q.capitalized) }
            if let c = config.cost(entry) {
                Pill(text: Format.usd(c, precise: true), color: Theme.accent)
            } else {
                Pill(text: "Subscription")
            }
            if entry.seconds != nil { Pill(text: Format.seconds(entry.seconds)) }
        }
    }

    private func actions(ref: ImageRef?, index: Int) -> some View {
        let path = ref.map { entry.outputs[$0.index] }
        let fileExists = path.map(ImageLocator.exists) ?? false
        let referenceSource: URL? = ref.flatMap { ImageLocator.source(for: $0)?.url ?? ImageLocator.existingThumb(for: $0) }
        return HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                referenceButton("Use as Reference", source: referenceSource)
                referenceButton("Reference", source: referenceSource)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { if let ref { Actions.open(ref) } } label: {
                Label("Open", systemImage: "arrow.up.forward.app").labelStyle(.iconOnly).frame(width: 18)
            }
            .disabled(ref == nil)
            .keyboardShortcut("o", modifiers: .command)
            .help("Open (⌘O)")

            Button { if let path { Actions.reveal(path) } } label: {
                Label("Show in Finder", systemImage: "folder").labelStyle(.iconOnly).frame(width: 18)
            }
            .disabled(!fileExists)
            .help("Show in Finder")

            Button { copy(entry.prompt) } label: {
                Label("Copy Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy prompt (⇧⌘C)")
        }
        .buttonStyle(.bordered)
    }

    private func referenceButton(_ title: String, source: URL?) -> some View {
        Button { reference = source.map(DetailReference.init) } label: {
            Label(title, systemImage: "wand.and.sparkles")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(source == nil)
        .help("Generate with this image as a reference")
    }

    private func copy(_ text: String) {
        Actions.copy(text)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { copied = false }
        }
    }

    private var detailRows: [DetailRowData] {
        var rows: [DetailRowData] = [
            .init(symbol: "calendar", label: "Date", value: entry.date.formatted(date: .abbreviated, time: .shortened)),
            .init(symbol: "folder", label: "Project", value: entry.project,
                  detail: (entry.cwd as NSString).abbreviatingWithTildeInPath),
        ]
        if let c = entry.caller, !c.label.isEmpty {
            rows.append(.init(symbol: "person", label: "Started by", value: c.label))
        }
        if let u = entry.openAIUsage {
            rows.append(.init(symbol: "number", label: "Tokens",
                              value: "\(Format.tokens(u.inputTokens)) in · \(Format.tokens(u.outputTokens)) out"))
        }
        if let note = missingNote {
            rows.append(.init(symbol: "exclamationmark.triangle", label: "File", value: note, warning: true))
        }
        return rows
    }

    private var details: some View {
        let rows = detailRows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Divider().padding(.leading, 52) }
                DetailRow(row: row)
            }
        }
        .padding(.vertical, 4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("References").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            DetailFlow(spacing: 8) {
                ForEach(entry.refs, id: \.self) { DetailReferenceThumb(path: $0) }
            }
        }
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

// MARK: - Rows

private struct DetailRowData {
    let symbol: String
    let label: String
    let value: String
    var detail: String?
    var warning = false
}

/// Icon badge + small label + value, like the tour's numbered points.
private struct DetailRow: View {
    let row: DetailRowData

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(symbol: row.symbol, color: row.warning ? .orange : Theme.accent, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.caption).foregroundStyle(.secondary)
                Text(row.value)
                    .font(.system(size: 13))
                    .foregroundStyle(row.warning ? .orange : .primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(detail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Hero

/// The image on the tour's soft accent wash, with the other images of the run below it.
private struct DetailHero: View {
    let entry: LogEntry
    let ref: ImageRef?
    let selected: Int
    let select: (Int) -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let ref {
                LargePreview(ref: ref)
                    .frame(height: 260)
                if entry.outputs.count > 1 { strip }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(height: 160)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(GalleryWash())
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entry.outputs.indices, id: \.self) { i in
                    DetailStripThumb(ref: entry.imageRef(i), selected: i == selected) { select(i) }
                }
            }
            .padding(4)
        }
        .scrollClipDisabled()
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity)
    }
}

private struct DetailStripThumb: View {
    let ref: ImageRef
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        ThumbnailView(ref: ref)
            .frame(width: 44, height: 44)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
            .overlay {
                if selected { shape.inset(by: -3).strokeBorder(Theme.accent, lineWidth: 2) }
            }
            .opacity(selected || hovering ? 1 : 0.7)
            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
            .contentShape(shape)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Components

/// Small thumbnail of a reference image; click shows it in Finder.
private struct DetailReferenceThumb: View {
    let path: String
    @State private var image: CGImage?

    var body: some View {
        Theme.well
            .frame(width: 52, height: 52)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
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

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        ZStack {
            if let result {
                Image(decorative: result.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
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
                    .id(ref)
            } else {
                shape.fill(Theme.well)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
                    .overlay {
                        if loaded {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.exclamationmark").font(.system(size: 28, weight: .light))
                                Text("Deleted").font(.callout)
                            }
                            .foregroundStyle(.tertiary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
