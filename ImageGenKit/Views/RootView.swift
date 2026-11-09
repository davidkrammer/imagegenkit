import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case gallery = "Gallery"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .gallery: "photo.on.rectangle.angled"
        case .history: "list.bullet.rectangle"
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
    @SceneStorage("sidebar") private var item: SidebarItem = .overview
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: Binding(ignoringNil: $item)) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .badge(item == .settings && (installer.needsAttention || updater.updateAvailable) ? Text("!") : nil)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if item == .settings {
                SettingsView().navigationTitle("Settings")
            } else {
                content
            }
        }
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
            default: OverviewView()
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
                    Toggle(isOn: $store.hideDeleted) { Label("Hide Deleted", systemImage: "eye.slash") }
                        .help("Hide deleted images")
                }
            }
            ToolbarItem {
                Picker("Provider", selection: $store.providerFilter) {
                    Text("All").tag(String?.none)
                    ForEach(store.loggedProviders, id: \.self) { Text(ProviderStyle.label($0)).tag(String?.some($0)) }
                }
            }
            ToolbarItem {
                Picker("Range", selection: $store.range) {
                    ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.trailing") }
            }
        }
    }

    /// `-startSection gallery -startRange all -selectLatest YES -settingsTab Install` (screenshots and docs).
    private func applyLaunchOptions() {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: "startSection"),
           let match = SidebarItem.allCases.first(where: { $0.rawValue.lowercased() == s.lowercased() }) {
            item = match
        }
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
