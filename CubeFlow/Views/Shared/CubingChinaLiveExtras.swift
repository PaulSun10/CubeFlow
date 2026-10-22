import Foundation
import Combine

nonisolated struct CubingChinaLiveData<Value: Decodable>: Decodable { let data: Value }

nonisolated struct CubingChinaPhotoStream: Hashable, Codable, Sendable {
    let title: String
    let url: URL
    static func verified(_ value: Any?) -> [Self] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty,
                  let raw = item["url"] as? String, let url = URL(string: raw),
                  url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
            return Self(title: title, url: url)
        }
    }
}

nonisolated struct CubingChinaLivePodium: Decodable, Hashable, Sendable {
    let eventId: String
    let roundNumber: Int
    let results: [CubingChinaLiveResult]
    let group: Group?
    let groupIndex: Int?
    struct Group: Decodable, Hashable, Sendable {
        let type: String
        let age: Int?
        let under: Bool?
    }
    var key: CubingChinaLiveRoundKey { .init(eventID: eventId, number: roundNumber) }
    var supportedGroup: Bool {
        guard let group else { return true }
        // Index zero is the observed open category; do not invent semantics for other filters.
        guard groupIndex == 0 else { return false }
        return ["female", "newcomer"].contains(group.type)
            || (group.type == "age" && group.under != nil && (group.age ?? 0) > 0)
    }
}

nonisolated struct CubingChinaLiveSumRank: Decodable, Hashable, Sendable, Identifiable {
    let competitor: CubingChinaLiveResult.Competitor
    let sum: Int
    let count: Int
    let ranks: [String: Int]
    let enteredEventIds: [String]
    let gender: String?
    var id: CubingChinaLiveID<CubingChinaIDKind.User> { competitor.id }
    func isValid(events: Set<String>) -> Bool {
        sum >= 0 && count >= 0 && count <= events.count && !competitor.name.isEmpty
            && Set(enteredEventIds).count == enteredEventIds.count
            && enteredEventIds.allSatisfy(events.contains)
            && ranks.allSatisfy { events.contains($0.key) && $0.value >= 0 }
    }
}

nonisolated protocol CubingChinaLiveExtrasTransport: Sendable {
    func podiums(slug: String) async throws -> [CubingChinaLivePodium]
    func records(slug: String) async throws -> [CubingChinaLiveResult]
    func sumOfRanks(slug: String) async throws -> [CubingChinaLiveSumRank]
}

/// Competition-scoped server aggregates, not a scan of individual round snapshots.
@MainActor final class CubingChinaLiveExtrasStore: ObservableObject {
    @Published private(set) var podiums: [CubingChinaLivePodium] = []
    @Published private(set) var records: [CubingChinaLiveResult] = []
    @Published private(set) var sums: [CubingChinaLiveSumRank] = []
    @Published private(set) var isLoading = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var pendingRefresh: CubingChinaLiveBootstrap?
    private var refreshSequence = 0
    private var recordRounds: [CubingChinaLiveRound] = []
    private var podiumRounds: [CubingChinaLiveRound] = []
    private var slug: String?

    func refresh(_ bootstrap: CubingChinaLiveBootstrap, transport: any CubingChinaLiveExtrasTransport) {
        if slug != bootstrap.slug {
            stop(); slug = bootstrap.slug; recordRounds = []; podiumRounds = []
            podiums = []; records = []; sums = []
        }
        refreshSequence += 1
        if task != nil { pendingRefresh = bootstrap; return }
        generation += 1
        let token = generation
        let requestSequence = refreshSequence
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == token {
                    isLoading = false; task = nil
                    if let pendingRefresh {
                        self.pendingRefresh = nil; refresh(pendingRefresh, transport: transport)
                    }
                }
            }
            async let fetchedPodiums = try? transport.podiums(slug: bootstrap.slug)
            async let fetchedSums = try? transport.sumOfRanks(slug: bootstrap.slug)
            let r = try? await transport.records(slug: bootstrap.slug)
            guard !Task.isCancelled, generation == token else { return }
            // Do not wait for podium/statistics requests before publishing records.
            // A newer refresh can supersede this response even at the same revision.
            if refreshSequence == requestSequence, let r, Self.acceptsRecords(r, rounds: bootstrap.rounds) {
                recordRounds = bootstrap.rounds
                let validated = Self.validatedRecords(r, rounds: bootstrap.rounds)
                if records != validated { records = validated }
            }
            let (p, s) = await (fetchedPodiums, fetchedSums)
            guard !Task.isCancelled, generation == token, refreshSequence == requestSequence else { return }
            podiumRounds = bootstrap.rounds
            let validPodiums = Self.validatedPodiums(p ?? [], rounds: bootstrap.rounds)
            if podiums != validPodiums { podiums = validPodiums }
            let events = Set(bootstrap.rounds.map(\.eventId))
            let validSums: [CubingChinaLiveSumRank] = s.flatMap { values in
                guard values.count <= 20_000, Set(values.map(\.id)).count == values.count,
                      values.allSatisfy({ $0.isValid(events: events) }) else { return nil }
                return values
            } ?? []
            if sums != validSums { sums = validSums }
        }
    }
    /// Only server-authored flags whose round identity/metadata still matches.
    /// Podiums may additionally supply explicit PRs, but are never a full roster.
    func roundRecordTags(for rounds: [CubingChinaLiveRound]) -> [String: String] {
        var tags: [String: String] = [:]
        let recordEvidence = Set(recordRounds), podiumEvidence = Set(podiumRounds)
        let recordsByRound = Dictionary(grouping: records) { CubingChinaLiveRoundKey(eventID: $0.eventId, number: $0.roundNumber) }
        let podiumsByRound = Dictionary(grouping: podiums, by: \.key)
        for round in rounds {
            let hasRecords = recordEvidence.contains(round)
            let regional = hasRecords ? recordsByRound[round.key] ?? [] : []
            let podium = podiumEvidence.contains(round) ? podiumsByRound[round.key]?.flatMap(\.results) ?? [] : []
            let podiumTags = podium.flatMap { value in
                // A complete regional summary can retract a flag before podiums refresh.
                hasRecords ? [CubingLiveRecordIndicators.display(regional: nil, personal: value.personalSingleRecord),
                              CubingLiveRecordIndicators.display(regional: nil, personal: value.personalAverageRecord)]
                    : [value.singleIndicator, value.averageIndicator]
            }
            tags[round.key.selectionID] = CubingLiveRecordIndicators.highestDisplay(
                regional.flatMap { [$0.singleIndicator, $0.averageIndicator] } + podiumTags)
        }
        return tags
    }
    static func validatedRecords(_ values: [CubingChinaLiveResult], rounds: [CubingChinaLiveRound]) -> [CubingChinaLiveResult] {
        guard acceptsRecords(values, rounds: rounds) else { return [] }
        return values.filter { $0.singleBadge != nil || $0.averageBadge != nil }
    }
    private static func acceptsRecords(_ values: [CubingChinaLiveResult], rounds: [CubingChinaLiveRound]) -> Bool {
        values.count <= 20_000 && Set(values.map(\.id)).count == values.count
            && values.allSatisfy { value in rounds.contains(where: { value.belongs(to: $0) }) }
    }
    func hasRecordEvidence(for round: CubingChinaLiveRound) -> Bool { recordRounds.contains(round) }
    static func validatedPodiums(_ values: [CubingChinaLivePodium], rounds: [CubingChinaLiveRound]) -> [CubingChinaLivePodium] {
        guard values.count <= 1_000 else { return [] }
        return values.filter { value in
            value.supportedGroup && !value.results.isEmpty && rounds.contains { round in
                round.key == value.key && value.results.count <= 100
                    && Set(value.results.map(\.id)).count == value.results.count
                    && value.results.allSatisfy { $0.belongs(to: round) }
            }
        }
    }
    func stop() { generation += 1; task?.cancel(); task = nil; isLoading = false; pendingRefresh = nil }
}

nonisolated enum CubingChinaLiveHeaderMetadata {
    static func counts(_ snapshot: CubingChinaLiveSnapshot) -> (recorded: Int, expected: Int)? {
        let groups = Dictionary(grouping: snapshot.results, by: \.registrationId)
        guard !groups.isEmpty else { return nil }
        return (groups.values.filter { $0.contains { $0.attempts.contains { $0 != 0 } } }.count, groups.count)
    }
    static func updatedAt(_ snapshot: CubingChinaLiveSnapshot, now: Date) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return snapshot.results.compactMap { value -> Date? in
            guard let text = value.updatedByOperatorAt else { return nil }
            let date = formatter.date(from: text) ?? plain.date(from: text)
            return date.flatMap { $0 <= now ? $0 : nil }
        }.max()
    }
    static func freshViewers(_ count: Int, observedAt: Date?, now: Date) -> Int? {
        guard let observedAt, count >= 0, now >= observedAt, now.timeIntervalSince(observedAt) <= 45 else { return nil }
        return count
    }
    static func viewerObservation(occurredAt: String?, now: Date) -> Date? {
        // Buffered SSE telemetry must not become fresh merely because it was received late.
        guard let occurredAt else { return now }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: occurredAt) ?? ISO8601DateFormatter().date(from: occurredAt)
    }
}
