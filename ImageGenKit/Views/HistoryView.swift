import SwiftUI

nonisolated struct HistoryRow: Identifiable, Sendable {
    let entry: LogEntry
    let cost: Double
    let provider: String
    var id: Int { entry.id }
    var date: Date { entry.date }
    var model: String { entry.modelLabel }
    var images: Int { entry.imageCount }
    var size: String { entry.sizeLabel }
    var project: String { entry.project }
    var seconds: Double { entry.seconds ?? 0 }
    var prompt: String { entry.prompt }
}

struct HistoryView: View {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config
    @State private var sortOrder = [KeyPathComparator(\HistoryRow.date, order: .reverse)]

    var body: some View {
        @Bindable var store = store
        let rows = store.filtered
            .map { HistoryRow(entry: $0, cost: config.cost($0) ?? -1, provider: ProviderStyle.label($0.provider)) }
            .sorted(using: sortOrder)
        Table(rows, selection: $store.selectedID, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { row in
                HStack(spacing: 10) {
                    HistoryThumb(entry: row.entry)
                    Text(HistoryFormat.date(row.date))
                        .monospacedDigit()
                }
            }
            .width(min: 140, ideal: 160)
            TableColumn("Provider", value: \.provider) { row in
                HStack(spacing: 7) {
                    Circle().fill(ProviderStyle.color(row.entry.provider)).frame(width: 8, height: 8)
                    Text(row.provider)
                }
            }
            .width(min: 70, ideal: 85)
            TableColumn("Type") { (row: HistoryRow) in
                Text(row.entry.kindLabel).foregroundStyle(.secondary)
            }
            .width(min: 55, ideal: 65)
            TableColumn("Model", value: \.model) { row in
                Text(row.model).lineLimit(1)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Images", value: \.images) { row in
                Text("\(row.images)").monospacedDigit().foregroundStyle(row.images == 0 ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 45, ideal: 52)
            TableColumn("Size", value: \.size) { row in
                Text(row.size).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 85)
            TableColumn("Cost", value: \.cost) { row in
                Group {
                    if row.cost >= 0 {
                        Text(HistoryFormat.cost(row.cost)).monospacedDigit()
                    } else {
                        Text("subscription").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 85)
            TableColumn("Time", value: \.seconds) { row in
                Text(Format.seconds(row.entry.seconds)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 45, ideal: 55)
            TableColumn("Project", value: \.project) { row in
                Text(row.project).lineLimit(1)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Prompt", value: \.prompt) { row in
                Text(row.prompt).lineLimit(1).foregroundStyle(.secondary).help(row.prompt)
            }
            .width(min: 160, ideal: 400)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
            if let id = ids.first, let entry = store.entries.last(where: { $0.id == id }) {
                ImageMenu(entry: entry)
            }
        } primaryAction: { ids in
            if let id = ids.first, let entry = store.entries.last(where: { $0.id == id }), !entry.outputs.isEmpty {
                Actions.open(entry.imageRef(0))
            }
        }
        .overlay {
            if rows.isEmpty {
                if store.searchText.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "list.bullet.rectangle")
                } else {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
        .navigationSubtitle("\(rows.count) runs")
    }
}

enum HistoryFormat {
    static func date(_ d: Date) -> String {
        let sameYear = Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
        return sameYear
            ? d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
            : d.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    /// $0.042 for small amounts, $1.20 from a dollar up, "–" for free.
    static func cost(_ v: Double) -> String {
        if v == 0 { return "–" }
        return Format.usd(v, precise: v < 1)
    }
}

/// Tiny rounded preview of a run's first image (gives rows a comfortable height).
private struct HistoryThumb: View {
    let entry: LogEntry
    @State private var image: CGImage?

    var body: some View {
        Theme.well
            .frame(width: 24, height: 24)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: entry.outputs.isEmpty ? "minus" : "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.vertical, 2)
            .task(id: entry.id) {
                guard !entry.outputs.isEmpty else { return }
                image = await Thumbnails.thumbnail(entry.imageRef(0))
            }
    }
}
