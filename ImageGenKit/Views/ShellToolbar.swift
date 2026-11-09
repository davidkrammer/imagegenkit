import SwiftUI

/// One filter menu for Overview, Gallery and History: provider, plus "Show Deleted" in the Gallery.
struct ShellFilterMenu: View {
    var showDeletedToggle = false
    @Environment(LogStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("Provider", selection: $store.providerFilter) {
                Text("All Providers").tag(String?.none)
                Divider()
                ForEach(store.loggedProviders, id: \.self) { Text(ProviderStyle.label($0)).tag(String?.some($0)) }
            }
            .pickerStyle(.inline)
            if showDeletedToggle {
                Divider()
                Toggle("Show Deleted Images", isOn: Binding(get: { !store.hideDeleted }, set: { store.hideDeleted = !$0 }))
            }
        } label: {
            Label(store.providerFilter.map(ProviderStyle.label) ?? "All Providers",
                  systemImage: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .labelStyle(.titleAndIcon)
        }
        .help("Filter")
    }

    private var filtered: Bool { store.providerFilter != nil || (showDeletedToggle && !store.hideDeleted) }
}

/// Time range as a compact pop-up, so the toolbar fits at the smallest window size.
struct ShellRangePicker: View {
    @Environment(LogStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Picker(selection: $store.range) {
            ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
        } label: {
            Label("Range", systemImage: "calendar")
        }
        .pickerStyle(.menu)
        .help("Time range")
    }
}
