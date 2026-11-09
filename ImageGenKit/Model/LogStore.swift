import Foundation
import Observation

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "7 days"
    case month = "30 days"
    case quarter = "90 days"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }

    var start: Date? {
        guard let days else { return nil }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: .now))
    }
}

struct GalleryItem: Identifiable, Hashable {
    let entry: LogEntry
    let index: Int
    var id: String { "\(entry.id)-\(index)" }
    var ref: ImageRef { entry.imageRef(index) }
}

/// Reads ~/.config/imagegen/log.jsonl and follows it as new runs are appended.
@Observable
final class LogStore {
    private(set) var entries: [LogEntry] = []  // oldest first
    private(set) var lastUpdate: Date?
    private(set) var logMissing = false
    private(set) var archiveDone = 0
    private(set) var archiveTotal = 0

    var range: TimeRange = .month
    var providerFilter: String?
    var searchText = ""
    var hideDeleted = true
    private(set) var missing: Set<String> = []  // gallery item ids with no file and no preview left
    var selectedID: LogEntry.ID? {
        didSet { if oldValue != selectedID { selectedImageIndex = 0 } }
    }
    var selectedImageIndex = 0

    @ObservationIgnored private var offset: UInt64 = 0
    @ObservationIgnored private var tail = Data()
    @ObservationIgnored private var nextLine = 0
    @ObservationIgnored private let parser = LogParser()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var archiveTask: Task<Void, Never>?
    @ObservationIgnored private let logURL: URL

    init(logURL: URL = Paths.log) {
        self.logURL = logURL
    }

    func start() {
        guard pollTask == nil else { return }
        poll()
        archiveMissingPreviews(entries)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.poll()
            }
        }
    }

    // MARK: Reading

    func reloadAll() {
        offset = 0
        tail = Data()
        nextLine = 0
        entries = []
        poll()
    }

    /// Reads whatever was appended since the last call.
    func poll() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? NSNumber else {
            logMissing = true
            return
        }
        logMissing = false
        let fileSize = size.uint64Value
        if fileSize < offset {  // log was replaced or truncated
            offset = 0
            tail = Data()
            nextLine = 0
            entries = []
        }
        guard fileSize > offset, let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)

        var buffer = tail + data
        guard let lastNewline = buffer.lastIndex(of: 0x0A) else {  // no complete line yet
            tail = buffer
            return
        }
        tail = Data(buffer[buffer.index(after: lastNewline)...])
        buffer = Data(buffer[..<lastNewline])

        var added: [LogEntry] = []
        for line in String(decoding: buffer, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if let entry = parser.parse(line: line, id: nextLine) { added.append(entry) }
            nextLine += 1
        }
        guard !added.isEmpty else { return }
        entries.append(contentsOf: added)
        lastUpdate = .now
        if pollTask != nil { archiveMissingPreviews(added) }
    }

    /// Creates 512 px previews for images that still exist but have none yet (older runs, before the
    /// CLI made its own). Runs in the background, one image at a time.
    private func archiveMissingPreviews(_ batch: [LogEntry]) {
        let refs = batch.flatMap { e in e.outputs.indices.map { ("\(e.id)-\($0)", e.imageRef($0)) } }
        guard !refs.isEmpty else { return }
        let previous = archiveTask
        archiveTotal += refs.count
        archiveTask = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            var done = 0
            var gone: [String] = []
            for (id, ref) in refs {
                if !Thumbnails.ensureArchived(ref) { gone.append(id) }
                done += 1
                if done % 20 == 0 || done == refs.count {
                    let step = done % 20 == 0 ? 20 : done % 20, batch = gone
                    gone = []
                    await MainActor.run {
                        self?.archiveDone += step
                        self?.missing.formUnion(batch)
                    }
                }
            }
        }
    }

    // MARK: Views

    var selected: LogEntry? {
        guard let selectedID else { return nil }
        return entries.last { $0.id == selectedID }
    }

    /// Entries in the chosen time range, oldest first.
    var inRange: [LogEntry] {
        guard let start = range.start else { return entries }
        return entries.filter { $0.date >= start }
    }

    /// In range, matching the provider filter and search, newest first.
    var filtered: [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return inRange.reversed().filter { e in
            if let providerFilter, e.provider != providerFilter { return false }
            guard !query.isEmpty else { return true }
            return e.prompt.localizedCaseInsensitiveContains(query)
                || e.project.localizedCaseInsensitiveContains(query)
                || e.model.localizedCaseInsensitiveContains(query)
                || e.outputs.contains { ($0 as NSString).lastPathComponent.localizedCaseInsensitiveContains(query) }
        }
    }

    var galleryItems: [GalleryItem] {
        filtered.flatMap { e in
            e.outputs.indices.map { GalleryItem(entry: e, index: $0) }.filter { !hideDeleted || !missing.contains($0.id) }
        }
    }

    /// Provider ids that appear in the log, for filters.
    var loggedProviders: [String] {
        var seen: [String] = []
        for e in entries where !seen.contains(e.provider) { seen.append(e.provider) }
        return seen.sorted()
    }

    func select(_ item: GalleryItem) {
        selectedID = item.entry.id
        selectedImageIndex = item.index
    }
}
