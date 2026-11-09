import SwiftUI

struct GalleryView: View {
    @Environment(LogStore.self) private var store
    @AppStorage("galleryTileSize") private var tileSize: Double = 140

    var body: some View {
        let items = store.galleryItems
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.6), spacing: 14)],
                      spacing: 14) {
                ForEach(items) { item in
                    GalleryTile(item: item,
                                selected: store.selectedID == item.entry.id && store.selectedImageIndex == item.index,
                                missing: store.missing.contains(item.id))
                        .onTapGesture { store.select(item) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { Actions.open(item.ref) })
                        .contextMenu { ImageMenu(entry: item.entry, index: item.index) }
                }
            }
            .padding(22)
            .animation(.smooth(duration: 0.25), value: tileSize)
        }
        .background(Theme.background)
        .overlay {
            if items.isEmpty {
                if store.searchText.isEmpty {
                    ContentUnavailableView("No images yet", systemImage: "photo.on.rectangle.angled")
                } else {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                GallerySizeSlider(value: $tileSize)
            }
        }
        .navigationSubtitle("\(items.count) images")
    }
}

/// Compact tile-size slider for the toolbar.
private struct GallerySizeSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3").font(.system(size: 10))
            Slider(value: $value, in: 100...320).controlSize(.mini).frame(width: 80)
            Image(systemName: "square").font(.system(size: 13))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .help("Tile size")
    }
}

private struct GalleryTile: View {
    let item: GalleryItem
    let selected: Bool
    let missing: Bool
    @State private var hovering = false

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.45), .black.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.07))
            }
            .overlay {
                if selected {
                    shape.inset(by: -4).strokeBorder(Theme.accent, lineWidth: 2.5)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.05), radius: hovering ? 10 : 4, y: hovering ? 4 : 2)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(shape)
            .onHover { h in withAnimation(.easeOut(duration: 0.16)) { hovering = h } }
            .animation(.easeOut(duration: 0.15), value: selected)
            .help(item.entry.prompt)
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
                    Image(systemName: "photo")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .background(Circle().fill(Theme.well).padding(-1))
                                .offset(x: 5, y: 4)
                        }
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
