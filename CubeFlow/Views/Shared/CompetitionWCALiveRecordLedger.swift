import Foundation

/// Client observation ordering only, never a server revision or cache TTL.
nonisolated struct CompetitionWCALiveRequestContext: Hashable, Codable, Sendable {
    static let processID = UUID()
    let processID: UUID
    let startedAt: TimeInterval
    static func now() -> Self { Self(processID: processID, startedAt: ProcessInfo.processInfo.systemUptime) }
    var currentProcessTime: TimeInterval? {
        processID == Self.processID && startedAt.isFinite && startedAt >= 0
            && startedAt <= ProcessInfo.processInfo.systemUptime ? startedAt : nil
    }
}

/// Compact record evidence outlives full-row eviction, including empty retractions.
/// A person response covers only that person; it cannot date other people's flags.
@MainActor struct CompetitionWCALiveRecordLedger {
    private struct Personal {
        let records: [CompetitionWCALiveRecord]
        let time: TimeInterval
    }
    private struct Round {
        var records: [CompetitionWCALiveRecord] = []
        var time: TimeInterval = -.infinity
        var people: [String: Personal] = [:]
    }
    private var rounds: [String: Round] = [:]
    private var invalidBefore: TimeInterval = -.infinity
    var records: [CompetitionWCALiveRecord] {
        rounds.keys.sorted().flatMap { key -> [CompetitionWCALiveRecord] in
            guard let round = rounds[key] else { return [] }
            let newer = round.people.filter { $0.value.time > round.time }
            let other = round.records.filter { $0.personID.map { newer[$0] == nil } ?? true }
            return other + newer.keys.sorted().flatMap { newer[$0]?.records ?? [] }
        }
    }
    mutating func full(_ values: [CompetitionWCALiveRecord], roundID: String, observedAt: TimeInterval) {
        guard observedAt >= invalidBefore else { return }
        var round = rounds[roundID] ?? Round()
        guard observedAt >= round.time else { return }
        round.records = values; round.time = observedAt
        round.people = round.people.filter { $0.value.time > observedAt }
        rounds[roundID] = round
        enforceBounds(at: observedAt)
    }
    mutating func person(_ values: [CompetitionWCALiveRecord], personID: String, roundID: String, observedAt: TimeInterval) {
        guard observedAt >= invalidBefore else { return }
        var round = rounds[roundID] ?? Round()
        guard observedAt > round.time, observedAt >= (round.people[personID]?.time ?? -.infinity) else { return }
        round.people[personID] = Personal(records: values, time: observedAt); rounds[roundID] = round
        enforceBounds(at: observedAt)
    }
    mutating func retainRounds(_ ids: Set<String>) { rounds = rounds.filter { ids.contains($0.key) } }
    private mutating func enforceBounds(at time: TimeInterval) {
        let all = rounds.values
        guard rounds.count <= 500, all.reduce(0, { $0 + $1.people.count }) <= 2048,
              all.reduce(0, { $0 + $1.records.count + $1.people.values.reduce(0, { $0 + $1.records.count }) }) <= 20_000 else {
            // Resource eviction must never resurrect old base records. Remain unknown
            // until a newer authoritative source supplies evidence again.
            rounds = [:]; invalidBefore = time
            return
        }
    }
}
