import Foundation
import CryptoKit

/// Storage only. Profile/Explore owners still decide request identity and freshness.
actor PublicDataSnapshotStore {
    nonisolated struct Entry: Sendable {
        let body: Data
        let fetchedAt: Date
    }
    private struct Envelope: Codable {
        let version: Int
        let key: String
        let body: Data
        let fetchedAt: Date
    }
    let directory: URL
    private let countLimit: Int
    private let diskLimit: Int
    private let entryLimit: Int
    private let memoryLimit: Int
    private let retention: TimeInterval
    private let now: @Sendable () -> Date
    private var memory: [String: Entry] = [:]
    private var order: [String] = []
    private var memoryBytes = 0

    init(directory: URL, countLimit: Int, diskLimit: Int, entryLimit: Int = 8 * 1024 * 1024,
         memoryLimit: Int = 8 * 1024 * 1024, retention: TimeInterval,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory; self.countLimit = countLimit; self.diskLimit = diskLimit
        self.entryLimit = entryLimit; self.memoryLimit = memoryLimit; self.retention = retention; self.now = now
    }

    nonisolated static func key(_ components: [String]) -> String {
        // Length-delimited JSON components, not a lossy punctuation substitution.
        String(decoding: (try? JSONEncoder().encode(components)) ?? Data(), as: UTF8.self)
    }

    func load(_ key: String) -> Entry? {
        if let entry = memory[key] {
            guard usable(entry.fetchedAt) else { remove(key); return nil }
            touch(key); return entry
        }
        let file = url(key)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        guard size <= entryLimit, let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(Envelope.self, from: data), value.version == 2,
              value.key == key, usable(value.fetchedAt) else {
            try? FileManager.default.removeItem(at: file); return nil
        }
        let entry = Entry(body: value.body, fetchedAt: value.fetchedAt)
        remember(entry, key: key); return entry
    }

    @discardableResult
    func save(_ body: Data, key: String, fetchedAt: Date) -> Bool {
        guard !Task.isCancelled, usable(fetchedAt), body.count <= entryLimit else { return false }
        if let newer = load(key), newer.fetchedAt > fetchedAt { return true }
        guard let data = try? JSONEncoder().encode(Envelope(version: 2, key: key, body: body, fetchedAt: fetchedAt)),
              data.count <= entryLimit, data.count <= diskLimit else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(key), options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: fetchedAt], ofItemAtPath: url(key).path)
            remember(Entry(body: body, fetchedAt: fetchedAt), key: key)
            evictDisk()
            return true
        } catch { return false }
    }

    func remove(_ key: String) {
        if let previous = memory.removeValue(forKey: key) { memoryBytes -= previous.body.count }
        order.removeAll { $0 == key }
        try? FileManager.default.removeItem(at: url(key))
    }
    func clear() {
        memory = [:]; order = []; memoryBytes = 0
        for file in files() { try? FileManager.default.removeItem(at: file) }
    }
    func maintain() { evictDisk() }

    nonisolated static func diskBytes(at directory: URL) -> Int64 {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    private func usable(_ date: Date) -> Bool {
        let age = now().timeIntervalSince(date)
        return age >= -60 && age <= retention
    }
    private func url(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("v2-" + digest + ".json")
    }
    private func touch(_ key: String) { order.removeAll { $0 == key }; order.append(key) }
    private func remember(_ entry: Entry, key: String) {
        guard entry.body.count <= memoryLimit else { return }
        if let old = memory.updateValue(entry, forKey: key) { memoryBytes -= old.body.count }
        memoryBytes += entry.body.count; touch(key)
        while memoryBytes > memoryLimit || order.count > countLimit {
            let first = order.removeFirst()
            if let old = memory.removeValue(forKey: first) { memoryBytes -= old.body.count }
        }
    }
    private func files() -> [URL] {
        // These directories exclusively contain this owner's downloadable JSON snapshots,
        // including its legacy format. Non-JSON files (e.g. migration markers) are not data.
        ((try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []).filter { $0.pathExtension == "json" }
    }
    private func evictDisk() {
        let values = files().compactMap { file -> (URL, Int, Date)? in
            guard let fields = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = fields.fileSize, let date = fields.contentModificationDate else { return nil }
            return (file, size, date)
        }.sorted { $0.2 == $1.2 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.2 > $1.2 }
        var bytes = 0, kept = 0
        for (file, size, date) in values {
            guard usable(date), kept < countLimit, bytes + size <= diskLimit else {
                try? FileManager.default.removeItem(at: file); continue
            }
            kept += 1; bytes += size
        }
    }
}
