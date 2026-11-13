import Foundation

/// Public discovery metadata only. Never stores authenticated account pages or Live data.
actor CompetitionSummaryCache {
    static let shared = CompetitionSummaryCache()
    private struct Entry: Codable { let summary: CompetitionSummary; let savedAt: Date }
    private var entries: [String: Entry] = [:]
    private var loaded = false
    private let url: URL
    private let now: @Sendable () -> Date

    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        let root = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CubeFlow", isDirectory: true)
        url = root.appendingPathComponent("competition-summary-cache-v1.json")
        self.now = now
    }

    func summary(_ id: String) -> CompetitionSummary? {
        load()
        guard let entry = entries[id], (-60...CompetitionCachePolicy.retention).contains(now().timeIntervalSince(entry.savedAt)) else { return nil }
        return entry.summary
    }

    func store(_ summary: CompetitionSummary) {
        load()
        guard !Task.isCancelled else { return }
        entries[summary.id] = Entry(summary: summary, savedAt: now())
        entries = entries.filter { (-60...CompetitionCachePolicy.retention).contains(now().timeIntervalSince($0.value.savedAt)) }
        while entries.count > 128, let oldest = entries.min(by: { $0.value.savedAt < $1.value.savedAt }) { entries[oldest.key] = nil }
        guard let data = try? JSONEncoder().encode(entries), data.count <= CompetitionCachePolicy.maximumJSONBytes else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= CompetitionCachePolicy.maximumJSONBytes,
              let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    func clear() { entries = [:]; loaded = true; try? FileManager.default.removeItem(at: url) }
}

nonisolated struct CompetitionNameReference: Sendable {
    let id: String
    let name: String
    let website: String?
    var archiveYear: Int? = nil
}
