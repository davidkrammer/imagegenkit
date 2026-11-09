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
            CommandGroup(replacing: .help) {
                Button("Welcome Tour…") { OnboardingStore.show() }
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
    }

    /// With the menu bar item shown, closing the window keeps the app running there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !MenuBarDock.showMenuBar }
}
