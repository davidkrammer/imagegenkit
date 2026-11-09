import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case gallery = "Gallery"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .gallery: "photo.on.rectangle.angled"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @Environment(Updater.self) private var updater
    @Environment(Catalog.self) private var catalog
    @AppStorage("sidebarSection") private var item: SidebarItem = .overview
    @State private var showInspector = false
    @State private var showGenerate = false

    var body: some View {
        NavigationSplitView {
            SidebarColumn(item: $item, showGenerate: $showGenerate)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                if item == .settings {
                    SettingsView().navigationTitle("Settings")
                } else {
                    content
                }
            }
            .background(Theme.background)
        }
        .sheet(isPresented: $showGenerate) { GenerateView() }
        .background(GenerateDebugPresenter())
        .background(OnboardingPresenter { destination in
            switch destination {
            case .generate: showGenerate = true
            case .gallery: item = .gallery
            case .settings: item = .settings
            }
        })
        .onAppear(perform: applyLaunchSection)
        .onChange(of: store.selectedID) { _, id in
            if id != nil { showInspector = true }
        }
        .task {
            store.start()
            applyLaunchOptions()
            config.catalogPrices = Dictionary(uniqueKeysWithValues: catalog.providers.map { ($0.id, $0.prices) })
            await installer.refresh()
            await status.refresh(config.providers)
            await updater.check(quiet: true)
            await catalog.refresh()
            config.catalogPrices = Dictionary(uniqueKeysWithValues: catalog.providers.map { ($0.id, $0.prices) })
        }
    }

    private var content: some View {
        @Bindable var store = store
        return Group {
            switch item {
            case .gallery: GalleryView()
            case .history: HistoryView()
            default: OverviewView(addProvider: { item = .settings }, generate: { showGenerate = true })
            }
        }
        .navigationTitle(item.rawValue)
        .modifier(SearchIf(enabled: item != .overview, text: $store.searchText))
        .inspector(isPresented: $showInspector) {
            Group {
                if let entry = store.selected {
                    EntryDetailView(entry: entry)
                } else {
                    ContentUnavailableView("Nothing selected", systemImage: "photo")
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
        }
        .toolbar {
            if item == .gallery {
                ToolbarItem {
                    Button { store.hideDeleted.toggle() } label: {
                        Label(store.hideDeleted ? "Show Deleted" : "Hide Deleted",
                              systemImage: store.hideDeleted ? "eye.slash" : "eye")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .help(store.hideDeleted ? "Show deleted images" : "Hide deleted images")
                }
            }
            if !(item == .overview && store.entries.isEmpty) {
                ToolbarItem {
                    Menu {
                        Picker("Provider", selection: $store.providerFilter) {
                            Text("All Providers").tag(String?.none)
                            Divider()
                            ForEach(store.loggedProviders, id: \.self) { Text(ProviderStyle.label($0)).tag(String?.some($0)) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(store.providerFilter.map(ProviderStyle.label) ?? "All Providers",
                              systemImage: "line.3.horizontal.decrease")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Provider")
                }
                ToolbarItem {
                    Picker("Range", selection: $store.range) {
                        ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help("Time range")
                }
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
                    .help("Details")
            }
        }
    }

    private func applyLaunchSection() {
        if let s = UserDefaults.standard.string(forKey: "startSection"),
           let match = SidebarItem.allCases.first(where: { $0.rawValue.lowercased() == s.lowercased() }) {
            item = match
        }
    }

    /// `-startSection gallery -startRange all -selectLatest YES -overviewEmpty YES` (screenshots and docs).
    private func applyLaunchOptions() {
        let defaults = UserDefaults.standard
        applyLaunchSection()
        if let r = defaults.string(forKey: "startRange"), let match = TimeRange.allCases.first(where: { "\($0)" == r }) {
            store.range = match
        }
        if defaults.bool(forKey: "selectLatest"), let last = store.entries.last(where: { !$0.outputs.isEmpty }) {
            store.selectedID = last.id
        }
        #if DEBUG
        if defaults.bool(forKey: "debugInstallCLI") { Task { await installer.installCLI() } }
        #endif
    }
}

// MARK: - Sidebar

/// Neutral sidebar: app identity, navigation, and the Generate button.
private struct SidebarColumn: View {
    @Binding var item: SidebarItem
    @Binding var showGenerate: Bool
    @Environment(ConfigStore.self) private var config
    @Environment(ProviderStatus.self) private var status
    @Environment(Installer.self) private var installer
    @Environment(Updater.self) private var updater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarIdentity()
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 18)

            List(selection: Binding(ignoringNil: $item)) {
                ForEach(SidebarItem.allCases) { entry in
                    Label(entry.rawValue, systemImage: entry.icon)
                        .badge(entry == .settings && (installer.needsAttention || updater.updateAvailable) ? Text("1") : nil)
                        .tag(entry)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(SidebarItem.allCases.count) * 34 + 12)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Button { showGenerate = true } label: {
                    Label("Generate", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
                .help("Generate an image (⌘N)")

                if let readyCount {
                    SidebarProviderFooter(ready: readyCount) { item = .settings }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar)
    }

    /// Nil until the first status check has finished.
    private var readyCount: Int? {
        let states = config.providers.map { status.state($0.id) }
        guard states.contains(where: { $0 != .unknown }) else { return nil }
        return states.filter(\.isReady).count
    }
}

private struct SidebarIdentity: View {
    var body: some View {
        HStack(spacing: 9) {
            AppIconView(size: 30)
            Text("ImageGenKit")
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

private struct SidebarProviderFooter: View {
    let ready: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(ready == 0 ? "No provider set up" : ready == 1 ? "1 provider ready" : "\(ready) providers ready")
            } icon: {
                Circle().fill(ready > 0 ? Color.green : Color.orange).frame(width: 6, height: 6)
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .help("Providers")
    }
}

private struct SearchIf: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, placement: .toolbar, prompt: "Search")
        } else {
            content
        }
    }
}

extension Binding where Value == SidebarItem? {
    /// Adapts a non-optional selection for `List(selection:)`, ignoring deselection.
    init(ignoringNil base: Binding<SidebarItem>) {
        self.init(get: { base.wrappedValue }, set: { if let v = $0 { base.wrappedValue = v } })
    }
}
