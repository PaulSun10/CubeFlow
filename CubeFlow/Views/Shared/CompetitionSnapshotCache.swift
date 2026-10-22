import Foundation
import CryptoKit

nonisolated struct CompetitionSnapshotKey: Codable, Hashable, Sendable {
    let provider: String
    let competition: String
    let resource: String
    let schema: Int
}

nonisolated struct CompetitionSnapshotEntry: Codable, Sendable {
    let body: Data
    let validatedAt: Date
    let etag: String?
    let lastModified: String?
}

/// Public, non-authenticated snapshots only. Live/provisional state never enters this store.
/// All file access/serialization is actor-isolated, outside the main actor.
actor CompetitionSnapshotCache {
    static let shared = CompetitionSnapshotCache()
    nonisolated static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CubeFlow/competition-public-v1", isDirectory: true)
    nonisolated static let retention: TimeInterval = 30 * 24 * 3600
    private struct Stored: Codable {
        let version: Int
        let key: CompetitionSnapshotKey
        let entry: CompetitionSnapshotEntry
    }
    private let directory: URL
    private let memoryLimit: Int
    private let diskLimit: Int
    private let entryLimit: Int
    private let countLimit: Int
    private let now: @Sendable () -> Date
    private var entries: [CompetitionSnapshotKey: CompetitionSnapshotEntry] = [:]
    private var order: [CompetitionSnapshotKey] = []
    private var memoryBytes = 0

    init(directory: URL = CompetitionSnapshotCache.directory, memoryLimit: Int = 16 * 1024 * 1024,
         diskLimit: Int = 96 * 1024 * 1024, entryLimit: Int = 16 * 1024 * 1024,
         countLimit: Int = 64, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory; self.memoryLimit = memoryLimit; self.diskLimit = diskLimit
        self.entryLimit = entryLimit; self.countLimit = countLimit; self.now = now
    }

    func entry(for key: CompetitionSnapshotKey) -> CompetitionSnapshotEntry? {
        if let entry = entries[key] {
            guard usable(entry) else { remove(key); return nil }
            touch(key); return entry
        }
        let url = url(for: key)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        guard size <= entryLimit,
              let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == 1, stored.key == key, usable(stored.entry) else {
            try? FileManager.default.removeItem(at: url); return nil
        }
        remember(stored.entry, for: key)
        return stored.entry
    }

    func store(_ entry: CompetitionSnapshotEntry, for key: CompetitionSnapshotKey) {
        guard !Task.isCancelled, usable(entry), entry.body.count <= entryLimit,
              let data = try? JSONEncoder().encode(Stored(version: 1, key: key, entry: entry)),
              data.count <= entryLimit, data.count <= diskLimit else { return }
        remember(entry, for: key)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: key), options: .atomic)
            evictDisk()
        } catch { /* Cache write failure must not fail a successful response. */ }
    }

    func remove(_ key: CompetitionSnapshotKey) {
        if let previous = entries.removeValue(forKey: key) { memoryBytes -= previous.body.count }
        order.removeAll { $0 == key }
        try? FileManager.default.removeItem(at: url(for: key))
    }

    func clear() {
        entries = [:]; order = []; memoryBytes = 0
        for file in files() { try? FileManager.default.removeItem(at: file) }
    }

    private func usable(_ entry: CompetitionSnapshotEntry) -> Bool {
        let age = now().timeIntervalSince(entry.validatedAt)
        return age >= -60 && age <= Self.retention
    }
    private func url(for key: CompetitionSnapshotKey) -> URL {
        // JSON's sorted keys make the identity hash stable across launches.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = (try? encoder.encode(key)) ?? Data()
        let name = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
    private func touch(_ key: CompetitionSnapshotKey) {
        order.removeAll { $0 == key }; order.append(key)
    }
    private func remember(_ entry: CompetitionSnapshotEntry, for key: CompetitionSnapshotKey) {
        guard entry.body.count <= memoryLimit else { return }
        if let previous = entries.updateValue(entry, forKey: key) { memoryBytes -= previous.body.count }
        memoryBytes += entry.body.count; touch(key)
        while memoryBytes > memoryLimit || order.count > countLimit {
            let oldest = order.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) { memoryBytes -= removed.body.count }
        }
    }
    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []).filter {
            $0.lastPathComponent.range(of: "^[a-f0-9]{64}\\.json$", options: .regularExpression) != nil
        }
    }
    private func evictDisk() {
        let values = files().compactMap { file -> (URL, Int, Date)? in
            guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attributes.fileSize, let date = attributes.contentModificationDate else { return nil }
            return (file, size, date)
        }.sorted { $0.2 > $1.2 }
        var bytes = 0
        for (index, item) in values.enumerated() {
            bytes += item.1
            if index >= countLimit || bytes > diskLimit || now().timeIntervalSince(item.2) > Self.retention {
                try? FileManager.default.removeItem(at: item.0)
            }
        }
    }
}
