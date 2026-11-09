import AppKit
import SwiftUI

/// Settings: one scrolling page with Providers, Use for, Images, Prices, Agents and About.
struct SettingsView: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @Environment(Updater.self) private var updater
    @State private var sheet: AddProviderRoute?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsProvidersSection(sheet: $sheet)
                SettingsTasksSection()
                SettingsImagesSection().id("images")
                SettingsAgentsSection()
                SettingsAboutSection()
                Color.clear.frame(height: 1).id("end")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        #if DEBUG
        .task {
            if let target = UserDefaults.standard.string(forKey: "debugScrollTo") {
                try? await Task.sleep(for: .seconds(3))
                proxy.scrollTo(target, anchor: target == "end" ? .bottom : .top)
            }
        }
        #endif
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .sheet(item: $sheet) { AddProviderSheet(route: $0) }
        .task {
            config.reload()
            await status.refresh(config.providers)
            #if DEBUG
            let d = UserDefaults.standard
            if d.bool(forKey: "debugAddProvider") { sheet = .add }
            if let id = d.string(forKey: "debugSetup") { sheet = .setup(id) }
            if d.bool(forKey: "debugCustom") { sheet = .custom(nil) }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            config.reload()
            Task {
                await status.refresh(config.providers)
                await installer.refresh()
            }
        }
    }
}

// MARK: - Building blocks

/// A titled group: small header above a card.
struct SettingsSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                accessory
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }
}

/// One row inside a section card: icon, title, optional detail, trailing control.
struct SettingsRow<Trailing: View>: View {
    var icon: String?
    var tint: Color = Theme.accent
    let title: String
    var detail: String?
    var detailColor: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon { IconBadge(symbol: icon, color: tint, size: 28) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1).truncationMode(.middle)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}

/// Hairline between rows, inset past the icon.
struct SettingsDivider: View {
    var inset: CGFloat = 14
    var body: some View { Divider().padding(.leading, inset) }
}

/// A row that expands to show more rows (Models, Prices).
struct SettingsDisclosure<Content: View>: View {
    let title: String
    var icon: String
    @ViewBuilder var content: Content
    #if DEBUG
    @State private var open = UserDefaults.standard.bool(forKey: "debugExpand")
    #else
    @State private var open = false
    #endif

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { open.toggle() }
        } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, color: .secondary, size: 28)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if open {
            VStack(spacing: 0) { content }
                .padding(.leading, 40)
                .transition(.opacity)
        }
    }
}

// MARK: - Use for

struct SettingsTasksSection: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status

    var body: some View {
        let enabled = config.enabled(ready: { status.state($0).isReady })
        SettingsSection(title: "Use for") {
            ForEach(Array(ImageTask.allCases.enumerated()), id: \.element) { i, task in
                if i > 0 { SettingsDivider(inset: 54) }
                SettingsRow(icon: task.icon, title: task.label, detail: hint(task)) {
                    picker(task, enabled: task == .transparent ? enabled.filter(\.canTransparent) : enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func picker(_ task: ImageTask, enabled: [ProviderInfo]) -> some View {
        let binding = config.taskBinding(task, "provider")
        if enabled.isEmpty {
            Text(task == .transparent ? "Needs OpenAI" : "No provider").foregroundStyle(.secondary)
        } else {
            Picker(task.label, selection: binding) {
                ForEach(enabled) { p in
                    Text(p.label).tag(p.id)
                }
                if !enabled.contains(where: { $0.id == binding.wrappedValue }) {
                    Text(binding.wrappedValue.isEmpty ? "None" : ProviderStyle.label(binding.wrappedValue))
                        .tag(binding.wrappedValue)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func hint(_ task: ImageTask) -> String {
        switch task {
        case .draft: "Quick mockups"
        case .final: "Finished images"
        case .edit: "Change an image"
        case .transparent: "Clear background"
        }
    }
}

// MARK: - Images

struct SettingsImagesSection: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status

    var body: some View {
        let enabled = config.enabled(ready: { status.state($0).isReady })
        SettingsSection(title: "Images") {
            SettingsRow(icon: "folder", title: "Save to", detail: config.string("output_dir")) {
                Button("Choose…", action: chooseFolder)
            }
            ForEach(enabled) { p in
                SettingsDivider(inset: 54)
                SettingsProviderImageRow(provider: p)
            }
            SettingsDivider(inset: 54)
            SettingsPricesSection()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: (config.string("output_dir") as NSString).expandingTildeInPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.set("output_dir", (url.path as NSString).abbreviatingWithTildeInPath)
    }
}

// MARK: - Prices

struct SettingsPricesSection: View {
    @Environment(ConfigStore.self) private var config

    var body: some View {
        SettingsDisclosure(title: "Prices", icon: "dollarsign") {
                Text("OpenAI · per 1M tokens")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 4)
                priceRow("Text in", "openai", "text_in")
                SettingsDivider()
                priceRow("Image in", "openai", "image_in")
                SettingsDivider()
                priceRow("Image out", "openai", "image_out")
                Text("Per image")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 12)
                priceRow("xAI API", "xai", "per_image")
                SettingsDivider()
                priceRow("Gemini", "gemini", "per_image")
                ForEach(config.customProviders) { p in
                    SettingsDivider()
                    priceRow(p.label, p.id, "per_image")
                }
                SettingsDivider()
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { config.resetPrices() }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func priceRow(_ title: String, _ provider: String, _ key: String) -> some View {
        SettingsRow(title: title) {
            HStack(spacing: 4) {
                Text("$").foregroundStyle(.secondary)
                TextField(title, value: config.priceBinding(provider, key), format: .number.precision(.fractionLength(0...4)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .labelsHidden()
                    .frame(width: 90)
            }
        }
    }
}

// MARK: - About

struct SettingsAboutSection: View {
    @Environment(Updater.self) private var updater
    @Environment(Catalog.self) private var catalog

    var body: some View {
        SettingsSection(title: "About") {
            HStack(spacing: 12) {
                AppIconView(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ImageGenKit").font(.body.weight(.semibold))
                    Text("Version \(updater.currentVersion)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                updateControl
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            SettingsDivider()
            HStack(spacing: 18) {
                Button {
                    NotificationCenter.default.post(Notification(name: Notification.Name("ImageGenKitShowOnboarding")))
                } label: {
                    Label("Show Welcome Tour", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
                Link(destination: Updater.homepage) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                }
                Spacer()
                if !catalog.updated.isEmpty {
                    Text("Providers updated \(catalog.updated)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var updateControl: some View {
        switch updater.state {
        case .idle:
            Button("Check for Updates") { Task { await updater.check() } }
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            HStack(spacing: 8) {
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
                Button { Task { await updater.check() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Check again")
            }
        case .available(let v):
            Button("Update to \(v)") { Task { await updater.install() } }
                .buttonStyle(.borderedProminent)
        case .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(updater.state == .downloading ? "Downloading…" : "Installing…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
                Button("Retry") { Task { await updater.check() } }
            }
        }
    }
}
