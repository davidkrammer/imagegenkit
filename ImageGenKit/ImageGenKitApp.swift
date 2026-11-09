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
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(config)
                .environment(status)
                .environment(installer)
                .environment(updater)
                .environment(catalog)
                .frame(width: 720, height: 600)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
