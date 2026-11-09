import SwiftUI

// MARK: - Model glue

/// Reads and writes the monthly limits. In DEBUG, `-debugLimitCost 4 -debugLimitImages 150 [-debugStopPaid YES]`
/// fakes limits in memory (screenshots) so the real config is never written.
@MainActor
enum SettingsLimitsModel {
    static func current(_ config: ConfigStore) -> UsageLimits {
        #if DEBUG
        if let fake = SettingsLimitsDebug.shared.limits { return fake }
        #endif
        return config.limits
    }

    /// Saves only when something really changed.
    static func set(_ config: ConfigStore, _ new: UsageLimits) {
        guard new != current(config) else { return }
        #if DEBUG
        if SettingsLimitsDebug.shared.limits != nil {
            SettingsLimitsDebug.shared.limits = new
            return
        }
        #endif
        config.setLimits(new)
    }

    /// "Dec 1"
    static func resetDate(_ usage: MonthUsage) -> String {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: usage.start) ?? usage.start
        return next.formatted(.dateTime.month(.abbreviated).day())
    }

    static func color(_ fraction: Double) -> Color {
        fraction >= 1 ? .red : fraction >= 0.8 ? .orange : Theme.accent
    }

    static func color(_ level: UsageLimits.Level) -> Color {
        switch level {
        case .reached: .red
        case .warning: .orange
        default: Theme.accent
        }
    }
}

#if DEBUG
@MainActor @Observable
final class SettingsLimitsDebug {
    static let shared = SettingsLimitsDebug()
    var limits: UsageLimits?

    private init() {
        let d = UserDefaults.standard
        let cost = d.object(forKey: "debugLimitCost") != nil ? d.double(forKey: "debugLimitCost") : nil
        let images = d.object(forKey: "debugLimitImages") != nil ? d.integer(forKey: "debugLimitImages") : nil
        if cost != nil || images != nil || d.bool(forKey: "debugLimitsOff") {
            limits = UsageLimits(monthlyCost: cost, monthlyImages: images, stopPaid: d.bool(forKey: "debugStopPaid"))
        }
    }
}
#endif

// MARK: - Section

struct SettingsLimitsSection: View {
    @Environment(ConfigStore.self) private var config
    @Environment(LogStore.self) private var store
    @State private var lastCost = 20.0
    @State private var lastImages = 500

    var body: some View {
        let limits = SettingsLimitsModel.current(config)
        let usage = MonthUsage(entries: store.entries, cost: config.cost)
        SettingsSection(title: "Limits", icon: "gauge.with.dots.needle.67percent", lead: "Cap what you use each month.") {
            SettingsRow(icon: "dollarsign", title: "Monthly spend", detail: "USD") {
                HStack(spacing: 10) {
                    if limits.monthlyCost != nil {
                        SettingsLimitsField(prefix: "$", value: costBinding(limits), format: .number.precision(.fractionLength(0...2)))
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    }
                    Toggle("Monthly spend", isOn: costToggle(limits)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsDivider(inset: 58)
            SettingsRow(icon: "photo", title: "Monthly images", detail: "All providers") {
                HStack(spacing: 10) {
                    if limits.monthlyImages != nil {
                        SettingsLimitsField(prefix: nil, value: imagesBinding(limits), format: .number.precision(.fractionLength(0)))
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    }
                    Toggle("Monthly images", isOn: imagesToggle(limits)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsDivider(inset: 58)
            SettingsRow(icon: "bell.badge", title: "When reached",
                        detail: limits.stopPaid ? "Subscriptions keep working." : "Get a notification.") {
                Picker("When reached", selection: stopBinding(limits)) {
                    Text("Warn Me").tag(false)
                    Text("Stop Paid Images").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .disabled(!limits.isSet)
            .opacity(limits.isSet ? 1 : 0.5)

            if limits.isSet {
                SettingsDivider()
                SettingsLimitsMeters(limits: limits, usage: usage)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: limits)
    }

    // MARK: Bindings (write only on real changes)

    private func costToggle(_ l: UsageLimits) -> Binding<Bool> {
        Binding(get: { l.monthlyCost != nil }, set: { on in
            var n = l
            if on {
                n.monthlyCost = lastCost
                LimitNotifier.requestPermission()
            } else {
                if let c = l.monthlyCost { lastCost = c }
                n.monthlyCost = nil
            }
            SettingsLimitsModel.set(config, n)
        })
    }

    private func imagesToggle(_ l: UsageLimits) -> Binding<Bool> {
        Binding(get: { l.monthlyImages != nil }, set: { on in
            var n = l
            if on {
                n.monthlyImages = lastImages
                LimitNotifier.requestPermission()
            } else {
                if let i = l.monthlyImages { lastImages = i }
                n.monthlyImages = nil
            }
            SettingsLimitsModel.set(config, n)
        })
    }

    private func costBinding(_ l: UsageLimits) -> Binding<Double> {
        Binding(get: { l.monthlyCost ?? lastCost }, set: { v in
            guard v > 0, v != l.monthlyCost else { return }
            var n = l
            n.monthlyCost = (v * 100).rounded() / 100
            SettingsLimitsModel.set(config, n)
        })
    }

    private func imagesBinding(_ l: UsageLimits) -> Binding<Double> {
        Binding(get: { Double(l.monthlyImages ?? lastImages) }, set: { v in
            let i = Int(v.rounded())
            guard i > 0, i != l.monthlyImages else { return }
            var n = l
            n.monthlyImages = i
            SettingsLimitsModel.set(config, n)
        })
    }

    private func stopBinding(_ l: UsageLimits) -> Binding<Bool> {
        Binding(get: { l.stopPaid }, set: { v in
            var n = l
            n.stopPaid = v
            SettingsLimitsModel.set(config, n)
        })
    }
}

/// Compact number field with an optional "$" prefix. Commits on Return or when focus leaves.
private struct SettingsLimitsField: View {
    let prefix: String?
    @Binding var value: Double
    let format: FloatingPointFormatStyle<Double>

    var body: some View {
        HStack(spacing: 4) {
            if let prefix { Text(prefix).foregroundStyle(.secondary) }
            TextField("Limit", value: $value, format: format)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .labelsHidden()
                .frame(width: 80)
        }
    }
}

// MARK: - Meters (Settings and Overview)

/// This month's usage against each limit, with the reset date.
struct SettingsLimitsMeters: View {
    let limits: UsageLimits
    let usage: MonthUsage
    var showsReset = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = limits.monthlyCost, let f = limits.costFraction(usage) {
                SettingsLimitsMeter(title: "Spend", value: "\(Format.usd(usage.cost)) of \(Format.usd(c))", fraction: f)
            }
            if let i = limits.monthlyImages, let f = limits.imageFraction(usage) {
                SettingsLimitsMeter(title: "Images", value: "\(usage.images.formatted()) of \(i.formatted())", fraction: f)
            }
            if showsReset {
                Text("Resets on \(SettingsLimitsModel.resetDate(usage))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct SettingsLimitsMeter: View {
    let title: String
    let value: String
    let fraction: Double

    var body: some View {
        let color = SettingsLimitsModel.color(fraction)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Text(value).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(fraction >= 0.8 ? color : .primary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            SettingsLimitsBar(fraction: fraction, color: color)
        }
    }
}

struct SettingsLimitsBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.4), value: fraction)
    }
}
