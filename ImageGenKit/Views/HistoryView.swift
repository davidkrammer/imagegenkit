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
                Text(row.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).hour().minute()))
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 140)
            TableColumn("Provider", value: \.provider) { row in
                HStack(spacing: 6) {
                    Circle().fill(ProviderStyle.color(row.entry.provider)).frame(width: 8, height: 8)
                    Text(row.provider)
                }
            }
            .width(min: 70, ideal: 80)
            TableColumn("Type") { (row: HistoryRow) in Text(row.entry.kindLabel) }
                .width(min: 55, ideal: 65)
            TableColumn("Model", value: \.model)
                .width(min: 100, ideal: 150)
            TableColumn("Images", value: \.images) { row in Text("\(row.images)").monospacedDigit() }
                .width(min: 45, ideal: 50)
            TableColumn("Size", value: \.size)
                .width(min: 70, ideal: 85)
            TableColumn("Cost", value: \.cost) { row in
                if row.cost >= 0 {
                    Text(Format.usd(row.cost, precise: true)).monospacedDigit()
                } else {
                    Text("subscription").foregroundStyle(.secondary)
                }
            }
            .width(min: 70, ideal: 85)
            TableColumn("Time", value: \.seconds) { row in Text(Format.seconds(row.entry.seconds)).monospacedDigit() }
                .width(min: 45, ideal: 55)
            TableColumn("Project", value: \.project)
                .width(min: 90, ideal: 140)
            TableColumn("Prompt", value: \.prompt) { row in
                Text(row.prompt).lineLimit(1).help(row.prompt)
            }
            .width(min: 160, ideal: 400)
        }
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
            if rows.isEmpty && !store.searchText.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
        .navigationSubtitle("\(rows.count) runs")
    }
}
