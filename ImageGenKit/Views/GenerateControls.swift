import AppKit
import SwiftUI

enum GenerateColors {
    /// Selected segment / raised chip, a step above `Theme.well` in both modes.
    static let raised = Color(light: 0xFFFFFF, dark: 0x4A4A50)
}

/// Caption above a control.
struct GenerateField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content
        }
    }
}

/// Capsule segmented control with a sliding selection.
struct GenerateSegmented: View {
    let options: [String]
    @Binding var selection: String
    var label: (String) -> String = { $0 }
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.callout.weight(on ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .frame(minWidth: 36, minHeight: 26)
                        .background {
                            if on {
                                Capsule().fill(GenerateColors.raised)
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.well, in: Capsule())
    }
}

/// Provider choice chip.
struct GenerateProviderChip: View {
    let provider: ProviderInfo
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(provider.color).frame(width: 8, height: 8)
                Text(provider.label).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .background(selected ? Theme.accent.opacity(0.12) : (hover ? Theme.well : Theme.card), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
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

/// Aspect ratio menu that looks like the segmented controls.
struct GenerateAspectMenu: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            Picker("Aspect", selection: $selection) {
                ForEach(options, id: \.self) { a in
                    Text(a).tag(a)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 7) {
                GenerateAspectShape(aspect: selection)
                Text(selection).font(.callout.weight(.semibold)).monospacedDigit()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.well, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
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

    var body: some View {
        VStack(spacing: 10) {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                    .scaleEffect(hover ? 1.01 : 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { Actions.open(url) }
                    .onHover { hover = $0 }
                    .animation(.easeOut(duration: 0.18), value: hover)
                    .draggable(url)
                    .contextMenu { menu }
                    .help("Double-click to open")
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
            withAnimation(.easeOut(duration: 0.3)) { image = loaded }
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
            Group {
                if compact {
                    Image(systemName: icon).frame(width: 30, height: 26)
                } else {
                    Label(title, systemImage: icon).padding(.horizontal, 10).frame(height: 26)
                }
            }
            .font(.callout.weight(.medium))
            .contentTransition(.symbolEffect(.replace))
            .background(Theme.well, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// Calm "working" state with elapsed seconds.
struct GenerateProgressView: View {
    let start: Date
    let provider: String
    @State private var spin = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [Theme.accent.opacity(0.05), Theme.accent.opacity(0.5), Color.purple.opacity(0.35),
                                                   Theme.accent.opacity(0.05)], center: .center))
                    .frame(width: 84, height: 84)
                    .blur(radius: 10)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.breathe, options: .repeating)
            }
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
            }
            VStack(spacing: 4) {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    Text("Generating · \(Int(max(0, ctx.date.timeIntervalSince(start)))) s")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text(provider).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Label whose icon has its own tint.
struct GenerateTintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
