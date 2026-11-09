import AppKit
import SwiftUI

@main
struct ImageGenKitApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = LogStore()
    @State private var config = ConfigStore()
    @State private var status = ProviderStatus()
    @State private var installer = Installer()
    @State private var updater = Updater()
    @State private var catalog = Catalog()
    @AppStorage("showMenuBar") private var showMenuBar = true

    init() {
        Paths.migrateLegacyConfig()
        // `-forceAppearance light|dark` (screenshots).
        if let mode = UserDefaults.standard.string(forKey: "forceAppearance") {
            NSApplication.shared.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        }
    }

    var body: some Scene {
        Window("ImageGenKit", id: "main") {
            RootView()
                .modifier(MenuBarLimitWatcher())
                .modifier(MenuBarDebugOpener())
                .environment(store)
                .environment(config)
                .environment(status)
                .environment(installer)
                .environment(updater)
                .environment(catalog)
                .controlSize(.large)
                .buttonBorderShape(Theme.buttonShape)
                .tint(Theme.accent)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 740)
        // Always open the main window at launch, even if it was closed (menu bar only) when the app last quit.
        // Its size and position are still remembered.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    store.reloadAll()
                    config.reload()
                }
                .keyboardShortcut("r")
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit ImageGenKit") { AppDelegate.quit() }
                    .keyboardShortcut("q")
            }
            CommandGroup(replacing: .help) {
                Button("Welcome Tour…") { OnboardingStore.show() }
                Divider()
                Link("ImageGenKit on GitHub", destination: Updater.homepage)
                Menu("Donate") {
                    Link("PayPal", destination: Updater.donatePayPal)
                    Link("GitHub Sponsors", destination: Updater.donateGitHub)
                }
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel()
                .environment(store)
                .environment(config)
                .controlSize(.large)
                .buttonBorderShape(Theme.buttonShape)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel()
                .environment(store)
                .environment(config)
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
        // `-debugMenuPanel YES`: the menu bar panel in a normal window (screenshots).
        Window("Menu Bar Panel", id: "debugMenuPanel") {
            MenuBarPanel()
                .environment(store)
                .environment(config)
                .controlSize(.large)
                .buttonBorderShape(Theme.buttonShape)
                .tint(Theme.accent)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        Settings {
            SettingsView()
                .environment(store)
                .environment(config)
                .environment(status)
                .environment(installer)
                .environment(updater)
                .environment(catalog)
                .controlSize(.large)
                .buttonBorderShape(Theme.buttonShape)
                .tint(Theme.accent)
                .frame(width: 720, height: 600)
        }
    }
}

extension ImageGenKitApp {
    static var debugPanel: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugMenuPanel")
        #else
        false
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDock.shared.install()
        // Quit from the Dock, AppleScript, logout or shutdown arrives as an Apple event, which AppKit refuses while a
        // sheet is open. Route it through `quit()` so it works with the welcome tour open, like ⌘Q.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleQuitEvent(_:reply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
        #if DEBUG
        // `-debugQuitAfter 8`: the same path as ⌘Q, after n seconds (tests quitting with a sheet open).
        let delay = UserDefaults.standard.double(forKey: "debugQuitAfter")
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { AppDelegate.quit() } }
        #endif
    }

    /// Quit even while a sheet is open (like the welcome tour on first launch): AppKit refuses to terminate while a
    /// sheet is attached, so the sheets close first. If one doesn't within 2 s, settings are flushed and the app exits.
    static func quit() {
        guard hasSheets else { NSApp.terminate(nil); return }
        NotificationCenter.default.post(name: .imageGenKitDismissSheets, object: nil)
        terminateWhenSheetsClosed(tries: 20)
    }

    @objc private func handleQuitEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        AppDelegate.quit()
    }

    private static var hasSheets: Bool { NSApp.windows.contains { $0.attachedSheet != nil } }

    private static func terminateWhenSheetsClosed(tries: Int) {
        if !hasSheets {
            NSApp.terminate(nil)
        } else if tries == 0 {
            UserDefaults.standard.synchronize()
            exit(0)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { terminateWhenSheetsClosed(tries: tries - 1) }
        }
    }

    /// With the menu bar item shown, closing the window keeps the app running there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !MenuBarDock.showMenuBar }
}
