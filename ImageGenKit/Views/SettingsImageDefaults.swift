import SwiftUI

/// Settings › Images: one collapsible row per provider with only the options it supports.
/// Values live in config.json under provider_defaults.<id>.<key> ("" = the provider's own default).
struct SettingsProviderImageRow: View {
    @Environment(Installer.self) private var installer
    let provider: ProviderInfo
    @Environment(ConfigStore.self) private var config
    @Environment(Catalog.self) private var catalog
    @State private var open: Bool
    @State private var hovering = false

    init(provider: ProviderInfo) {
        self.provider = provider
        #if DEBUG
        let ids = (UserDefaults.standard.string(forKey: "debugExpandProviders") ?? "").split(separator: ",").map(String.init)
        _open = State(initialValue: ids.contains(provider.id))
        #else
        _open = State(initialValue: false)
        #endif
    }

    private var kind: ProviderKind { provider.kind }
    private var expandable: Bool { GenerateSpec.hasSettings(kind) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if open && expandable {
                VStack(spacing: 0) { options }
                    .padding(.vertical, 4)
                    .background(Theme.well.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.leading, 58)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        Button {
            guard expandable else { return }
            withAnimation(.snappy(duration: 0.22)) { open.toggle() }
        } label: {
            HStack(spacing: 12) {
                SettingsProviderTile(id: provider.id, kind: provider.kind, size: 32)
                Text(provider.label).foregroundStyle(.primary).lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if expandable {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(hovering && expandable ? Color.primary.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        let sizes = GenerateSpec.sizes(kind)
        let qualities = GenerateSpec.qualities(kind)
        let backgrounds = GenerateSpec.backgrounds(kind)
        let formats = GenerateSpec.formats(kind)
        if GenerateSpec.hasModel(kind) {
            optionRow("Model") { modelField("model", editing: false) }
        }
        if GenerateSpec.hasEditModel(kind) {
            optionRow("Edit model") { modelField("edit_model", editing: true) }
        }
        if !qualities.isEmpty {
            optionRow("Quality") { choice("quality", qualities, label: \.capitalized) }
        }
        if !sizes.isEmpty {
            optionRow("Size") { choice("resolution", sizes) }
        }
        if !backgrounds.isEmpty {
            optionRow("Background") { choice("background", backgrounds.filter { $0 != "auto" }, label: \.capitalized) }
        }
        if !formats.isEmpty {
            optionRow("Format") { choice("format", formats, label: GenerateSpec.formatLabel) }
        }
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                content()
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
    }

    /// OpenAI's quality and size always have a value (the CLI's old global defaults), so no "Auto" there.
    private func hasFallback(_ key: String) -> Bool {
        kind == .openai && (key == "quality" || key == "resolution")
    }

    private func choice(_ key: String, _ values: [String], label: @escaping (String) -> String = { $0 }) -> some View {
        let binding = config.providerDefaultBinding(provider.id, key)
        let options = hasFallback(key) ? values : [""] + values
        return GenerateSegmented(options: options, selection: Binding(
            get: { options.contains(binding.wrappedValue) ? binding.wrappedValue : (options.first ?? "") },
            set: { binding.wrappedValue = $0 }
        ), label: { $0.isEmpty ? GenerateSpec.auto : label($0) })
    }

    private func modelField(_ key: String, editing: Bool) -> some View {
        modelFieldBody(key, editing: editing)
            .task(id: provider.id) { await LiveModels.shared.load(provider, installer: installer) }
    }

    private func modelFieldBody(_ key: String, editing: Bool) -> some View {
        let binding = config.providerDefaultBinding(provider.id, key)
        let suggestions = (catalog.entry(provider.catalogID ?? provider.id)?.models ?? [])
            + (LiveModels.shared.models[provider.id] ?? []).filter { !(catalog.entry(provider.catalogID ?? provider.id)?.models ?? []).contains($0) }
        let builtin = (editing ? provider.editModel : nil) ?? provider.model ?? ""
        return HStack(spacing: 6) {
            TextField(key, text: binding, prompt: Text(builtin.isEmpty ? "Default" : builtin))
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .frame(width: 230)
            if !suggestions.isEmpty {
                Menu {
                    if !hasModelFallback {
                        Button("Default") { binding.wrappedValue = "" }
                        Divider()
                    }
                    ForEach(suggestions, id: \.self) { m in
                        Button { binding.wrappedValue = m } label: {
                            if m == binding.wrappedValue { Label(m, systemImage: "checkmark") } else { Text(m) }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Models")
            }
        }
    }

    /// Built-in API providers fall back to the CLI's old global model keys, so they always show a model.
    private var hasModelFallback: Bool { [.openai, .xai, .gemini].contains(kind) }

    // MARK: Summary

    private var summary: String {
        guard expandable else { return "No settings" }
        let d = { (key: String) in config.providerDefault(provider.id, key) }
        var parts: [String] = []
        if !d("quality").isEmpty { parts.append(d("quality").capitalized) }
        if !d("resolution").isEmpty { parts.append(d("resolution")) }
        if d("background") == "transparent" { parts.append("Transparent") }
        if d("background") == "opaque" { parts.append("Opaque") }
        if !d("format").isEmpty && d("format") != "png" { parts.append(GenerateSpec.formatLabel(d("format"))) }
        if GenerateSpec.hasModel(kind) {
            let m = d("model").isEmpty ? (provider.model ?? "") : d("model")
            if !m.isEmpty { parts.append(m) }
        }
        return parts.isEmpty ? "Default" : parts.joined(separator: " · ")
    }
}
