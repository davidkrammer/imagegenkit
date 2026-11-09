import AppKit
import SwiftUI

/// Dock icon and window routing while the menu bar item is shown:
/// no Dock icon while no window is open, back to a normal app as soon as one opens.
@MainActor
final class MenuBarDock {
    static let shared = MenuBarDock()
    static let generateNotification = Notification.Name("ImageGenKitShowGenerate")

    private var observers: [NSObjectProtocol] = []

    static var showMenuBar: Bool { UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true }

    func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MenuBarDock.shared.update() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { MenuBarDock.shared.update(closing: window) }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MenuBarDock.shared.update() }
        })
    }

    /// Shows the Dock icon when a window is open (or the menu bar item is off); hides it only when the
    /// last window closes, never during launch (SwiftUI wouldn't present the first window for an accessory app).
    func update(closing: NSWindow? = nil) {
        let hasWindow = NSApp.windows.contains { $0 !== closing && Self.isAppWindow($0) }
        if !Self.showMenuBar || hasWindow {
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        } else if closing != nil, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Real document-style windows: not the menu bar panel, the status item, sheets or popovers.
    static func isAppWindow(_ w: NSWindow) -> Bool {
        guard w.isVisible || w.isMiniaturized, !(w is NSPanel), !w.isSheet, w.canBecomeMain else { return false }
        let name = String(describing: type(of: w))
        return !name.contains("StatusBar") && !name.contains("MenuBarExtra")
    }

    // MARK: Actions from the menu bar

    /// Shows the app in the Dock, brings the main window up, then runs `then` once it's there.
    static func openMain(_ openWindow: OpenWindowAction, then: (@MainActor () -> Void)? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: "main")
        guard let then else { return }
        Task { @MainActor in
            for _ in 0..<40 where !NSApp.windows.contains(where: { isAppWindow($0) && $0.isVisible }) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(200))
            then()
        }
    }

    static func generate(_ openWindow: OpenWindowAction) {
        openMain(openWindow) { NotificationCenter.default.post(name: generateNotification, object: nil) }
    }

    static func settings(_ openWindow: OpenWindowAction) {
        UserDefaults.standard.set(SidebarItem.settings.rawValue, forKey: "sidebarSection")
        openMain(openWindow)
    }
}
