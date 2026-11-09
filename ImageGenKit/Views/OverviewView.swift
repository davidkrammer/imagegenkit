import Charts
import SwiftUI

struct OverviewView: View {
    var addProvider: () -> Void = {}
    var generate: () -> Void = {}
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config

    var body: some View {
        if isEmpty {
            OverviewEmptyState(addProvider: addProvider, generate: generate)
        } else {
            dashboard
        }
    }

    private var isEmpty: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "overviewEmpty") { return true }  // screenshots
        #endif
        return store.entries.isEmpty
    }

    private var dashboard: some View {
        let stats = Stats(entries: store.inRange, rangeStart: store.range.start, cost: config.cost)
        let allTime = Stats(entries: store.entries, rangeStart: nil, cost: config.cost)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let cards = statCards(stats)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { ForEach(cards) { $0 } }
                        .frame(minWidth: 540)
                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow { cards[0]; cards[1] }
                        GridRow { cards[2]; cards[3] }
                    }
                }

                OverviewSection(title: "Images") { OverviewChart(stats: stats, metric: .images) }
                OverviewSection(title: "Spend") {
                    if stats.cost > 0 {
                        OverviewChart(stats: stats, metric: .cost)
                    } else {
                        OverviewNote(text: "No paid runs in this range")
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { breakdowns(stats) }
                        .frame(minWidth: 600)
                    VStack(spacing: 16) { breakdowns(stats) }
                }

                OverviewSection(title: "Months", columns: true) { OverviewMonths(months: allTime.months) }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Theme.background)
    }

    private func statCards(_ stats: Stats) -> [OverviewStatCard] {
        [
            OverviewStatCard(title: "Spend", value: Format.usd(stats.cost), symbol: "dollarsign",
                             color: Color(light: 0x1BAF7A, dark: 0x2BC48C)),
            OverviewStatCard(title: "Images", value: stats.images.formatted(), symbol: "photo", color: Theme.accent,
                             detail: stats.paidImages == stats.images ? nil : "\(stats.paidImages) paid"),
            OverviewStatCard(title: "Runs", value: stats.runs.formatted(), symbol: "bolt",
                             color: Color(light: 0xEB6834, dark: 0xF07A48)),
            OverviewStatCard(title: "Avg. time", value: Format.seconds(stats.averageSeconds), symbol: "timer",
                             color: Color(light: 0x2A78D6, dark: 0x4A93EA)),
        ]
    }

    @ViewBuilder
    private func breakdowns(_ stats: Stats) -> some View {
        OverviewSection(title: "Providers", columns: true) {
            OverviewBreakdown(groups: stats.byProvider, colored: true)
        }
        OverviewSection(title: "Projects", columns: true) {
            OverviewBreakdown(groups: stats.byProject, colored: false)
        }
    }
}

// MARK: - Building blocks

private struct OverviewStatCard: View, Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let symbol: String
    let color: Color
    var detail: String?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconBadge(symbol: symbol, color: color, size: 26)
                Text(title).font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .offset(y: hovering ? -1 : 0)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Card with a title; `columns` adds the "Images · Spend" captions for breakdown lists.
private struct OverviewSection<Content: View>: View {
    let title: String
    var columns = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if columns {
                    HStack(spacing: 0) {
                        Text("Images").frame(width: OverviewBreakdown.imagesWidth, alignment: .trailing)
                        Text("Spend").frame(width: OverviewBreakdown.spendWidth, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }
}

private struct OverviewNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

/// Thin proportional bar.
private struct OverviewBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule().fill(color.gradient)
                    .frame(width: max(4, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Empty state

private struct OverviewEmptyState: View {
    let addProvider: () -> Void
    let generate: () -> Void

    var body: some View {
        OnboardingFirstSteps(generate: generate)
    }
}

// MARK: - Chart

private struct OverviewChart: View {
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
                    .opacity(hovered == nil || hovered == b.start ? 1 : 0.35)
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered, unit: stats.unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        OverviewTooltip(stats: stats, start: hovered)
                    }
            }
        }
        .chartForegroundStyleScale(domain: ids.map(ProviderStyle.label), range: ids.map(ProviderStyle.color))
        .chartXScale(domain: stats.domain)
        .chartLegend(ids.count > 1 ? .visible : .hidden)
        .chartLegend(position: .top, alignment: .trailing)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(metric == .cost ? Format.axisUSD(v) : "\(Int(v))") }
                }
                .foregroundStyle(Color.secondary)
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
        .animation(.easeOut(duration: 0.15), value: hovered)
        .frame(height: metric == .cost ? 150 : 190)
    }
}

private struct OverviewTooltip: View {
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
                    Text(ProviderStyle.label(b.provider))
                    Spacer(minLength: 8)
                    Text("\(b.images)")
                    if b.cost > 0 { Text(Format.usd(b.cost, precise: true)).foregroundStyle(.secondary) }
                }
                .font(.caption)
                .monospacedDigit()
            }
        }
        .padding(9)
        .frame(minWidth: 130)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
    }
}

// MARK: - Lists

private struct OverviewBreakdown: View {
    static let imagesWidth: CGFloat = 56
    static let spendWidth: CGFloat = 84
    let groups: [Stats.Group]
    let colored: Bool
    private let limit = 6

    var body: some View {
        if groups.isEmpty {
            OverviewNote(text: "No runs in this range")
        } else {
            let top = rows.map(\.images).max() ?? 1
            VStack(spacing: 12) {
                ForEach(rows) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            HStack(spacing: 7) {
                                if colored { Circle().fill(ProviderStyle.color(g.id)).frame(width: 8, height: 8) }
                                Text(g.name).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Text(g.images.formatted())
                                .monospacedDigit()
                                .frame(width: Self.imagesWidth, alignment: .trailing)
                            Text(g.subscription ? "Plan" : Format.usd(g.cost))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: Self.spendWidth, alignment: .trailing)
                        }
                        .font(.callout)
                        OverviewBar(fraction: Double(g.images) / Double(max(top, 1)),
                                    color: colored ? ProviderStyle.color(g.id) : Theme.accent)
                    }
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

private struct OverviewMonths: View {
    let months: [Stats.Month]
    @State private var showAll = false

    var body: some View {
        let shown = showAll ? months : Array(months.prefix(4))
        let top = months.map(\.images).max() ?? 1
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Divider().opacity(0.5) }
                HStack(spacing: 14) {
                    Text(m.start.formatted(.dateTime.month(.wide).year()))
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    OverviewBar(fraction: Double(m.images) / Double(max(top, 1)), color: Theme.accent)
                        .frame(maxWidth: .infinity)
                    Text(m.images.formatted())
                        .monospacedDigit()
                        .frame(width: OverviewBreakdown.imagesWidth, alignment: .trailing)
                    Text(Format.usd(m.cost))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: OverviewBreakdown.spendWidth, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 9)
            }
            if months.count > 4 {
                Button(showAll ? "Show less" : "Show all") {
                    withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() }
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Theme.accent)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
