import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config

    var body: some View {
        let stats = Stats(entries: store.inRange, rangeStart: store.range.start, cost: config.cost)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StatTile(title: "Spend", value: Format.usd(stats.cost), detail: "estimated")
                    StatTile(title: "Images", value: "\(stats.images)", detail: "\(stats.paidImages) paid")
                    StatTile(title: "Runs", value: "\(stats.runs)", detail: "\(stats.providers.count) providers")
                    StatTile(title: "Avg. time", value: Format.seconds(stats.averageSeconds))
                }

                Card(title: "Images") { ProviderBarChart(stats: stats, metric: .images) }
                Card(title: "Spend") { ProviderBarChart(stats: stats, metric: .cost) }

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Providers") { GroupTable(groups: stats.byProvider, limit: 8, colored: true) }
                    Card(title: "Projects") { GroupTable(groups: stats.byProject, limit: 8, colored: false) }
                }
                Card(title: "Months") {
                    MonthTable(months: Stats(entries: store.entries, rangeStart: nil, cost: config.cost).months)
                }
            }
            .padding(20)
        }
        .overlay {
            if store.entries.isEmpty {
                ContentUnavailableView("No images yet", systemImage: "photo.stack",
                                       description: Text("Runs show up here as soon as imagegen makes one."))
            }
        }
    }
}

// MARK: - Chart

struct ProviderBarChart: View {
    enum Metric { case images, cost }
    let stats: Stats
    let metric: Metric
    @State private var hovered: Date?

    var body: some View {
        let data = metric == .cost ? stats.buckets.filter { $0.cost > 0 } : stats.buckets
        let ids = metric == .cost ? stats.providers.filter { id in data.contains { $0.provider == id } } : stats.providers
        Chart {
            ForEach(data) { b in
                BarMark(x: .value("Date", b.start, unit: stats.unit),
                        y: .value(metric == .cost ? "Spend" : "Images", metric == .cost ? b.cost : Double(b.images)))
                    .foregroundStyle(by: .value("Provider", ProviderStyle.label(b.provider)))
                    .cornerRadius(3)
                    .opacity(hovered == nil || hovered == b.start ? 1 : 0.4)
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered, unit: stats.unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        BucketTooltip(stats: stats, start: hovered)
                    }
            }
        }
        .chartForegroundStyleScale(domain: ids.map(ProviderStyle.label), range: ids.map(ProviderStyle.color))
        .chartXScale(domain: stats.domain)
        .chartLegend(ids.count > 1 ? .visible : .hidden)
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(metric == .cost ? Format.axisUSD(v) : "\(Int(v))") }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geo[frame].origin.x
                            if let date: Date = proxy.value(atX: x), stats.domain.contains(date) {
                                hovered = stats.bucketStart(date)
                            } else {
                                hovered = nil
                            }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: metric == .cost ? 170 : 210)
    }
}

private struct BucketTooltip: View {
    let stats: Stats
    let start: Date

    var body: some View {
        let items = stats.buckets(at: start)
        VStack(alignment: .leading, spacing: 4) {
            Text(stats.unit == .day ? start.formatted(.dateTime.weekday().day().month())
                    : "Week of " + start.formatted(.dateTime.day().month()))
                .font(.caption.weight(.semibold))
            if items.isEmpty { Text("No runs").font(.caption).foregroundStyle(.secondary) }
            ForEach(items) { b in
                HStack(spacing: 6) {
                    Circle().fill(ProviderStyle.color(b.provider)).frame(width: 7, height: 7)
                    Text("\(ProviderStyle.label(b.provider))  \(b.images)")
                    if b.cost > 0 { Text(Format.usd(b.cost, precise: true)).foregroundStyle(.secondary) }
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}

// MARK: - Tables

struct GroupTable: View {
    let groups: [Stats.Group]
    let limit: Int
    let colored: Bool

    var body: some View {
        if groups.isEmpty {
            Text("–").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Runs").gridColumnAlignment(.trailing)
                    Text("Images").gridColumnAlignment(.trailing)
                    Text("Spend").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(rows) { g in
                    GridRow {
                        HStack(spacing: 6) {
                            if colored { Circle().fill(ProviderStyle.color(g.id)).frame(width: 8, height: 8) }
                            Text(g.name).lineLimit(1).truncationMode(.middle)
                        }
                        Text("\(g.runs)").monospacedDigit()
                        Text("\(g.images)").monospacedDigit()
                        Text(g.subscription ? "subscription" : Format.usd(g.cost))
                            .monospacedDigit()
                            .foregroundStyle(g.subscription ? .secondary : .primary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var rows: [Stats.Group] {
        guard groups.count > limit else { return groups }
        var other = Stats.Group(id: "__other", name: "Other")
        for g in groups[(limit - 1)...] {
            other.runs += g.runs
            other.images += g.images
            other.cost += g.cost
        }
        return Array(groups.prefix(limit - 1)) + [other]
    }
}

struct MonthTable: View {
    let months: [Stats.Month]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("Runs").gridColumnAlignment(.trailing)
                Text("Images").gridColumnAlignment(.trailing)
                Text("Spend").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(months) { m in
                GridRow {
                    Text(m.start.formatted(.dateTime.month(.wide).year()))
                    Text("\(m.runs)").monospacedDigit()
                    Text("\(m.images)").monospacedDigit()
                    Text(Format.usd(m.cost)).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }
}
