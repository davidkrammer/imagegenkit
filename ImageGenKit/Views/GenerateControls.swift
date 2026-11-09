import AppKit
import SwiftUI

/// Native segmented control.
struct GenerateSegmented: View {
    let options: [String]
    @Binding var selection: String
    var label: (String) -> String = { $0 }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// Provider choice: a native button, prominent when selected.
struct GenerateProviderChip: View {
    let provider: ProviderInfo
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label {
                Text(provider.label)
            } icon: {
                Circle().fill(selected ? Color.white : provider.color).frame(width: 8, height: 8)
            }
        }
        if selected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

/// A small rectangle with the aspect's proportions.
struct GenerateAspectShape: View {
    let aspect: String
    var box: CGFloat = 14

    var body: some View {
        let (w, h) = Self.ratio(aspect)
        let scale = box / max(w, h)
        Group {
            if aspect == GenerateSpec.auto {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [2.4, 1.6]))
                    .frame(width: box * 0.86, height: box * 0.86)
            } else {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(lineWidth: 1.4)
                    .frame(width: max(5, w * scale), height: max(5, h * scale))
            }
        }
        .frame(width: box, height: box)
    }

    static func ratio(_ aspect: String) -> (CGFloat, CGFloat) {
        let parts = aspect.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return (1, 1) }
        return (parts[0], parts[1])
    }
}

/// Aspect ratio pop-up menu.
struct GenerateAspectMenu: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Picker("Aspect", selection: $selection) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// Reference image thumbnail with a remove button.
struct GenerateReferenceTile: View {
    let url: URL
    var size: CGFloat = 56
    let remove: () -> Void
    @State private var image: CGImage?
    @State private var hover = false

    var body: some View {
        ZStack {
            Theme.well
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.black.opacity(0.65), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .opacity(hover ? 1 : 0)
            .help("Remove")
        }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(url.lastPathComponent)
        .task(id: url) { image = await GenerateImageLoader.load(url, maxPixel: Int(size * 3)) }
    }
}

/// Small round-cornered reference thumbnail (prompt summary).
struct GenerateReferenceThumb: View {
    let url: URL
    var size: CGFloat = 32
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Theme.card
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.well, lineWidth: 2))
        .help(url.lastPathComponent)
        .task(id: url) { image = await GenerateImageLoader.load(url, maxPixel: Int(size * 3)) }
    }
}

/// Dashed "+" tile for adding references.
struct GenerateAddTile: View {
    var size: CGFloat = 56
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(hover ? Theme.accent : .secondary)
                .frame(width: size, height: size)
                .background(hover ? Theme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hover ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.18),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Add reference images")
    }
}

/// One generated image with its actions.
struct GenerateResultTile: View {
    let url: URL
    let compact: Bool
    let useAsReference: () -> Void
    @State private var image: CGImage?
    @State private var hover = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: .black.opacity(hover ? 0.24 : 0.16), radius: hover ? 16 : 12, y: hover ? 8 : 6)
                        .scaleEffect(hover ? 1.012 : 1)
                        .transition(reduceMotion ? .opacity : .modifier(active: GenerateReveal(amount: 1), identity: GenerateReveal(amount: 0)))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { Actions.open(url) }
                        .onHover { hover = $0 }
                        .animation(.easeOut(duration: 0.18), value: hover)
                        .draggable(url)
                        .contextMenu { menu }
                        .help("Double-click to open")
                } else {
                    GenerateCanvasPlaceholder(aspect: GenerateSpec.auto)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: compact ? 4 : 8) {
                action("Open", "arrow.up.forward.square") { Actions.open(url) }
                action("Show in Finder", "folder") { Actions.reveal(url.path) }
                action(copied ? "Copied" : "Copy Path", copied ? "checkmark" : "doc.on.doc") {
                    Actions.copy(url.path)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                }
                action("Use as Reference", "arrow.uturn.backward", useAsReference)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            let loaded = await GenerateImageLoader.load(url, maxPixel: 1400)
            withAnimation(.smooth(duration: 0.6)) { image = loaded }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Open") { Actions.open(url) }
        Button("Show in Finder") { Actions.reveal(url.path) }
        Button("Copy Path") { Actions.copy(url.path) }
        Divider()
        Button("Use as Reference", action: useAsReference)
    }

    private func action(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon)
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .help(title)
    }
}

enum GenerateFilePicker {
    static func images(multiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Type-erased label style (switch icon-only vs title+icon at runtime).
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
