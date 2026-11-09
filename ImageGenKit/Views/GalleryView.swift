import SwiftUI

struct GalleryView: View {
    @Environment(LogStore.self) private var store
    @AppStorage("galleryTileSize") private var tileSize: Double = 140
    @State private var width: CGFloat = 800
    @State private var showGenerate = false
    @FocusState private var focused: Bool

    private static let sizes: [Double] = [110, 140, 180, 230, 300]
    private static let gap: CGFloat = 16
    private static let pad: CGFloat = 24

    var body: some View {
        let items = store.galleryItems
        let sections = GallerySection.group(items)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.5), spacing: Self.gap)],
                          alignment: .leading, spacing: Self.gap, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                tile(item)
                            }
                        } header: {
                            GallerySectionHeader(title: section.title, count: section.items.count)
                        }
                    }
                }
                .padding(.horizontal, Self.pad)
                .padding(.bottom, Self.pad)
                .animation(.smooth(duration: 0.3), value: tileSize)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.leftArrow) { move(.left, sections, proxy) }
            .onKeyPress(.rightArrow) { move(.right, sections, proxy) }
            .onKeyPress(.upArrow) { move(.up, sections, proxy) }
            .onKeyPress(.downArrow) { move(.down, sections, proxy) }
            .onKeyPress(.return) { openSelected(items) }
        }
        .background(Theme.background)
        .overlay {
            if items.isEmpty { emptyState }
        }
        .toolbar {
            if !items.isEmpty {
            ToolbarItem {
                ControlGroup {
                    Button { step(-1) } label: { Label("Smaller", systemImage: "minus.magnifyingglass") }
                        .keyboardShortcut("-", modifiers: .command)
                        .disabled(tileSize <= Self.sizes.first!)
                        .help("Smaller (⌘−)")
                    Button { step(1) } label: { Label("Larger", systemImage: "plus.magnifyingglass") }
                        .keyboardShortcut("=", modifiers: .command)
                        .disabled(tileSize >= Self.sizes.last!)
                        .help("Larger (⌘+)")
                } label: {
                    Label("Tile Size", systemImage: "square.grid.2x2")
                }
            }
            }
        }
        .navigationSubtitle(items.count == 1 ? "1 image" : "\(items.count) images")
        .sheet(isPresented: $showGenerate) { GenerateView() }
    }

    private func tile(_ item: GalleryItem) -> some View {
        GalleryTile(item: item,
                    selected: store.selectedID == item.entry.id && store.selectedImageIndex == item.index,
                    missing: store.missing.contains(item.id))
            .id(item.id)
            .onTapGesture {
                focused = true
                withAnimation(.easeOut(duration: 0.15)) { store.select(item) }
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { Actions.open(item.ref) })
            .contextMenu { ImageMenu(entry: item.entry, index: item.index) }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        if !store.searchText.isEmpty {
            GalleryEmptyState(symbol: "magnifyingglass", title: "No results",
                              lead: "Nothing matches “\(store.searchText)”.") {
                Button("Clear Search") { store.searchText = "" }
            }
        } else if store.entries.contains(where: { !$0.outputs.isEmpty }) {
            GalleryEmptyState(symbol: "calendar", title: "Nothing here",
                              lead: "No images in this range.") {
                Button("Show All") {
                    withAnimation(.smooth(duration: 0.3)) {
                        store.range = .all
                        store.providerFilter = nil
                    }
                }
            }
        } else {
            GalleryEmptyState(symbol: nil, title: "No images yet",
                              lead: "Everything you generate shows up here.") {
                Button { showGenerate = true } label: { Label("Generate", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Size and keyboard

    private func step(_ delta: Int) {
        let current = Self.sizes.enumerated().min { abs($0.element - tileSize) < abs($1.element - tileSize) }?.offset ?? 1
        let next = max(0, min(Self.sizes.count - 1, current + delta))
        tileSize = Self.sizes[next]
    }

    private var columns: Int {
        let available = width - Self.pad * 2
        return max(1, Int((available + Self.gap) / (CGFloat(tileSize) + Self.gap)))
    }

    private enum Direction { case left, right, up, down }

    private func move(_ direction: Direction, _ sections: [GallerySection], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let flat = sections.flatMap(\.items)
        guard !flat.isEmpty else { return .ignored }
        guard let current = flat.firstIndex(where: { $0.entry.id == store.selectedID && $0.index == store.selectedImageIndex }) else {
            select(flat[0], proxy)
            return .handled
        }
        var target: GalleryItem?
        switch direction {
        case .left: target = current > 0 ? flat[current - 1] : nil
        case .right: target = current + 1 < flat.count ? flat[current + 1] : nil
        case .up, .down:
            // Positions inside the item's day section, so up/down keeps the column.
            var start = 0
            for (s, section) in sections.enumerated() {
                let end = start + section.items.count
                if current < end {
                    let pos = current - start
                    let col = pos % columns
                    if direction == .up {
                        if pos >= columns {
                            target = section.items[pos - columns]
                        } else if s > 0 {
                            let prev = sections[s - 1].items
                            let lastRow = (prev.count - 1) / columns * columns
                            target = prev[min(prev.count - 1, lastRow + col)]
                        }
                    } else {
                        if pos + columns < section.items.count {
                            target = section.items[pos + columns]
                        } else if (pos / columns) < (section.items.count - 1) / columns {
                            target = section.items.last
                        } else if s + 1 < sections.count {
                            let next = sections[s + 1].items
                            target = next[min(next.count - 1, col)]
                        }
                    }
                    break
                }
                start = end
            }
        }
        guard let target else { return .handled }
        select(target, proxy)
        return .handled
    }

    private func select(_ item: GalleryItem, _ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { store.select(item) }
        withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(item.id) }
    }

    private func openSelected(_ items: [GalleryItem]) -> KeyPress.Result {
        guard let item = items.first(where: { $0.entry.id == store.selectedID && $0.index == store.selectedImageIndex }) else {
            return .ignored
        }
        Actions.open(item.ref)
        return .handled
    }
}

// MARK: - Day sections

private struct GallerySection: Identifiable {
    let day: Date
    var items: [GalleryItem]
    var id: Date { day }

    var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: day, to: cal.startOfDay(for: .now)).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        if cal.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Items are newest first; keeps that order and starts a new section per day.
    static func group(_ items: [GalleryItem]) -> [GallerySection] {
        let cal = Calendar.current
        var sections: [GallerySection] = []
        for item in items {
            let day = cal.startOfDay(for: item.entry.date)
            if sections.last?.day == day {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(GallerySection(day: day, items: [item]))
            }
        }
        return sections
    }
}

private struct GallerySectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text("\(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }
}

// MARK: - Empty state

/// Looks like a tour step: a soft picture, one title, one line, native buttons.
private struct GalleryEmptyState<Buttons: View>: View {
    let symbol: String?
    let title: String
    let lead: String
    @ViewBuilder var actions: Buttons

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(width: 340, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
                .galleryEnter(0)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 24)
                .galleryEnter(1)
            Text(lead)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 5)
                .galleryEnter(2)
            HStack(spacing: 10) { actions }
                .padding(.top, 20)
                .galleryEnter(3)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var picture: some View {
        ZStack {
            GalleryWash()
            if let symbol {
                IconBadge(symbol: symbol, size: 64)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
                    .onboardingFloat(4, duration: 3)
                    .onboardingPop(0.05)
            } else {
                let fan: [(OnboardingSample, CGFloat, Double, CGFloat)] = [
                    (.mountain, -98, -8, 92), (.robot, 98, 7, 88),
                ]
                ForEach(Array(fan.enumerated()), id: \.offset) { i, item in
                    OnboardingSampleImage(sample: item.0, height: item.3)
                        .onboardingFloat(4, duration: 2.8 + Double(i) * 0.4, tilt: item.2)
                        .offset(x: item.1, y: 6)
                        .onboardingPop(0.08 * Double(i))
                }
                OnboardingSampleImage(sample: .mug, height: 110)
                    .onboardingFloat(4, duration: 3.3)
                    .onboardingPop(0.2)
            }
        }
    }
}

// MARK: - Tile

private struct GalleryTile: View {
    let item: GalleryItem
    let selected: Bool
    let missing: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        GalleryTileImage(ref: item.ref, missing: missing)
            .overlay(alignment: .bottomLeading) {
                if hovering {
                    VStack(alignment: .leading, spacing: 6) {
                        ProviderBadge(provider: item.entry.provider)
                            .environment(\.colorScheme, .dark)
                        Text(item.entry.prompt)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(10)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.5), .black.opacity(0.72)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.07)) }
            .overlay {
                if selected {
                    shape.inset(by: -4).strokeBorder(Theme.accent, lineWidth: 2.5)
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.05), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .contentShape(shape)
            .onHover { h in withAnimation(.easeOut(duration: 0.16)) { hovering = h } }
            .help(item.entry.prompt)
            .accessibilityElement()
            .accessibilityLabel(item.entry.prompt)
            .accessibilityAddTraits(selected ? [.isImage, .isSelected] : .isImage)
    }
}

/// Square image that loads the archived preview; deleted images get a quiet placeholder.
private struct GalleryTileImage: View {
    let ref: ImageRef
    let missing: Bool
    @State private var image: CGImage?
    @State private var loaded = false

    var body: some View {
        Theme.well
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .transition(.opacity)
                } else if loaded || missing {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: ref) {
                let img = await Thumbnails.thumbnail(ref)
                withAnimation(.easeOut(duration: 0.2)) {
                    image = img
                    loaded = true
                }
            }
    }
}
