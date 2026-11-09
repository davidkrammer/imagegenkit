import Foundation
import Observation
import UserNotifications

/// This calendar month's usage, for the menu bar and the limits.
struct MonthUsage {
    struct ProviderRow: Identifiable {
        let id: String
        var images = 0
        var cost = 0.0
        var subscription = false
    }

    struct Day: Identifiable {
        let date: Date
        var images = 0
        var cost = 0.0
        var id: Date { date }
    }

    var start: Date
    var cost = 0.0
    var images = 0
    var paidImages = 0
    var runs = 0
    var providers: [ProviderRow] = []  // most images first
    var last7: [Day] = []              // oldest first, always 7 entries
    var recent: [LogEntry] = []        // newest first, runs with images

    init(entries: [LogEntry], cost: (LogEntry) -> Double?, now: Date = .now) {
        let cal = Calendar.current
        start = cal.dateInterval(of: .month, for: now)?.start ?? now
        let today = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        var byProvider: [String: ProviderRow] = [:]
        var days: [Date: Day] = [:]
        for d in 0..<7 {
            let date = cal.date(byAdding: .day, value: d, to: weekStart) ?? weekStart
            days[date] = Day(date: date)
        }
        for e in entries {
            let c = cost(e)
            if e.date >= weekStart {
                let day = cal.startOfDay(for: e.date)
                days[day]?.images += e.imageCount
                days[day]?.cost += c ?? 0
            }
            guard e.date >= start else { continue }
            self.cost += c ?? 0
            images += e.imageCount
            if c != nil { paidImages += e.imageCount }
            runs += 1
            var row = byProvider[e.provider] ?? ProviderRow(id: e.provider)
            row.images += e.imageCount
            row.cost += c ?? 0
            row.subscription = c == nil
            byProvider[e.provider] = row
        }
        providers = byProvider.values.sorted { ($0.images, $0.cost) > ($1.images, $1.cost) }
        last7 = days.values.sorted { $0.date < $1.date }
        recent = Array(entries.reversed().filter { !$0.outputs.isEmpty }.prefix(6))
    }
}

/// Monthly limits from config.json (`limits`): spend (USD), images, and whether to stop paid images.
struct UsageLimits: Equatable {
    var monthlyCost: Double?
    var monthlyImages: Int?
    var stopPaid: Bool

    var isSet: Bool { monthlyCost != nil || monthlyImages != nil }

    enum Level: Int, Comparable {
        case none, ok, warning, reached
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// 0…1+ of each limit that is used.
    func costFraction(_ u: MonthUsage) -> Double? { monthlyCost.map { $0 > 0 ? u.cost / $0 : 0 } }
    func imageFraction(_ u: MonthUsage) -> Double? { monthlyImages.map { $0 > 0 ? Double(u.images) / Double($0) : 0 } }

    func level(_ u: MonthUsage) -> Level {
        let worst = [costFraction(u), imageFraction(u)].compactMap { $0 }.max()
        guard let worst else { return .none }
        return worst >= 1 ? .reached : worst >= 0.8 ? .warning : .ok
    }
}

extension ConfigStore {
    var limits: UsageLimits {
        let l = user["limits"] as? [String: Any] ?? [:]
        return UsageLimits(monthlyCost: (l["monthly_cost"] as? NSNumber)?.doubleValue,
                           monthlyImages: (l["monthly_images"] as? NSNumber)?.intValue,
                           stopPaid: l["stop_paid"] as? Bool ?? false)
    }

    func setLimits(_ new: UsageLimits) {
        var l: [String: Any] = [:]
        if let c = new.monthlyCost, c > 0 { l["monthly_cost"] = c }
        if let i = new.monthlyImages, i > 0 { l["monthly_images"] = i }
        if !l.isEmpty { l["stop_paid"] = new.stopPaid }
        setRaw("limits", l.isEmpty ? nil : l)
    }
}

/// Posts a notification once per month when usage crosses 80 % and 100 % of a limit.
@MainActor
enum LimitNotifier {
    private static let key = "limitNotified"  // "2026-11:warning" / "2026-11:reached"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func check(_ usage: MonthUsage, limits: UsageLimits) {
        let level = limits.level(usage)
        guard level >= .warning else { return }
        let month = usage.start.formatted(.iso8601.year().month())
        let stamp = "\(month):\(level == .reached ? "reached" : "warning")"
        let done = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !done.contains(stamp) else { return }
        UserDefaults.standard.set(done.suffix(10) + [stamp], forKey: key)

        let content = UNMutableNotificationContent()
        if level == .reached {
            content.title = "Monthly limit reached"
            content.body = limits.stopPaid ? "Paid images are paused until next month. Subscriptions still work."
                : "You're over your monthly limit."
        } else {
            content.title = "80 % of your monthly limit"
            content.body = summary(usage, limits)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: stamp, content: content, trigger: nil))
    }

    static func summary(_ u: MonthUsage, _ l: UsageLimits) -> String {
        var parts: [String] = []
        if let c = l.monthlyCost { parts.append("\(Format.usd(u.cost)) of \(Format.usd(c))") }
        if let i = l.monthlyImages { parts.append("\(u.images) of \(i) images") }
        return parts.joined(separator: " · ")
    }
}
