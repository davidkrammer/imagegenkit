import SwiftUI

struct GalleryView: View {
    @Environment(LogStore.self) private var store

    var body: some View {
        let items = store.galleryItems
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12)], spacing: 16) {
                ForEach(items) { item in
                    GalleryCell(item: item, selected: store.selectedID == item.entry.id && store.selectedImageIndex == item.index)
                        .contentShape(Rectangle())
                        .onTapGesture { store.select(item) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { Actions.open(item.ref) })
                        .contextMenu { ImageMenu(entry: item.entry, index: item.index) }
                }
            }
            .padding(16)
        }
        .overlay {
            if items.isEmpty {
                if store.searchText.isEmpty {
                    ContentUnavailableView("No images", systemImage: "photo.on.rectangle")
                } else {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
        .navigationSubtitle("\(items.count) images")
    }
}

private struct GalleryCell: View {
    let item: GalleryItem
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(ref: item.ref)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .topLeading) {
                    ProviderBadge(provider: item.entry.provider).padding(6)
                }
            Text(item.entry.prompt)
                .font(.caption)
                .lineLimit(2)
                .help(item.entry.prompt)
            Text("\(item.entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · \(item.entry.project)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
