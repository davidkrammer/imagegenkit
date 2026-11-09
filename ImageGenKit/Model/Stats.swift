import Foundation

/// Totals and breakdowns for a set of runs.
struct Stats {
    struct Bucket: Identifiable {
        let start: Date
        let provider: String
        var runs = 0
        var images = 0
        var cost = 0.0
        var id: String { "\(start.timeIntervalSince1970)-\(provider)" }
    }

    struct Group: Identifiable {
        let id: String
        var name: String
        var runs = 0
        var images = 0
        var cost = 0.0
        var subscription = false
    }

    struct Month: Identifiable {
        let start: Date
        var runs = 0
        var images = 0
        var cost = 0.0
        var id: Date { start }
    }

    var runs = 0
    var images = 0
    var cost = 0.0
    var paidImages = 0
    var averageSeconds: Double?
    var buckets: [Bucket] = []
    var providers: [String] = []  // ids present, in fixed display order
    var unit: Calendar.Component = .day
    var domain: ClosedRange<Date>
    var byProvider: [Group] = []
    var byProject: [Group] = []
    var months: [Month] = []

    private let calendar = Calendar.current

    init(entries: [LogEntry], rangeStart: Date?, cost: (LogEntry) -> Double?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let first = rangeStart ?? entries.first.map { cal.startOfDay(for: $0.date) } ?? today
        let span = cal.dateComponents([.day], from: first, to: today).day ?? 0
        let unit: Calendar.Component = span > 100 ? .weekOfYear : .day
        let lower = cal.dateInterval(of: unit, for: first)?.start ?? first
        let upper = cal.dateInterval(of: unit, for: today)?.end ?? today.addingTimeInterval(86_400)
        self.unit = unit
        domain = lower...upper

        var bucketMap: [Date: [String: Bucket]] = [:]
        var providerMap: [String: Group] = [:]
        var projectMap: [String: Group] = [:]
        var monthMap: [Date: Month] = [:]
        var seconds: [Double] = []
        // Calendar lookups dominate a redraw with a 10k-run log, so they're cached per local day.
        // `ts` starts with the local date the date was parsed from (unparseable ones aren't cached).
        var dayStarts: [Substring: (bucket: Date, month: Date)] = [:]
        func starts(_ e: LogEntry) -> (bucket: Date, month: Date) {
            let key = e.ts.prefix(10)
            if e.date != .distantPast, let hit = dayStarts[key] { return hit }
            let value = (cal.dateInterval(of: unit, for: e.date)?.start ?? e.date,
                         cal.dateInterval(of: .month, for: e.date)?.start ?? e.date)
            if e.date != .distantPast { dayStarts[key] = value }
            return value
        }

        for e in entries {
            let (start, monthStart) = starts(e)
            let c = cost(e)
            let value = c ?? 0
            runs += 1
            images += e.imageCount
            self.cost += value
            if c != nil { paidImages += e.imageCount }
            if let s = e.seconds { seconds.append(s) }

            var b = bucketMap[start, default: [:]][e.provider] ?? Bucket(start: start, provider: e.provider)
            b.runs += 1
            b.images += e.imageCount
            b.cost += value
            bucketMap[start, default: [:]][e.provider] = b

            var p = providerMap[e.provider] ?? Group(id: e.provider, name: ProviderStyle.label(e.provider))
            p.runs += 1
            p.images += e.imageCount
            p.cost += value
            p.subscription = c == nil
            providerMap[e.provider] = p

            var g = projectMap[e.project] ?? Group(id: e.project, name: e.project)
            g.runs += 1
            g.images += e.imageCount
            g.cost += value
            projectMap[e.project] = g

            var m = monthMap[monthStart] ?? Month(start: monthStart)
            m.runs += 1
            m.images += e.imageCount
            m.cost += value
            monthMap[monthStart] = m
        }

        let fixed = ["openai", "grok", "codex", "gemini", "xai"]
        providers = providerMap.keys.sorted {
            (fixed.firstIndex(of: $0) ?? 10, $0) < (fixed.firstIndex(of: $1) ?? 10, $1)
        }
        buckets = bucketMap.keys.sorted().flatMap { day in providers.compactMap { bucketMap[day]?[$0] } }
        byProvider = providers.compactMap { providerMap[$0] }
        byProject = projectMap.values.sorted { ($0.cost, $0.images) > ($1.cost, $1.images) }
        months = monthMap.values.sorted { $0.start > $1.start }
        averageSeconds = seconds.isEmpty ? nil : seconds.reduce(0, +) / Double(seconds.count)
    }

    /// Start of the day (or week) that contains `date`.
    func bucketStart(_ date: Date) -> Date {
        calendar.dateInterval(of: unit, for: date)?.start ?? date
    }

    func buckets(at start: Date) -> [Bucket] { buckets.filter { $0.start == start } }
}

enum Format {
    static func usd(_ value: Double, precise: Bool = false) -> String {
        let digits = precise ? 3 : 2
        return value.formatted(.currency(code: "USD").precision(.fractionLength(digits)))
    }

    static func axisUSD(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(value < 10 && value != 0 && value.truncatingRemainder(dividingBy: 1) != 0 ? 2 : 0)))
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6)
            : n >= 1000 ? String(format: "%.1fk", Double(n) / 1e3) : "\(n)"
    }

    static func seconds(_ s: Double?) -> String {
        guard let s else { return "–" }
        return s < 10 ? String(format: "%.1f s", s) : "\(Int(s.rounded())) s"
    }
}
