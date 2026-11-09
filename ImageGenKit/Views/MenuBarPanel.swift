import AppKit
import SwiftUI

/// The menu bar panel: this month's spend and limits, providers, the last 7 days, recent images and quick actions.
struct MenuBarPanel: View {
    @Environment(LogStore.self) private var store
    @Environment(ConfigStore.self) private var config
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    static let width: CGFloat = 332

    var body: some View {
        let usage = MonthUsage(entries: store.entries, cost: config.cost)
        let limits = MenuBarLimits.current(config)
        VStack(spacing: 10) {
            MenuBarMonthCard(usage: usage, limits: limits)
            if !usage.providers.isEmpty {
                MenuBarProvidersCard(usage: usage)
            }
            if usage.last7.contains(where: { $0.images > 0 }) {
                MenuBarWeekCard(days: usage.last7)
            }
            if !usage.recent.isEmpty {
                MenuBarRecentStrip(entries: usage.recent)
            }
            actions
                .padding(.top, 4)
        }
        .padding(12)
        .frame(width: Self.width)
        .background(Theme.background)
        .task { store.start() }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                dismiss()
                MenuBarDock.generate(openWindow)
            } label: {
                Label("Generate…", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n")

            HStack(spacing: 8) {
                Button {
                    dismiss()
                    MenuBarDock.openMain(openWindow)
                } label: {
                    Text("Open ImageGenKit").frame(maxWidth: .infinity)
                }
                .keyboardShortcut("o")

                Button {
                    dismiss()
                    MenuBarDock.settings(openWindow)
                } label: {
                    Image(systemName: "gearshape")
                }
                .keyboardShortcut(",")
                .help("Settings")

                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .keyboardShortcut("q")
                .help("Quit ImageGenKit")
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - This month

private struct MenuBarMonthCard: View {
    let usage: MonthUsage
    let limits: UsageLimits

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Format.usd(usage.cost))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(usage.runs == 0 ? "No images yet"
                     : "\(usage.images) \(usage.images == 1 ? "image" : "images") · \(usage.runs) \(usage.runs == 1 ? "run" : "runs")")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let limit = limits.monthlyCost, let f = limits.costFraction(usage) {
                MenuBarLimitBar(text: "\(Format.usd(usage.cost)) of \(Format.axisUSD(limit))", title: "Spend", fraction: f)
            }
            if let limit = limits.monthlyImages, let f = limits.imageFraction(usage) {
                MenuBarLimitBar(text: "\(usage.images) of \(limit)", title: "Images", fraction: f)
            }
            if limits.stopPaid && limits.level(usage) == .reached {
                Label("Paid images paused until \(nextMonth)", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private var nextMonth: String {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: usage.start) ?? usage.start
        return next.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct MenuBarLimitBar: View {
    let text: String
    let title: String
    let fraction: Double

    private var color: Color { fraction >= 1 ? .red : fraction >= 0.8 ? .orange : Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(fraction >= 0.8 ? color : .primary)
            }
            .font(.caption)
            MenuBarBar(fraction: fraction, color: color, height: 6)
        }
    }
}

/// A thin rounded progress bar on the neutral well color.
private struct MenuBarBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well)
                Capsule().fill(color)
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.35), value: fraction)
    }
}

// MARK: - Providers

private struct MenuBarProvidersCard: View {
    let usage: MonthUsage

    var body: some View {
        let top = max(usage.providers.map(\.images).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 11) {
            ForEach(usage.providers.prefix(5)) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(ProviderStyle.color(row.id)).frame(width: 7, height: 7)
                        Text(ProviderStyle.label(row.id)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(row.images)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(row.subscription ? "Plan" : Format.usd(row.cost))
                            .monospacedDigit()
                            .foregroundStyle(row.subscription ? .secondary : .primary)
                            .frame(minWidth: 52, alignment: .trailing)
                    }
                    .font(.callout)
                    MenuBarBar(fraction: Double(row.images) / Double(top), color: ProviderStyle.color(row.id), height: 3)
                }
                .help("\(ProviderStyle.label(row.id)): \(row.images) images")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

// MARK: - Last 7 days

private struct MenuBarWeekCard: View {
    let days: [MonthUsage.Day]
    @State private var hovered: Date?

    var body: some View {
        let top = max(days.map(\.images).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 7 days").foregroundStyle(.secondary)
                Spacer()
                Text(caption)
                    .monospacedDigit()
                    .foregroundStyle(hovered == nil ? .secondary : .primary)
                    .contentTransition(.numericText())
            }
            .font(.caption)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    let active = hovered == nil ? isToday : hovered == day.date
                    VStack(spacing: 5) {
                        VStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(day.images == 0 ? AnyShapeStyle(Theme.well) : AnyShapeStyle(Theme.accent.opacity(active ? 0.9 : 0.3)))
                                .frame(width: 14, height: day.images == 0 ? 4 : max(6, 46 * CGFloat(day.images) / CGFloat(top)))
                        }
                        .frame(height: 46)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.15)) {
                            if inside { hovered = day.date } else if hovered == day.date { hovered = nil }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private var caption: String {
        if let hovered, let day = days.first(where: { $0.date == hovered }) {
            let name = Calendar.current.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated))
            return "\(name) · \(day.images) · \(Format.usd(day.cost))"
        }
        let images = days.map(\.images).reduce(0, +)
        return "\(images) images · \(Format.usd(days.map(\.cost).reduce(0, +)))"
    }
}

// MARK: - Recent images

private struct MenuBarRecentStrip: View {
    let entries: [LogEntry]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(entries.prefix(5)) { entry in
                MenuBarThumb(entry: entry)
            }
        }
    }
}

private struct MenuBarThumb: View {
    let entry: LogEntry
    @State private var hover = false

    var body: some View {
        ThumbnailView(ref: entry.imageRef(0))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(hover ? 0.25 : 0.08)))
            .scaleEffect(hover ? 1.04 : 1)
            .shadow(color: .black.opacity(hover ? 0.12 : 0), radius: 4, y: 2)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
            .onTapGesture { Actions.open(entry.imageRef(0)) }
            .help(entry.prompt)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(entry.prompt)
    }
}
