import Foundation
import Combine

@MainActor
final class CubingChinaModernLiveSession: ObservableObject {
    @Published private(set) var rounds: [CubingChinaLiveRound]
    @Published private(set) var snapshot: CubingChinaLiveSnapshot?
    @Published private(set) var messages: [CubingChinaLiveMessage] = []
    @Published private(set) var viewers = 0
    @Published private(set) var viewersObservedAt: Date?
    @Published private(set) var isLoadingResults = false
    @Published private(set) var isLoadingMessages = false
    @Published private(set) var resultError: Error?
    @Published private(set) var chatError: Error?
    @Published private(set) var connectionError: Error?
    @Published private(set) var knownRoundBadges: [String: String] = [:]
    @Published private(set) var aggregateRefreshID = 0
    private var knownBadgeRounds: [String: CubingChinaLiveRound] = [:]
    private var knownBadgeEpochs: [String: Int] = [:]
    @Published private(set) var roundAdvancement: [String: [String: CompetitionAdvancement]] = [:]
    @Published private var nextRosters: [CubingChinaLiveRoundKey: Roster] = [:]
    private struct Roster {
        let revision: Int
        let people: Set<CubingChinaLiveID<CubingChinaIDKind.User>>
    }
    private var nextRosterTask: Task<Void, Never>?
    private(set) var selectedKey: CubingChinaLiveRoundKey
    let bootstrap: CubingChinaLiveBootstrap
    private let transport: any CubingChinaLiveTransport
    private let resultRequests = CompetitionRequestPool<CubingChinaLiveSnapshot>()
    private let pause: @Sendable (UInt64) async throws -> Void
    private let viewerID = UUID().uuidString
    private var state: CubingChinaLiveRoundState
    private var runTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var connection: CubingChinaLiveConnection?
    private var generation = 0
    private var selectionGeneration = 0
    private var needsSnapshotRefresh = false
    private struct CachedRound {
        let streamEpoch: Int
        let state: CubingChinaLiveRoundState
    }
    private var streamEpoch = 0
    private var cachedRounds: [CubingChinaLiveRoundKey: CachedRound] = [:]
    private var cachedRoundOrder: [CubingChinaLiveRoundKey] = []
    private var roundEventSequences: [CubingChinaLiveRoundKey: Int] = [:]
    private let competitorRequests = CompetitionRequestPool<[CubingChinaLiveResult]>()
    let personalRecords = CubingChinaPersonalRecords()
    private var personalObservation: AnyCancellable?
    private var personalEvidenceSequence = 0

    init(bootstrap: CubingChinaLiveBootstrap, transport: any CubingChinaLiveTransport = CubingChinaLiveHTTPClient.shared,
         pause: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.bootstrap = bootstrap; self.transport = transport; self.pause = pause
        rounds = bootstrap.rounds; selectedKey = bootstrap.defaultRound.key
        state = CubingChinaLiveRoundState(round: bootstrap.defaultRound)
        personalObservation = personalRecords.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func select(_ key: CubingChinaLiveRoundKey) {
        guard key != selectedKey, let round = rounds.first(where: { $0.key == key }) else { return }
        selectionGeneration += 1; snapshotTask?.cancel(); snapshotTask = nil
        nextRosterTask?.cancel(); nextRosterTask = nil
        needsSnapshotRefresh = false
        selectedKey = key; state = CubingChinaLiveRoundState(round: round)
        let cached = cachedRounds[key]
        let known = cached?.state.snapshot.flatMap { value in
            value.round.id == round.id && value.round.competitionId == round.competitionId
                && value.round.competitionRoundId == round.competitionRoundId ? value : nil
        }
        // Last-known presentation is separate from the new stream's authority.
        // Never merge a new delta into an unvalidated prior-stream snapshot.
        if snapshot != known { snapshot = known }
        resultError = nil
        if connection != nil, connectionError == nil, let cached = cachedRounds[key],
           cached.streamEpoch == streamEpoch, cached.state.snapshot?.round == round,
           (cached.state.snapshot?.round.revision ?? -1) >= cached.state.minimumRevision {
            state = cached.state
            if snapshot != state.snapshot { snapshot = state.snapshot }
            isLoadingResults = false
            rememberSelectedRound(); updateBadge()
            return
        }
        if runTask != nil { refreshSelectedRound() }
    }

    func start() {
        guard runTask == nil else { return }
        generation += 1
        let token = generation
        refreshSelectedRound()
        runTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<5 {
                guard !Task.isCancelled, generation == token else { return }
                var ownedConnection: CubingChinaLiveConnection?
                do {
                    let opened = try await transport.events(slug: bootstrap.slug, viewerID: viewerID)
                    guard !Task.isCancelled, generation == token else { opened.cancel(); return }
                    ownedConnection = opened
                    streamEpoch += 1
                    connection = opened; connectionError = nil
                    // The stream buffers during resync. Reconnect never assumes server replay support.
                    await refreshRounds(token: token)
                    guard !Task.isCancelled, generation == token else { opened.cancel(); return }
                    if attempt > 0 { aggregateRefreshID += 1 }
                    refreshSelectedRound()
                    await refreshChat(token: token)
                    guard !Task.isCancelled, generation == token else { opened.cancel(); return }
                    for try await frame in opened.frames {
                        try Task.checkCancellation()
                        guard generation == token else { return }
                        try await receive(frame, token: token)
                    }
                    throw CubingChinaLiveError.disconnected
                } catch {
                    // A departing generation must not cancel a newly resumed session's connection.
                    ownedConnection?.cancel()
                    guard !Task.isCancelled, generation == token else { return }
                    connection = nil
                    viewersObservedAt = nil
                    connectionError = error
                    if attempt == 4 || !Self.isRetryable(error) { break }
                    do { try await pause(UInt64(1 << attempt) * 1_000_000_000) }
                    catch { return }
                }
            }
            if generation == token { runTask = nil }
        }
    }

    func stop() {
        streamEpoch += 1
        generation += 1; selectionGeneration += 1
        runTask?.cancel(); runTask = nil
        snapshotTask?.cancel(); snapshotTask = nil
        nextRosterTask?.cancel(); nextRosterTask = nil
        needsSnapshotRefresh = false
        connection?.cancel(); connection = nil
        viewersObservedAt = nil
        isLoadingResults = false; isLoadingMessages = false
    }

    func retry() { stop(); start() }

    private func refreshRounds(token: Int) async {
        do {
            let fetched = try await transport.rounds(slug: bootstrap.slug)
            let validated = try CubingChinaLiveBootstrap.make(slug: bootstrap.slug, rounds: fetched)
            guard validated.competitionID == bootstrap.competitionID else { throw CubingChinaLiveError.invalidData }
            guard !Task.isCancelled, generation == token else { return }
            let previous = Dictionary(uniqueKeysWithValues: rounds.map { ($0.id, $0.revision) })
            let previousRounds = rounds
            let merged = fetched.map { value in
                if let current = rounds.first(where: { $0.id == value.id }), current.revision > value.revision { return current }
                return value
            }
            if rounds != merged { rounds = merged }
            let validKeys = Set(rounds.map(\.key))
            cachedRounds = cachedRounds.filter { validKeys.contains($0.key) }
            cachedRoundOrder.removeAll { !validKeys.contains($0) }
            roundEventSequences = roundEventSequences.filter { validKeys.contains($0.key) }
            let validSelections = Set(rounds.map { $0.key.selectionID })
            knownBadgeRounds = knownBadgeRounds.filter { validSelections.contains($0.key) }
            knownBadgeEpochs = knownBadgeEpochs.filter { validSelections.contains($0.key) }
            if let selected = rounds.first(where: { $0.key == selectedKey }),
               selected.id != state.expectedRound.id || selected.competitionRoundId != state.expectedRound.competitionRoundId {
                selectionGeneration += 1; snapshotTask?.cancel(); snapshotTask = nil; needsSnapshotRefresh = false
                snapshot = nil; state = CubingChinaLiveRoundState(round: selected)
            }
            for value in fetched {
                if value.key == selectedKey { try state.observeMetadata(value) }
                if value.revision > (previous[value.id] ?? -1) {
                    invalidateAdvancement(value)
                    if value.key != selectedKey {
                        knownRoundBadges[value.key.selectionID] = nil; knownBadgeRounds[value.key.selectionID] = nil
                    }
                }
            }
            if !rounds.contains(where: { $0.key == selectedKey }) {
                snapshotTask?.cancel(); selectionGeneration += 1
                snapshot = nil; resultError = CubingChinaLiveError.unsupported
            }
            if rounds != previousRounds { aggregateRefreshID += 1 }
        } catch { if !Task.isCancelled, generation == token { connectionError = error } }
    }

    private func refreshSelectedRound() {
        guard rounds.contains(where: { $0.key == selectedKey }) else { return }
        if snapshotTask != nil { needsSnapshotRefresh = true; return }
        let token = generation, selection = selectionGeneration, key = selectedKey
        if isLoadingResults != (snapshot == nil) { isLoadingResults = snapshot == nil }
        snapshotTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == token, selectionGeneration == selection {
                    if isLoadingResults { isLoadingResults = false }; snapshotTask = nil
                    if needsSnapshotRefresh {
                        needsSnapshotRefresh = false; refreshSelectedRound()
                    }
                }
            }
            for attempt in 0..<3 {
                do {
                    let eventSequence = roundEventSequences[key, default: 0]
                    let requestedStream = streamEpoch
                    let fetched = try await fetchSnapshot(key)
                    guard !Task.isCancelled, generation == token, selectionGeneration == selection else { return }
                    // Even an equal-revision event can correct records while REST is in flight.
                    if streamEpoch != requestedStream || roundEventSequences[key, default: 0] != eventSequence { continue }
                    if try state.install(fetched) {
                        if snapshot != state.snapshot { snapshot = state.snapshot }
                        if resultError != nil { resultError = nil }; updateRound(fetched.round)
                        rememberSelectedRound(); updateBadge()
                        return
                    }
                } catch {
                    guard !Task.isCancelled, generation == token, selectionGeneration == selection else { return }
                    resultError = error
                    if !Self.isRetryable(error) { return }
                }
                if attempt < 2 {
                    do { try await pause(UInt64(attempt + 1) * 500_000_000) } catch { return }
                }
            }
            if !Task.isCancelled, generation == token, selectionGeneration == selection {
                resultError = CubingChinaLiveError.disconnected
            }
        }
    }

    private func refreshChat(token: Int) async {
        if isLoadingMessages != messages.isEmpty { isLoadingMessages = messages.isEmpty }
        defer { if generation == token, isLoadingMessages { isLoadingMessages = false } }
        do {
            let fetched = try await transport.messages(slug: bootstrap.slug)
            guard fetched.count <= 200, fetched.allSatisfy({ $0.competitionId == bootstrap.competitionID }),
                  Set(fetched.map(\.id)).count == fetched.count else { throw CubingChinaLiveError.invalidData }
            guard !Task.isCancelled, generation == token else { return }
            let sorted = fetched.sorted { $0.id.rawValue < $1.id.rawValue }
            if messages != sorted { messages = sorted }
            if chatError != nil { chatError = nil }
        } catch { if !Task.isCancelled, generation == token { chatError = error } }
    }

    private func updateRound(_ value: CubingChinaLiveRound) {
        if let index = rounds.firstIndex(where: { $0.id == value.id }), rounds[index].revision <= value.revision,
           rounds[index] != value {
            invalidateAdvancement(value)
            rounds[index] = value
        }
    }

    private func updateBadge() {
        guard let snapshot else { return }
        if cachedRounds[selectedKey]?.streamEpoch == streamEpoch {
            knownBadgeRounds[snapshot.round.key.selectionID] = snapshot.round
            knownBadgeEpochs[snapshot.round.key.selectionID] = streamEpoch
            let tag = CubingLiveRecordIndicators.highestDisplay(
                snapshot.results.flatMap { [$0.singleIndicator, $0.averageIndicator] })
            if knownRoundBadges[snapshot.round.key.selectionID] != tag { knownRoundBadges[snapshot.round.key.selectionID] = tag }
        }
        let advancement = CubingChinaLivePresentation.advancement(
            snapshot, rounds: rounds, nextParticipants: nextParticipants(for: snapshot.round))
        if roundAdvancement[snapshot.round.key.selectionID] != advancement { roundAdvancement[snapshot.round.key.selectionID] = advancement }
        loadNextRosterIfNeeded()
    }

    private func rememberSelectedRound() {
        guard state.snapshot != nil else { return }
        remember(state, key: selectedKey)
    }

    private func remember(_ state: CubingChinaLiveRoundState, key: CubingChinaLiveRoundKey) {
        cachedRounds[key] = CachedRound(streamEpoch: streamEpoch, state: state)
        cachedRoundOrder.removeAll { $0 == key }; cachedRoundOrder.append(key)
        // Bound both entry count and total canonical rows; never truncate a snapshot.
        while cachedRoundOrder.count > 12 || cachedRounds.values.reduce(0, { $0 + ($1.state.snapshot?.results.count ?? 0) }) > 20_000 {
            cachedRounds[cachedRoundOrder.removeFirst()] = nil
        }
    }

    func roundRecordTags(in extras: CubingChinaLiveExtrasStore, ownWCAID: String? = nil) -> [String: String] {
        // Other competitors' PRs remain in Results but never enter selectors.
        var tags = extras.roundRecordTags(for: rounds).filter { $0.value != "PR" }
        for round in rounds where knownBadgeRounds[round.key.selectionID] == round && knownBadgeEpochs[round.key.selectionID] == streamEpoch {
            // A current complete snapshot can also authoritatively clear a badge.
            tags[round.key.selectionID] = PublishedCompetitionResult.recordBadge(knownRoundBadges[round.key.selectionID])
        }
        for round in rounds where tags[round.key.selectionID] == nil {
            if !extras.hasRecordEvidence(for: round), let known = cachedRounds[round.key]?.state.snapshot,
               known.round == round, known.round.competitionId == bootstrap.competitionID {
                tags[round.key.selectionID] = PublishedCompetitionResult.highestBadge(
                    known.results.flatMap { [$0.singleBadge, $0.averageBadge] })
            }
            if tags[round.key.selectionID] != nil { continue }
            if let cached = cachedRounds[round.key], cached.streamEpoch == streamEpoch,
               let snapshot = cached.state.snapshot, snapshot.round == round {
                tags[round.key.selectionID] = CubingLiveRecordIndicators.selector(snapshot.results.map {
                    ($0.singleIndicator, $0.averageIndicator, $0.competitor?.wcaId)
                }, ownWCAID: ownWCAID)
            } else {
                tags[round.key.selectionID] = personalRecords.tag(for: round, ownWCAID: ownWCAID,
                    evidence: personalRecordEvidenceIdentity)
            }
        }
        return tags
    }

    var personalRecordEvidenceIdentity: String {
        "\(bootstrap.competitionID.rawValue)|\(personalEvidenceSequence)|" + rounds.map {
            "\($0.id.rawValue):\($0.competitionRoundId.rawValue):\($0.eventId):\($0.roundNumber)"
        }.sorted().joined(separator: ",")
    }

    var personalRecordRefreshIdentity: String { "\(generation)|\(streamEpoch)|" + personalRecordEvidenceIdentity }
    var hasCurrentSnapshot: Bool {
        guard let snapshot, let cached = cachedRounds[selectedKey], cached.streamEpoch == streamEpoch else { return false }
        return snapshot == state.snapshot && cached.state.snapshot?.round == snapshot.round
    }

    func discoverPersonalRecords(ownWCAID: String?, candidates: [CubingChinaLiveResult.Competitor]) async {
        let evidence = personalRecordEvidenceIdentity, requestScope = personalRecordRefreshIdentity, rounds = rounds
        await personalRecords.load(ownWCAID: ownWCAID, candidates: candidates, rounds: rounds, evidence: evidence,
            refreshIdentity: requestScope) { [self] number in
            let slug = bootstrap.slug, transport = transport
            let rows = try? await competitorRequests.value(key: "personal|\(slug)|\(number)|\(requestScope)") {
                try await transport.competitorResults(slug: slug, number: number)
            }
            guard personalRecordRefreshIdentity == requestScope else { return nil }
            return rows
        }
    }

    var knownAdvancement: [String: CompetitionAdvancement] {
        roundAdvancement.values.reduce(into: [:]) { $0.merge($1) { _, new in new } }
    }

    var advancementEvidenceIdentity: String {
        "\(generation)|" + rounds.map {
            "\($0.id.rawValue):\($0.competitionRoundId.rawValue):\($0.revision):\($0.status)"
        }.joined(separator: "|")
    }

    /// Grouped records/podiums contain only a subset of the field. Fetch their
    /// complete evidence without selecting a Results tab or changing its round.
    func loadAdvancementEvidence(for keys: [CubingChinaLiveRoundKey]) async {
        let token = generation
        for key in keys {
            guard !Task.isCancelled, generation == token else { return }
            guard let expected = rounds.first(where: { $0.key == key }) else { continue }
            if roundAdvancement[key.selectionID] != nil,
               nextRound(after: expected) == nil || nextParticipants(for: expected) != nil { continue }
            do {
                let full = try await fetchSnapshot(key).validated()
                guard acceptsEvidence(full, expected: expected, token: token) else { continue }
                let next = nextRound(after: full.round)
                var fetchedNext: CubingChinaLiveSnapshot?
                if let next, nextParticipants(for: full.round) == nil {
                    fetchedNext = try await fetchSnapshot(next.key).validated()
                    guard let fetchedNext, acceptsEvidence(fetchedNext, expected: next, token: token),
                          nextRound(after: full.round)?.id == next.id else { continue }
                }
                guard acceptsEvidence(full, expected: expected, token: token) else { continue }
                // Install metadata, roster and derived states together, after all
                // suspension points; no partial field can authorize a highlight.
                updateRound(full.round)
                if let fetchedNext {
                    updateRound(fetchedNext.round)
                    nextRosters[fetchedNext.round.key] = Roster(revision: fetchedNext.round.revision,
                        people: Set(fetchedNext.results.map(\.userId)))
                }
                roundAdvancement[key.selectionID] = CubingChinaLivePresentation.advancement(
                    full, rounds: rounds, nextParticipants: nextParticipants(for: full.round))
                if snapshot?.round.key == key, snapshot?.round != full.round, runTask != nil {
                    refreshSelectedRound()
                }
            } catch {
                // Preserve unknown evidence on failure; never turn a record or
                // partial podium into a guessed qualification.
                if Task.isCancelled || generation != token { return }
            }
        }
    }

    private func acceptsEvidence(_ value: CubingChinaLiveSnapshot, expected: CubingChinaLiveRound, token: Int) -> Bool {
        guard !Task.isCancelled, generation == token,
              value.round.competitionId == bootstrap.competitionID,
              value.round.key == expected.key, value.round.id == expected.id,
              value.round.competitionRoundId == expected.competitionRoundId,
              let current = rounds.first(where: { $0.key == expected.key }),
              current.id == expected.id, current.competitionRoundId == expected.competitionRoundId,
              value.round.revision >= current.revision else { return false }
        return true
    }

    private func fetchSnapshot(_ key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot {
        guard let round = rounds.first(where: { $0.key == key }) else { throw CubingChinaLiveError.unsupported }
        let identity = "\(round.id.rawValue)|\(round.competitionRoundId.rawValue)|\(round.revision)"
        let transport = transport, slug = bootstrap.slug
        return try await resultRequests.value(key: identity) { try await transport.results(slug: slug, key: key) }
    }

    func nextParticipants(for round: CubingChinaLiveRound) -> Set<CubingChinaLiveID<CubingChinaIDKind.User>>? {
        guard let next = nextRound(after: round), let roster = nextRosters[next.key],
              roster.revision == next.revision else { return nil }
        return roster.people
    }

    private func nextRound(after round: CubingChinaLiveRound) -> CubingChinaLiveRound? {
        rounds.first { $0.eventId == round.eventId && $0.roundNumber == round.roundNumber + 1
            && ["open", "live", "finished"].contains($0.status) }
    }

    private func invalidateAdvancement(_ round: CubingChinaLiveRound) {
        roundAdvancement[round.key.selectionID] = nil
        // Opening/reranking a subsequent round can revoke a previous qualification.
        for previous in rounds where previous.eventId == round.eventId && previous.roundNumber + 1 == round.roundNumber {
            roundAdvancement[previous.key.selectionID] = nil
        }
        nextRosters[round.key] = nil
    }

    private func loadNextRosterIfNeeded() {
        guard nextRosterTask == nil, let snapshot, let next = nextRound(after: snapshot.round),
              nextParticipants(for: snapshot.round) == nil else { return }
        let token = generation, selection = selectionGeneration
        nextRosterTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token, selectionGeneration == selection { nextRosterTask = nil } }
            // Only the adjacent round in this opened competition, never global discovery.
            guard let fetched = try? await fetchSnapshot(next.key),
                  (try? fetched.validated()) != nil, fetched.round.key == next.key,
                  fetched.round.competitionId == bootstrap.competitionID,
                  fetched.round.id == next.id, fetched.round.competitionRoundId == next.competitionRoundId,
                  fetched.round.revision >= next.revision, !Task.isCancelled,
                  generation == token, selectionGeneration == selection,
                  let current = rounds.first(where: { $0.id == next.id }),
                  current.revision <= fetched.round.revision else { return }
            updateRound(fetched.round)
            nextRosters[next.key] = Roster(revision: fetched.round.revision, people: Set(fetched.results.map(\.userId)))
            if let snapshot = self.snapshot {
                roundAdvancement[snapshot.round.key.selectionID] = CubingChinaLivePresentation.advancement(
                    snapshot, rounds: rounds, nextParticipants: nextParticipants(for: snapshot.round))
            }
        }
    }

    private func receive(_ frame: CubingChinaSSEFrame, token: Int) async throws {
        let bytes = Data(frame.data.utf8), decoder = JSONDecoder()
        let envelope = try decoder.decode(CubingChinaLiveEnvelope.self, from: bytes)
        if let count = envelope.viewers, count >= 0 {
            viewers = count
            viewersObservedAt = CubingChinaLiveHeaderMetadata.viewerObservation(occurredAt: envelope.occurredAt, now: Date())
        }
        if envelope.type == "heartbeat" { return }
        struct Payload<Value: Decodable>: Decodable { let payload: Value }
        switch envelope.type {
        case "message.created":
            let message = try decoder.decode(Payload<CubingChinaLiveMessage>.self, from: bytes).payload
            guard message.competitionId == bootstrap.competitionID else { throw CubingChinaLiveError.invalidData }
            messages.removeAll { $0.id == message.id }; messages.append(message)
            messages.sort { $0.id.rawValue < $1.id.rawValue }
            if messages.count > 200 { messages.removeFirst(messages.count - 200) }
        case "message.deleted":
            struct Deleted: Decodable { let id: CubingChinaLiveID<CubingChinaIDKind.Message> }
            let removed = try decoder.decode(Payload<Deleted>.self, from: bytes).payload
            messages.removeAll { $0.id == removed.id }
        case "chat.updated": break // Read-only access does not change when posting permissions change.
        case "round.updated", "round.rules.updated", "round.competitor.joined", "round.competitor.quit",
             "result.updated", "result.attempt.updated", "result.checked", "results.reranked", "advancement.refreshed":
            guard let delta = try? decoder.decode(Payload<CubingChinaLiveDelta>.self, from: bytes).payload else {
                personalEvidenceSequence += 1
                streamEpoch += 1
                await refreshRounds(token: token)
                if !Task.isCancelled, generation == token { aggregateRefreshID += 1; refreshSelectedRound() }
                return
            }
            guard delta.round.isValid, delta.round.competitionId == bootstrap.competitionID else {
                throw CubingChinaLiveError.invalidData
            }
            if !rounds.contains(where: { $0.id == delta.round.id }) { await refreshRounds(token: token) }
            guard !Task.isCancelled, generation == token else { return }
            let previousRevision = rounds.first(where: { $0.id == delta.round.id })?.revision ?? -1
            if delta.round.revision >= previousRevision {
                let affected = delta.upsertedResults.contains { value in
                    CompetitionPersonalIdentity.matches(signedInWCAID: personalRecords.wcaID, competitorWCAID: value.competitor?.wcaId)
                } || delta.removedResultIds.contains { id in personalRecords.rows.contains { $0.id == id } }
                if affected || envelope.type.hasPrefix("round.") || envelope.type == "advancement.refreshed" {
                    personalEvidenceSequence += 1
                }
            }
            if delta.round.revision >= previousRevision, rounds.contains(where: { $0.id == delta.round.id }) {
                roundEventSequences[delta.round.key, default: 0] += 1
            }
            updateRound(delta.round)
            if delta.round.revision >= previousRevision { aggregateRefreshID += 1 }
            guard delta.round.key == selectedKey else {
                if let cached = cachedRounds[delta.round.key], cached.streamEpoch == streamEpoch {
                    var updated = cached.state
                    if try !updated.apply(delta) { remember(updated, key: delta.round.key) }
                    else { cachedRounds[delta.round.key] = nil; cachedRoundOrder.removeAll { $0 == delta.round.key } }
                }
                if delta.round.revision >= previousRevision {
                    knownRoundBadges[delta.round.key.selectionID] = nil; knownBadgeRounds[delta.round.key.selectionID] = nil
                }
                if let snapshot, nextRound(after: snapshot.round)?.id == delta.round.id,
                   nextParticipants(for: snapshot.round) == nil {
                    nextRosterTask?.cancel(); nextRosterTask = nil
                }
                updateBadge()
                return
            }
            if try state.apply(delta) { refreshSelectedRound() }
            else { snapshot = state.snapshot; rememberSelectedRound(); updateBadge() }
        default:
            personalEvidenceSequence += 1
            streamEpoch += 1
            await refreshRounds(token: token)
            if !Task.isCancelled, generation == token { aggregateRefreshID += 1; refreshSelectedRound() }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let liveError = error as? CubingChinaLiveError else { return !(error is DecodingError) }
        switch liveError {
        case .http(let status): return status == 408 || status == 429 || status >= 500
        case .invalidData, .unsupported: return false
        default: return true
        }
    }

    func competitorResults(number: Int) async -> [CubingChinaLiveResult]? {
        let token = generation, evidence = aggregateRefreshID
        let slug = bootstrap.slug, transport = transport
        guard let values = try? await competitorRequests.value(key: "cubing|\(slug)|person:\(number)|\(token)|\(evidence)", loader: {
            try await transport.competitorResults(slug: slug, number: number)
        }), generation == token, aggregateRefreshID == evidence,
              !Task.isCancelled, !values.isEmpty, values.count <= 500,
              values.allSatisfy({ value in
                  value.competitionId == bootstrap.competitionID && value.competitor?.number == number
                      && rounds.contains(where: { value.belongs(to: $0) })
              }) else { return nil }
        return values
    }
}
