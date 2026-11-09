import AppKit
import SwiftUI

/// Neutral surfaces, so the window isn't tinted by the desktop wallpaper.
enum Theme {
    static let background = Color(light: 0xF5F5F7, dark: 0x1A1A1C)
    static let sidebar = Color(light: 0xEDEDF0, dark: 0x202023)
    static let card = Color(light: 0xFFFFFF, dark: 0x262629)
    static let well = Color(light: 0xF0F0F3, dark: 0x303034)
    /// Brand accent. `-accentHex RRGGBB` / `-accentDarkHex RRGGBB` override it (design previews).
    static let accent: Color = {
        let d = UserDefaults.standard
        if let hex = d.string(forKey: "accentHex").flatMap({ UInt32($0, radix: 16) }) {
            let dark = d.string(forKey: "accentDarkHex").flatMap { UInt32($0, radix: 16) } ?? hex
            return Color(light: hex, dark: dark)
        }
        return Color(light: 0x1C1C1E, dark: 0xF2F2F7)  // graphite: black in light mode, white in dark mode
    }()
    /// Text and symbols on an accent fill (white on black, black on white).
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x1C1C1E)

    /// Switches: a near-white tint turns lavender in dark mode (macOS boosts it against the white knob), so a neutral gray.
    static let switchTint = Color(light: 0x1C1C1E, dark: 0x8C8C8C)

    /// One button shape for the whole app. `-buttonShape capsule|rounded|square` previews others.
    static let buttonShape: ButtonBorderShape = {
        switch UserDefaults.standard.string(forKey: "buttonShape") {
        case "capsule": .capsule
        case "square": .roundedRectangle(radius: 5)
        default: .roundedRectangle(radius: 8)
        }
    }()
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
        Button("Copy Command") { Actions.copy(entry.rerunCommand) }
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

/// The real app icon (a rendered copy is bundled; Icon Composer icons don't reach NSApp.applicationIconImage at small sizes).
struct AppIconView: View {
    var size: CGFloat = 30

    var body: some View {
        Image(nsImage: Bundle.main.image(forResource: "app-icon") ?? NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The logo mark alone (viewfinder + sparkles), in the text color — for the few places that show branding.
/// Same geometry as AppIcon.icon (1024-point canvas).
struct AppGlyph: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            AppGlyphShape(part: .viewfinder).fill(.primary.opacity(0.45))
            AppGlyphShape(part: .sparkles).fill(.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

nonisolated struct AppGlyphShape: Shape {
    enum Part { case viewfinder, sparkles }
    let part: Part

    func path(in rect: CGRect) -> Path {
        // The mark sits inside 196...828; scale it to fill the frame with a little margin.
        let inset: CGFloat = 176, span: CGFloat = 1024 - 2 * inset
        let k = min(rect.width, rect.height) / span
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - inset) * k, y: rect.minY + (y - inset) * k)
        }
        var path = Path()
        switch part {
        case .sparkles:
            for (cx, cy, r, c) in [(500.0, 536.0, 200.0, 52.0), (690.0, 342.0, 68.0, 17.0)] {
                path.move(to: p(cx, cy - r))
                path.addQuadCurve(to: p(cx + r, cy), control: p(cx + c, cy - c))
                path.addQuadCurve(to: p(cx, cy + r), control: p(cx + c, cy + c))
                path.addQuadCurve(to: p(cx - r, cy), control: p(cx - c, cy + c))
                path.addQuadCurve(to: p(cx, cy - r), control: p(cx - c, cy - c))
                path.closeSubpath()
            }
        case .viewfinder:
            let t: CGFloat = 56, arm: CGFloat = 170, rad: CGFloat = 92
            for (x, y, sx, sy) in [(196.0, 196.0, 1.0, 1.0), (828.0, 196.0, -1.0, 1.0),
                                   (828.0, 828.0, -1.0, -1.0), (196.0, 828.0, 1.0, -1.0)] {
                func q(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { p(x + sx * dx, y + sy * dy) }
                var corner = Path()
                corner.move(to: q(0, arm))
                corner.addLine(to: q(0, rad))
                corner.addQuadCurve(to: q(rad, 0), control: q(0, 0))
                corner.addLine(to: q(arm, 0))
                corner.addQuadCurve(to: q(arm, t), control: q(arm + t / 2, t / 2))
                corner.addLine(to: q(rad, t))
                corner.addQuadCurve(to: q(t, rad), control: q(t, t))
                corner.addLine(to: q(t, arm))
                corner.addQuadCurve(to: q(0, arm), control: q(t / 2, arm + t / 2))
                corner.closeSubpath()
                path.addPath(corner)
            }
        }
        return path
    }
}
