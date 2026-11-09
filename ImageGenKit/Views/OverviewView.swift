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
        let previous = previousStats
        let allTime = Stats(entries: store.entries, rangeStart: nil, cost: config.cost)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OverviewHero(range: store.range, stats: stats, since: store.entries.first?.date, recent: recentImages)
                    .overviewEnter(0)

                let cards = statCards(stats, previous: previous)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { ForEach(cards) { $0 } }
                        .frame(minWidth: 620)
                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow { cards[0]; cards[1] }
                        GridRow { cards[2]; cards[3] }
                    }
                }
                .overviewEnter(1)

                OverviewActivityCard(stats: stats).overviewEnter(2)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { breakdowns(stats) }
                        .frame(minWidth: 640)
                    VStack(spacing: 16) { breakdowns(stats) }
                }
                .overviewEnter(3)

                OverviewSection(title: "Months", symbol: "calendar", columns: true) {
                    OverviewMonths(months: allTime.months)
                }
                .overviewEnter(4)
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.35), value: store.range)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Theme.background)
    }

    /// The same span right before the selected range (nil for "All").
    private var previousStats: Stats? {
        guard let start = store.range.start, let days = store.range.days,
              let prevStart = Calendar.current.date(byAdding: .day, value: -days, to: start) else { return nil }
        let entries = store.entries.filter { $0.date >= prevStart && $0.date < start }
        guard !entries.isEmpty else { return nil }
        return Stats(entries: entries, rangeStart: prevStart, cost: config.cost)
    }

    /// Latest images in range (or overall), newest first, for the header.
    private var recentImages: [GalleryItem] {
        let source = store.inRange.contains { !$0.outputs.isEmpty } ? store.inRange : store.entries
        var items: [GalleryItem] = []
        for e in source.reversed() {
            for i in e.outputs.indices {
                let item = GalleryItem(entry: e, index: i)
                if !store.missing.contains(item.id) { items.append(item) }
                if items.count == 4 { return items }
            }
        }
        return items
    }

    private func statCards(_ stats: Stats, previous: Stats?) -> [OverviewStatCard] {
        let span = store.range.rawValue
        func delta(_ now: Double, _ before: Double?) -> Double? {
            guard let before, before > 0 else { return nil }
            return (now - before) / before
        }
        return [
            OverviewStatCard(title: "Spend", value: Format.usd(stats.cost), symbol: "dollarsign",
                             color: Color(light: 0x1BAF7A, dark: 0x2BC48C),
                             delta: delta(stats.cost, previous?.cost), span: span),
            OverviewStatCard(title: "Images", value: stats.images.formatted(), symbol: "photo", color: Theme.accent,
                             detail: stats.paidImages == stats.images ? nil : "\(stats.paidImages) paid",
                             delta: delta(Double(stats.images), previous.map { Double($0.images) }), span: span),
            OverviewStatCard(title: "Runs", value: stats.runs.formatted(), symbol: "bolt",
                             color: Color(light: 0xEB6834, dark: 0xF07A48),
                             delta: delta(Double(stats.runs), previous.map { Double($0.runs) }), span: span),
            OverviewStatCard(title: "Avg. time", value: Format.seconds(stats.averageSeconds), symbol: "timer",
                             color: Color(light: 0x2A78D6, dark: 0x4A93EA)),
        ]
    }

    @ViewBuilder
    private func breakdowns(_ stats: Stats) -> some View {
        OverviewSection(title: "Providers", symbol: "square.stack.3d.up", columns: true) {
            OverviewBreakdown(groups: stats.byProvider, colored: true)
        }
        OverviewSection(title: "Projects", symbol: "folder", columns: true) {
            OverviewBreakdown(groups: stats.byProject, colored: false)
        }
    }
}

// MARK: - Header

/// Friendly summary of the range on an accent-washed, dotted panel, with the latest images fanned out.
private struct OverviewHero: View {
    let range: TimeRange
    let stats: Stats
    let since: Date?
    let recent: [GalleryItem]
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .contentTransition(.opacity)
                Text(lead)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if width > 600 && !recent.isEmpty {
                OverviewFan(items: recent).transition(.opacity)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 140)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(OverviewArtBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
    }

    private var title: String {
        switch range {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 90 days"
        case .all: "All time"
        }
    }

    private var lead: String {
        guard stats.runs > 0 else { return "Nothing generated in this range." }
        var parts: [String] = []
        if let top = stats.byProvider.max(by: { $0.images < $1.images }) {
            parts.append(stats.byProvider.count == 1 ? "All with \(top.name)" : "Mostly \(top.name)")
        }
        let projects = stats.byProject.count
        parts.append("\(projects) project\(projects == 1 ? "" : "s")")
        if range == .all, let since {
            parts.append("since \(since.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Up to four recent images, slightly fanned, floating gently. Click opens the image.
private struct OverviewFan: View {
    let items: [GalleryItem]
    private let tilts: [Double] = [-8, -3, 3, 8]

    var body: some View {
        HStack(spacing: -22) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                ThumbnailView(ref: item.ref)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.card, lineWidth: 3))
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                    .overviewFloat(4, duration: 2.8 + Double(i) * 0.35, tilt: tilts[i % tilts.count])
                    .overviewPop(0.1 + Double(i) * 0.08)
                    .zIndex(Double(i == 1 || i == 2 ? 1 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { Actions.open(item.ref) }
                    .contextMenu { ImageMenu(entry: item.entry, index: item.index) }
                    .help(item.entry.prompt)
            }
        }
        .fixedSize()
        .padding(.trailing, 8)
    }
}

/// The tour's picture-panel background: neutral base, soft accent glow, dotted grid.
struct OverviewArtBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.card
            RadialGradient(colors: [Theme.accent.opacity(scheme == .dark ? 0.24 : 0.13), .clear],
                           center: .init(x: 0.85, y: 0), startRadius: 0, endRadius: 420)
            Canvas { ctx, size in
                let gap: CGFloat = 18
                var y: CGFloat = gap / 2
                while y < size.height {
                    var x: CGFloat = gap / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                                 with: .color(.primary.opacity(0.08)))
                        x += gap
                    }
                    y += gap
                }
            }
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
    var delta: Double?
    var span = ""
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, color: color, size: 28)
                Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let delta { OverviewDelta(value: delta).help("vs. the \(span) before") }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .shadow(color: .black.opacity(hovering ? 0.06 : 0), radius: 10, y: 4)
        .offset(y: hovering ? -1 : 0)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// "↑ 12%" change against the previous range, in calm neutral tones.
private struct OverviewDelta: View {
    let value: Double

    var body: some View {
        let pct = Int((abs(value) * 100).rounded())
        HStack(spacing: 2) {
            if pct > 0 {
                Image(systemName: value > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(pct > 999 ? ">999%" : "\(pct)%")
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .fixedSize()
    }
}

/// One chart card for images or spend, switched with a segmented control.
private struct OverviewActivityCard: View {
    enum Metric: String, CaseIterable, Identifiable {
        case images = "Images", cost = "Spend"
        var id: String { rawValue }
    }
    let stats: Stats
    @AppStorage("overviewChartMetric") private var metric: Metric = .images

    var body: some View {
        let ids = metric == .cost
            ? stats.providers.filter { id in stats.buckets.contains { $0.provider == id && $0.cost > 0 } }
            : stats.providers
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                OverviewCardTitle(title: "Activity", symbol: "chart.bar")
                Spacer(minLength: 8)
                if ids.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(ids, id: \.self) { id in
                            HStack(spacing: 5) {
                                Circle().fill(ProviderStyle.color(id)).frame(width: 7, height: 7)
                                Text(ProviderStyle.label(id))
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Picker("Metric", selection: $metric.animation(.smooth(duration: 0.3))) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if metric == .cost && stats.cost == 0 {
                OverviewNote(text: "No paid runs in this range", height: 200)
            } else {
                OverviewChart(stats: stats, metric: metric == .cost ? .cost : .images, ids: ids)
                    .id(metric)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }
}

private struct OverviewCardTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(title).font(.system(size: 15, weight: .semibold))
        }
    }
}

/// Card with a title; `columns` adds the "Images · Spend" captions for breakdown lists.
private struct OverviewSection<Content: View>: View {
    let title: String
    var symbol = "circle"
    var columns = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                OverviewCardTitle(title: title, symbol: symbol)
                Spacer()
                if columns {
                    HStack(spacing: 0) {
                        Text("Images").frame(width: OverviewBreakdown.imagesWidth, alignment: .trailing)
                        Text("Spend").frame(width: OverviewBreakdown.spendWidth, alignment: .trailing)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }
}

private struct OverviewNote: View {
    let text: String
    var height: CGFloat = 60

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: height)
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
    let ids: [String]
    @State private var hovered: Date?

    var body: some View {
        let data = metric == .cost ? stats.buckets.filter { $0.cost > 0 } : stats.buckets
        Chart {
            ForEach(data) { b in
                BarMark(x: .value("Date", b.start, unit: stats.unit),
                        y: .value(metric == .cost ? "Spend" : "Images", metric == .cost ? b.cost : Double(b.images)))
                    .foregroundStyle(by: .value("Provider", ProviderStyle.label(b.provider)))
                    .cornerRadius(4)
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
        .chartLegend(.hidden)
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
                            if let date: Date = proxy.value(atX: x), stats.domain.contains(date),
                               !stats.buckets(at: stats.bucketStart(date)).isEmpty {
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
        .frame(height: 200)
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
                .buttonStyle(.link)
                .font(.callout)
                .foregroundStyle(Theme.accent)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Motion (same feel as the welcome tour)

private struct OverviewEnterModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .onAppear {
                withAnimation(.smooth(duration: 0.5).delay(0.04 + Double(index) * 0.06)) { shown = true }
            }
    }
}

private struct OverviewFloatModifier: ViewModifier {
    var amount: CGFloat
    var duration: Double
    var tilt: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.rotationEffect(.degrees(tilt))
        } else {
            content.phaseAnimator([false, true]) { view, up in
                view.offset(y: up ? -amount : amount)
                    .rotationEffect(.degrees(tilt + (up ? 0.8 : -0.8)))
            } animation: { _ in .easeInOut(duration: duration) }
        }
    }
}

private struct OverviewPopModifier: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .scaleEffect(visible ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.68).delay(delay)) { shown = true } }
    }
}

extension View {
    fileprivate func overviewEnter(_ index: Int) -> some View { modifier(OverviewEnterModifier(index: index)) }
    fileprivate func overviewFloat(_ amount: CGFloat = 4, duration: Double = 3, tilt: Double = 0) -> some View {
        modifier(OverviewFloatModifier(amount: amount, duration: duration, tilt: tilt))
    }
    fileprivate func overviewPop(_ delay: Double = 0) -> some View { modifier(OverviewPopModifier(delay: delay)) }
}
