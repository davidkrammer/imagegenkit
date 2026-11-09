import AppKit
import SwiftUI

/// Neutral surfaces, so the window isn't tinted by the desktop wallpaper.
enum Theme {
    static let background = Color(light: 0xF5F5F7, dark: 0x1A1A1C)
    static let sidebar = Color(light: 0xEDEDF0, dark: 0x202023)
    static let card = Color(light: 0xFFFFFF, dark: 0x262629)
    static let well = Color(light: 0xF0F0F3, dark: 0x303034)
    static let accent = Color(light: 0x5B5BD6, dark: 0x7C7CF0)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

struct ProviderBadge: View {
    let provider: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(ProviderStyle.color(provider)).frame(width: 7, height: 7)
            Text(ProviderStyle.label(provider))
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Square thumbnail that loads (or creates) the archived preview.
struct ThumbnailView: View {
    let ref: ImageRef
    @State private var image: CGImage?
    @State private var loaded = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if loaded {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark").font(.title2)
                        Text("File deleted").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .background(.quaternary.opacity(0.5))
            .clipped()
            .task(id: ref) {
                image = await Thumbnails.thumbnail(ref)
                loaded = true
            }
    }
}

enum Actions {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Opens the best available full-size file for an image.
    static func open(_ ref: ImageRef) {
        if let src = ImageLocator.source(for: ref) {
            open(src.url)
        } else if let thumb = ImageLocator.existingThumb(for: ref) {
            open(thumb)
        }
    }
}

/// Context menu shared by the gallery and the history table.
struct ImageMenu: View {
    let entry: LogEntry
    var index = 0

    var body: some View {
        if index < entry.outputs.count {
            let ref = entry.imageRef(index)
            Button("Open Image") { Actions.open(ref) }
            Button("Show in Finder") { Actions.reveal(entry.outputs[index]) }
                .disabled(!ImageLocator.exists(entry.outputs[index]))
            Divider()
        }
        Button("Copy Prompt") { Actions.copy(entry.prompt) }
        Button("Copy imagegen Command") { Actions.copy(entry.rerunCommand) }
        if index < entry.outputs.count {
            Button("Copy File Path") { Actions.copy(entry.outputs[index]) }
        }
    }
}

/// A command with a copy button (and optionally a Run button that opens Terminal).
struct CommandField: View {
    let command: String
    var runnable = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Actions.copy(command)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy")
            if runnable {
                Button { TerminalRunner.run(command) } label: { Image(systemName: "terminal") }
                    .buttonStyle(.borderless)
                    .help("Run in Terminal")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct StatusIcon: View {
    let ok: Bool?
    var warning = false

    var body: some View {
        Group {
            switch ok {
            case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case false? where warning: Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
            case false?: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            case nil: ProgressView().controlSize(.mini)
            }
        }
        .frame(width: 18)
    }
}

/// Red icon and text for delete-type buttons.
struct DestructiveLabel: View {
    let title: String
    var icon = "trash"

    var body: some View {
        Label(title, systemImage: icon).foregroundStyle(.red)
    }
}

// MARK: - Design system (shared by every screen)

/// The main call-to-action button: accent gradient capsule.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom),
                in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small capsule label, e.g. "Beta" or a size.
struct Pill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// SF Symbol in a tinted rounded square.
struct IconBadge: View {
    let symbol: String
    var color: Color = Theme.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

extension View {
    /// Card surface: neutral fill, hairline border, soft shadow.
    func card(padding: CGFloat = 16, radius: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
