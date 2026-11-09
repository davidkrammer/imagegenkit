import SwiftUI

struct EntryDetailView: View {
    let entry: LogEntry
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config

    var body: some View {
        let index = min(store.selectedImageIndex, max(entry.outputs.count - 1, 0))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !entry.outputs.isEmpty {
                    LargePreview(ref: entry.imageRef(index))
                    if entry.outputs.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(entry.outputs.indices, id: \.self) { i in
                                ThumbnailView(ref: entry.imageRef(i))
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(i == index ? Color.accentColor : .clear, lineWidth: 2)
                                    }
                                    .onTapGesture { store.selectedImageIndex = i }
                            }
                        }
                    }
                }

                HStack {
                    ProviderBadge(provider: entry.provider)
                    Text(entry.modelLabel).font(.callout.weight(.medium))
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.prompt)
                        .textSelection(.enabled)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("Copy Prompt", systemImage: "doc.on.doc") { Actions.copy(entry.prompt) }
                        Button("Copy Command", systemImage: "terminal") { Actions.copy(entry.rerunCommand) }
                            .help(entry.rerunCommand)
                    }
                    .controlSize(.small)
                }

                details

                files

                if !entry.refs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("References").font(.headline)
                        ForEach(entry.refs, id: \.self) { ref in
                            FileRow(path: ref, note: nil)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Type", entry.kindLabel)
            row("Size", entry.sizeLabel)
            if let q = entry.param("quality") { row("Quality", q) }
            if let b = entry.param("background") { row("Background", b) }
            row("Images", "\(entry.imageCount)")
            row("Time", Format.seconds(entry.seconds))
            if let c = config.cost(entry) {
                row("Cost", Format.usd(c, precise: true))
            } else {
                row("Cost", "subscription")
            }
            if let u = entry.openAIUsage {
                row("Tokens", "\(Format.tokens(u.inputTokens)) in · \(Format.tokens(u.outputTokens)) out")
            }
            row("Project", entry.project)
            if let c = entry.caller, !c.label.isEmpty { row("Started by", c.label) }
            row("Folder", entry.cwd)
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.outputs.count == 1 ? "File" : "Files").font(.headline)
            ForEach(entry.outputs.indices, id: \.self) { i in
                let path = entry.outputs[i]
                FileRow(path: path, note: ImageLocator.exists(path) ? nil : missingNote(i))
            }
        }
    }

    private func missingNote(_ i: Int) -> String {
        let ref = entry.imageRef(i)
        if ImageLocator.source(for: ref)?.kind == .grokCopy { return "Deleted · Grok copy left" }
        if ImageLocator.existingThumb(for: ref) != nil { return "Deleted · preview left" }
        return "Deleted"
    }
}

private struct FileRow: View {
    let path: String
    let note: String?

    var body: some View {
        let exists = ImageLocator.exists(path)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: exists ? "photo" : "photo.badge.exclamationmark")
                .foregroundStyle(exists ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                Text((path as NSString).deletingLastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
                if let note { Text(note).font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            if exists {
                Button { Actions.reveal(path) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show in Finder")
            }
        }
    }
}

private struct LargePreview: View {
    let ref: ImageRef
    @State private var result: (image: CGImage, kind: SourceKind)?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let result {
                Image(decorative: result.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
                    .onTapGesture(count: 2) { Actions.open(ref) }
                    .help("Double-click to open")
                    .overlay(alignment: .bottomLeading) {
                        if let note = note(result.kind) {
                            Text(note)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
            } else if loaded {
                ContentUnavailableView("Deleted", systemImage: "photo.badge.exclamationmark")
                    .frame(height: 220)
            } else {
                ProgressView().frame(height: 220)
            }
        }
        .task(id: ref) {
            result = await Thumbnails.preview(ref)
            loaded = true
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
