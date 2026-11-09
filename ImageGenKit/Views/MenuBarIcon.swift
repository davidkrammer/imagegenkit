import AppKit
import SwiftUI

/// The logo mark as a monochrome template image for the menu bar, with an optional small dot
/// when a monthly limit is near (hollow ring) or reached (filled dot).
enum MenuBarIcon {
    private static var cache: [UsageLimits.Level: NSImage] = [:]

    static func image(_ level: UsageLimits.Level) -> NSImage {
        let key: UsageLimits.Level = level >= .warning ? level : .none
        if let cached = cache[key] { return cached }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let frame = rect.insetBy(dx: 0.5, dy: 0.5)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
            ctx.addPath(AppGlyphShape(part: .viewfinder).path(in: frame).cgPath)
            ctx.fillPath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(AppGlyphShape(part: .sparkles).path(in: frame).cgPath)
            ctx.fillPath()
            if key >= .warning {
                // Knock out a ring around the dot so it reads cleanly over the mark.
                let dot = CGRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: dot.insetBy(dx: -1.25, dy: -1.25))
                ctx.setBlendMode(.normal)
                ctx.setFillColor(NSColor.black.cgColor)
                if key == .reached {
                    ctx.fillEllipse(in: dot)
                } else {
                    ctx.setStrokeColor(NSColor.black.cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.strokeEllipse(in: dot.insetBy(dx: 0.75, dy: 0.75))
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ImageGenKit"
        cache[key] = image
        return image
    }
}

/// The menu bar label: icon, keeps the log running and posts limit notifications.
struct MenuBarLabel: View {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config

    var body: some View {
        let usage = MonthUsage(entries: store.entries, cost: config.cost)
        let level = MenuBarLimits.current(config).level(usage)
        Image(nsImage: MenuBarIcon.image(level))
            .task { store.start() }
            .modifier(MenuBarLimitWatcher())
    }
}

/// Checks the monthly limits whenever the log grows (attached to the menu bar label and the main window).
struct MenuBarLimitWatcher: ViewModifier {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config

    func body(content: Content) -> some View {
        content
            .onChange(of: store.entries.count, initial: true) { check() }
            .onChange(of: config.limits) { check() }
    }

    private func check() {
        guard !MenuBarLimits.isFaked, !store.entries.isEmpty else { return }
        let limits = config.limits
        guard limits.isSet else { return }
        let usage = MonthUsage(entries: store.entries, cost: config.cost)
        if limits.level(usage) >= .warning { LimitNotifier.requestPermission() }
        LimitNotifier.check(usage, limits: limits)
    }
}

/// The limits the menu bar shows. DEBUG: `-debugLimitCost 20 -debugLimitImages 500 -debugStopPaid YES` fake them.
enum MenuBarLimits {
    static var isFaked: Bool {
        #if DEBUG
        let d = UserDefaults.standard
        return d.object(forKey: "debugLimitCost") != nil || d.object(forKey: "debugLimitImages") != nil
        #else
        return false
        #endif
    }

    static func current(_ config: ConfigStore) -> UsageLimits {
        #if DEBUG
        if isFaked {
            let d = UserDefaults.standard
            return UsageLimits(monthlyCost: d.object(forKey: "debugLimitCost") != nil ? d.double(forKey: "debugLimitCost") : nil,
                               monthlyImages: d.object(forKey: "debugLimitImages") != nil ? d.integer(forKey: "debugLimitImages") : nil,
                               stopPaid: d.bool(forKey: "debugStopPaid"))
        }
        #endif
        return config.limits
    }
}

/// DEBUG `-debugMenuPanel YES`: swaps the main window for a window that hosts the menu bar panel (screenshots).
struct MenuBarDebugOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            guard ImageGenKitApp.debugPanel else { return }
            openWindow(id: "debugMenuPanel")
            dismissWindow(id: "main")
        }
        #else
        content
        #endif
    }
}
