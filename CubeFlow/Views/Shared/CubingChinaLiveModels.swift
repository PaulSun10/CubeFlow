import Foundation

nonisolated enum CubingChinaIDKind {
    enum Competition: Sendable {}
    enum LiveRound: Sendable {}
    enum CompetitionRound: Sendable {}
    enum Result: Sendable {}
    enum User: Sendable {}
    enum Registration: Sendable {}
    enum Message: Sendable {}
}

/// Numeric IDs share a wire representation, not an interchangeable identity domain.
nonisolated struct CubingChinaLiveID<Kind>: Hashable, Codable, Sendable {
    let rawValue: Int
    init(_ value: Int) { rawValue = value }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Int.self)
        guard value > 0 else { throw CubingChinaLiveError.invalidData }
        rawValue = value
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}

nonisolated struct CubingChinaLiveRoundKey: Hashable, Codable, Sendable {
    let eventID: String
    let number: Int
    var selectionID: String { "\(eventID)|\(number)" }
}

nonisolated struct CubingChinaLiveRound: Hashable, Codable, Sendable, Identifiable {
    let id: CubingChinaLiveID<CubingChinaIDKind.LiveRound>
    let competitionId: CubingChinaLiveID<CubingChinaIDKind.Competition>
    let competitionRoundId: CubingChinaLiveID<CubingChinaIDKind.CompetitionRound>
    let revision: Int
    let eventId: String
    let roundNumber: Int
    let status: String
    let startedAt: String?
    let round: Rules

    struct Rules: Hashable, Codable, Sendable {
        let id: CubingChinaLiveID<CubingChinaIDKind.CompetitionRound>
        let format: String
        let timeLimit: TimeLimit?
        let cutoff: Cutoff?
        let advancementCondition: Advancement?
    }
    struct TimeLimit: Hashable, Codable, Sendable { let centiseconds: Int; let cumulativeRoundIds: [String] }
    struct Cutoff: Hashable, Codable, Sendable { let attemptResult: Int; let numberOfAttempts: Int }
    struct Advancement: Hashable, Codable, Sendable { let type: String; let level: Int }
    var key: CubingChinaLiveRoundKey { .init(eventID: eventId, number: roundNumber) }
    var isFinished: Bool { status == "finished" }
    var attemptCount: Int { ["a": 5, "m": 3, "1": 1, "2": 2, "3": 3, "5": 5][round.format] ?? 0 }
    var isValid: Bool {
        round.id == competitionRoundId && revision >= 0 && roundNumber > 0 && attemptCount > 0
            && eventId.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil
    }
}

nonisolated struct CubingChinaLiveResult: Hashable, Codable, Sendable, Identifiable {
    let id: CubingChinaLiveID<CubingChinaIDKind.Result>
    let competitionId: CubingChinaLiveID<CubingChinaIDKind.Competition>
    let competitionRoundId: CubingChinaLiveID<CubingChinaIDKind.CompetitionRound>
    let registrationId: CubingChinaLiveID<CubingChinaIDKind.Registration>
    let userId: CubingChinaLiveID<CubingChinaIDKind.User>
    let eventId: String
    let roundNumber: Int
    let attempts: [Int]
    let best: Int
    let average: Int
    let position: Int?
    let regionalSingleRecord: String?
    let regionalAverageRecord: String?
    let personalSingleRecord: String?
    let personalAverageRecord: String?
    let competitor: Competitor?
    var updatedByOperatorAt: String? = nil
    var updatedAt: String? = nil

    struct Competitor: Hashable, Codable, Sendable {
        let id: CubingChinaLiveID<CubingChinaIDKind.User>
        let number: Int?
        let name: String
        let localName: String?
        let wcaId: String?
        let regionIso2: String?
    }
    func belongs(to round: CubingChinaLiveRound) -> Bool {
        competitionId == round.competitionId && competitionRoundId == round.competitionRoundId
            && eventId == round.eventId && roundNumber == round.roundNumber
            && attempts.count <= 100 && (competitor == nil || competitor?.id == userId)
    }
    var singleBadge: String? { CubingLiveRecordIndicators.regional(regionalSingleRecord) }
    var averageBadge: String? { CubingLiveRecordIndicators.regional(regionalAverageRecord) }
}

nonisolated struct CubingChinaLiveSnapshot: Hashable, Codable, Sendable {
    let round: CubingChinaLiveRound
    let results: [CubingChinaLiveResult]
    func validated() throws -> Self {
        guard round.isValid, results.count <= 20_000,
              Set(results.map(\.id)).count == results.count,
              results.allSatisfy({ $0.belongs(to: round) }) else { throw CubingChinaLiveError.invalidData }
        return self
    }
    var rankedResults: [CubingChinaLiveResult] {
        // Preserve server-authored positions; presentation sorting never reranks scores.
        results.sorted { lhs, rhs in
            if lhs.position != rhs.position { return (lhs.position ?? Int.max) < (rhs.position ?? Int.max) }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }
}

nonisolated struct CubingChinaLiveDelta: Codable, Sendable {
    let round: CubingChinaLiveRound
    let upsertedResults: [CubingChinaLiveResult]
    let removedResultIds: [CubingChinaLiveID<CubingChinaIDKind.Result>]
}

nonisolated struct CubingChinaLiveBootstrap: Hashable, Codable, Sendable {
    let slug: String
    let competitionID: CubingChinaLiveID<CubingChinaIDKind.Competition>
    let rounds: [CubingChinaLiveRound]
    static func make(slug: String, rounds: [CubingChinaLiveRound]) throws -> Self {
        guard CubingChinaTicket.website(slug: slug) != nil, let first = rounds.first,
              rounds.count <= 500, rounds.allSatisfy({ $0.isValid && $0.competitionId == first.competitionId }),
              Set(rounds.map(\.id)).count == rounds.count, Set(rounds.map(\.key)).count == rounds.count else {
            throw CubingChinaLiveError.invalidData
        }
        return Self(slug: slug, competitionID: first.competitionId, rounds: rounds)
    }
    var defaultRound: CubingChinaLiveRound {
        rounds.first(where: { $0.status == "live" })
            ?? rounds.filter { $0.eventId == "333" }.max { $0.roundNumber < $1.roundNumber }
            ?? rounds[0]
    }

    private enum CodingKeys: CodingKey { case slug, competitionID, rounds }
    init(slug: String, competitionID: CubingChinaLiveID<CubingChinaIDKind.Competition>, rounds: [CubingChinaLiveRound]) {
        self.slug = slug; self.competitionID = competitionID; self.rounds = rounds
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let validated = try Self.make(slug: values.decode(String.self, forKey: .slug),
            rounds: values.decode([CubingChinaLiveRound].self, forKey: .rounds))
        guard validated.competitionID == (try values.decode(CubingChinaLiveID<CubingChinaIDKind.Competition>.self,
            forKey: .competitionID)) else { throw CubingChinaLiveError.invalidData }
        self = validated
    }
}

nonisolated enum CubingChinaLiveError: Error, Equatable {
    case invalidData, unsupported, oversized, disconnected, http(Int)
}

/// Per-selected-round reconciliation; a forward gap raises a floor for subsequent snapshots.
nonisolated struct CubingChinaLiveRoundState {
    private(set) var snapshot: CubingChinaLiveSnapshot?
    private(set) var minimumRevision = 0
    let expectedRound: CubingChinaLiveRound

    init(round: CubingChinaLiveRound) { expectedRound = round; minimumRevision = round.revision }

    mutating func observeMetadata(_ round: CubingChinaLiveRound) throws {
        guard matches(round) else { throw CubingChinaLiveError.invalidData }
        minimumRevision = max(minimumRevision, round.revision)
    }

    private func matches(_ round: CubingChinaLiveRound) -> Bool {
        round.id == expectedRound.id && round.competitionId == expectedRound.competitionId
            && round.competitionRoundId == expectedRound.competitionRoundId && round.key == expectedRound.key
    }

    mutating func install(_ value: CubingChinaLiveSnapshot) throws -> Bool {
        _ = try value.validated()
        guard matches(value.round) else { throw CubingChinaLiveError.invalidData }
        guard value.round.revision >= max(minimumRevision, snapshot?.round.revision ?? 0) else { return false }
        snapshot = value; minimumRevision = value.round.revision
        return true
    }

    /// Returns true when REST resynchronization is required. Stale events never roll state back.
    mutating func apply(_ delta: CubingChinaLiveDelta) throws -> Bool {
        _ = try CubingChinaLiveSnapshot(round: delta.round, results: delta.upsertedResults).validated()
        guard matches(delta.round), delta.removedResultIds.count <= 20_000 else { throw CubingChinaLiveError.invalidData }
        guard let current = snapshot else { minimumRevision = max(minimumRevision, delta.round.revision); return true }
        guard current.round.id == delta.round.id, current.round.key == delta.round.key,
              current.round.competitionId == delta.round.competitionId else { throw CubingChinaLiveError.invalidData }
        let revision = delta.round.revision
        if revision < minimumRevision || revision < current.round.revision { return false }
        if minimumRevision > current.round.revision || revision - current.round.revision > 1 {
            minimumRevision = max(minimumRevision, revision); return true
        }
        let removed = Set(delta.removedResultIds)
        var values = Dictionary(uniqueKeysWithValues: current.results.filter { !removed.contains($0.id) }.map { ($0.id, $0) })
        for result in delta.upsertedResults { values[result.id] = result }
        snapshot = try CubingChinaLiveSnapshot(round: delta.round, results: Array(values.values)).validated()
        minimumRevision = revision
        return false
    }
}

nonisolated struct CubingChinaLiveMessage: Hashable, Codable, Sendable, Identifiable {
    let id: CubingChinaLiveID<CubingChinaIDKind.Message>
    let competitionId: CubingChinaLiveID<CubingChinaIDKind.Competition>
    let content: String
    let createdAt: String
    let user: User?
    struct User: Hashable, Codable, Sendable { let name: String; let localName: String? }
}

nonisolated struct CubingChinaLiveEnvelope: Decodable, Sendable {
    let type: String
    let viewers: Int?
    let occurredAt: String?
}

nonisolated enum CompetitionPersonalIdentity {
    static func canonical(_ input: String?) -> String? {
        guard let value = input?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              value.range(of: #"^[0-9]{4}[A-Z]{4}[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }
    static func matches(signedInWCAID: String?, competitorWCAID: String?) -> Bool {
        guard let own = canonical(signedInWCAID), let other = canonical(competitorWCAID) else { return false }
        return own == other
    }
}

nonisolated struct CubingChinaLiveChatState: Codable, Sendable {
    let everyoneMuted: Bool
    let canSend: Bool
    let readOnlyReason: String?
}

extension CubingChinaLiveResult {
    nonisolated var singleIndicator: String? { CubingLiveRecordIndicators.display(regional: regionalSingleRecord, personal: personalSingleRecord) }
    nonisolated var averageIndicator: String? { CubingLiveRecordIndicators.display(regional: regionalAverageRecord, personal: personalAverageRecord) }

    // Only optional record decorations are lossy. Malformed identities, scores,
    // attempts or competition/round ownership still fail normal validation.
    nonisolated private enum CodingKeys: String, CodingKey {
        case id, competitionId, competitionRoundId, registrationId, userId, eventId, roundNumber
        case attempts, best, average, position, regionalSingleRecord, regionalAverageRecord
        case personalSingleRecord, personalAverageRecord, competitor, updatedByOperatorAt, updatedAt
    }
    nonisolated init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try value.decode(CubingChinaLiveID<CubingChinaIDKind.Result>.self, forKey: .id),
            competitionId: try value.decode(CubingChinaLiveID<CubingChinaIDKind.Competition>.self, forKey: .competitionId),
            competitionRoundId: try value.decode(CubingChinaLiveID<CubingChinaIDKind.CompetitionRound>.self, forKey: .competitionRoundId),
            registrationId: try value.decode(CubingChinaLiveID<CubingChinaIDKind.Registration>.self, forKey: .registrationId),
            userId: try value.decode(CubingChinaLiveID<CubingChinaIDKind.User>.self, forKey: .userId),
            eventId: try value.decode(String.self, forKey: .eventId), roundNumber: try value.decode(Int.self, forKey: .roundNumber),
            attempts: try value.decode([Int].self, forKey: .attempts), best: try value.decode(Int.self, forKey: .best),
            average: try value.decode(Int.self, forKey: .average), position: try value.decodeIfPresent(Int.self, forKey: .position),
            regionalSingleRecord: try? value.decodeIfPresent(String.self, forKey: .regionalSingleRecord),
            regionalAverageRecord: try? value.decodeIfPresent(String.self, forKey: .regionalAverageRecord),
            personalSingleRecord: try? value.decodeIfPresent(String.self, forKey: .personalSingleRecord),
            personalAverageRecord: try? value.decodeIfPresent(String.self, forKey: .personalAverageRecord),
            competitor: try value.decodeIfPresent(Competitor.self, forKey: .competitor),
            updatedByOperatorAt: try value.decodeIfPresent(String.self, forKey: .updatedByOperatorAt),
            updatedAt: try value.decodeIfPresent(String.self, forKey: .updatedAt))
    }
}
