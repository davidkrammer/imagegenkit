import ServiceManagement
import SwiftUI

/// Menu bar item and open at login.
struct SettingsGeneralSection: View {
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        SettingsSection(title: "General", icon: "gearshape", lead: "How the app runs.") {
            SettingsRow(icon: "menubar.rectangle", title: "Show in menu bar") {
                Toggle("Show in menu bar", isOn: $showMenuBar).labelsHidden().toggleStyle(.switch).tint(Theme.switchTint)
            }
            SettingsDivider(inset: 58)
            SettingsRow(icon: "power", title: "Open at login", detail: loginDetail, detailColor: .orange) {
                HStack(spacing: 10) {
                    if loginStatus == .requiresApproval {
                        Button("Allow…") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                    }
                    Toggle("Open at login", isOn: loginBinding).labelsHidden().toggleStyle(.switch).tint(Theme.switchTint)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private var loginDetail: String? {
        loginStatus == .requiresApproval ? "Needs approval in System Settings" : nil
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { on in
            let service = SMAppService.mainApp
            do {
                if on { try service.register() } else { try service.unregister() }
            } catch {
                // Quietly keep the real state (e.g. a test build that can't register).
            }
            withAnimation(.snappy(duration: 0.2)) { loginStatus = service.status }
        })
    }
}
