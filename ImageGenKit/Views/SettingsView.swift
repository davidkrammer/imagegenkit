import AppKit
import SwiftUI

/// Settings: one scrolling page with Providers, Use for, Images, Limits, Agents, General and About.
struct SettingsView: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @Environment(Updater.self) private var updater
    @State private var sheet: AddProviderRoute?
    /// Set by other screens (e.g. Overview's "Change Limit") to scroll to a section once.
    @AppStorage("settingsScrollTo") private var pendingScroll = ""

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SettingsProvidersSection(sheet: $sheet).settingsEnter(0)
                SettingsTasksSection().settingsEnter(1)
                SettingsImagesSection().id("images").settingsEnter(2)
                SettingsLimitsSection().id("limits").settingsEnter(3)
                SettingsAgentsSection().settingsEnter(4)
                SettingsGeneralSection().id("general").settingsEnter(5)
                SettingsAboutSection().settingsEnter(6)
                Color.clear.frame(height: 1).id("end")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .task {
            guard !pendingScroll.isEmpty else { return }
            let target = pendingScroll
            pendingScroll = ""
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo(target, anchor: .top) }
        }
        #if DEBUG
        .onAppear {
            // Don't start with the cursor in a text field (typing would change a setting by accident).
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .task {
            if let target = UserDefaults.standard.string(forKey: "debugScrollTo") {
                try? await Task.sleep(for: .seconds(3))
                proxy.scrollTo(target, anchor: target == "end" ? .bottom : .top)
            }
        }
        #endif
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .sheet(item: $sheet) { AddProviderSheet(route: $0).dismissOnQuit() }
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

/// A titled group like a tour step: icon badge, title and a one-line lead above a card.
struct SettingsSection<Content: View, Accessory: View>: View {
    let title: String
    var icon: String?
    var lead: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, icon: String? = nil, lead: String? = nil,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.lead = lead
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let icon { IconBadge(symbol: icon, size: 32) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    if let lead {
                        Text(lead).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                accessory
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(title: String, icon: String? = nil, lead: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: icon, lead: lead, accessory: { EmptyView() }, content: content)
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
            if let icon { IconBadge(symbol: icon, color: tint, size: 32) }
            VStack(alignment: .leading, spacing: 2) {
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
        .frame(minHeight: 56)
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
                IconBadge(symbol: icon, color: .secondary, size: 32)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if open {
            VStack(spacing: 0) { content }
                .padding(.vertical, 4)
                .background(Theme.well.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 58)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Use for

struct SettingsTasksSection: View {
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status

    var body: some View {
        let enabled = config.enabled(ready: { status.state($0).isReady })
        SettingsSection(title: "Use for", icon: "slider.horizontal.3", lead: "Pick a provider for each kind of image.") {
            ForEach(Array(ImageTask.allCases.enumerated()), id: \.element) { i, task in
                if i > 0 { SettingsDivider(inset: 58) }
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
            .buttonSizing(.flexible)
            .frame(width: 170)
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
        SettingsSection(title: "Images", icon: "photo.on.rectangle.angled", lead: "Where they're saved and how they look.") {
            SettingsRow(icon: "folder", title: "Save to", detail: config.string("output_dir")) {
                Button("Choose…", action: chooseFolder)
            }
            ForEach(enabled) { p in
                SettingsDivider(inset: 58)
                SettingsProviderImageRow(provider: p)
            }
            SettingsDivider(inset: 58)
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
            caption("OpenAI · per 1M tokens", top: 6)
            priceRow("Text in", "openai", "text_in")
            priceRow("Image in", "openai", "image_in")
            priceRow("Image out", "openai", "image_out")
            caption("Per image", top: 12)
            priceRow("xAI API", "xai", "per_image")
            priceRow("Gemini", "gemini", "per_image")
            ForEach(config.customProviders) { p in
                priceRow(p.label, p.id, "per_image")
            }
            HStack {
                Spacer()
                Button("Reset to Defaults") { config.resetPrices() }
                    .buttonStyle(.link).foregroundStyle(Theme.accent)
                    .font(.callout)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func caption(_ text: String, top: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, top).padding(.bottom, 2)
    }

    private func priceRow(_ title: String, _ provider: String, _ key: String) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
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
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
    }
}

// MARK: - About

struct SettingsAboutSection: View {
    @Environment(Updater.self) private var updater
    @Environment(Catalog.self) private var catalog

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SettingsArtBackground(radius: 260)
                AppGlyph(size: 64)
                    .settingsFloat(3, duration: 3.2)
            }
            .frame(height: 132)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }

            VStack(spacing: 4) {
                Text("ImageGenKit").font(.system(size: 20, weight: .semibold))
                Text("Version \(updater.currentVersion)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.top, 18)

            updateControl
                .frame(minHeight: 32)
                .padding(.top, 14)

            HStack(spacing: 20) {
                Button("Welcome Tour", systemImage: "sparkles") {
                    NotificationCenter.default.post(Notification(name: Notification.Name("ImageGenKitShowOnboarding")))
                }
                Link(destination: Updater.homepage) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                }
                Menu {
                    Link("PayPal", destination: Updater.donatePayPal)
                    Link("GitHub Sponsors", destination: Updater.donateGitHub)
                } label: {
                    Label("Donate", systemImage: "heart")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("ImageGenKit is free. A donation helps keep it going.")
            }
            .buttonStyle(.link).foregroundStyle(Theme.accent)
            .font(.callout)
            .padding(.top, 14)

            if !catalog.updated.isEmpty {
                Text("Providers updated \(Self.shortDate(catalog.updated))")
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    .padding(.top, 10)
            }
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    /// "2026-11-09T02:00" → "Nov 9, 2026" (falls back to the raw text).
    static func shortDate(_ raw: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(raw.prefix(10))) else { return raw }
        return d.formatted(date: .abbreviated, time: .omitted)
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
                SettingsBadge(text: "Up to date")
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
