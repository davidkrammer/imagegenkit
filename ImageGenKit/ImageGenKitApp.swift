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
                .environment(store)
                .environment(config)
                .environment(status)
                .environment(installer)
                .environment(updater)
                .environment(catalog)
                .controlSize(.large)
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 740)
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

        Settings {
            SettingsView()
                .environment(store)
                .environment(config)
                .environment(status)
                .environment(installer)
                .environment(updater)
                .environment(catalog)
                .controlSize(.large)
                .frame(width: 720, height: 600)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
