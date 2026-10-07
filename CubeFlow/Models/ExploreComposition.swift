import Foundation

nonisolated enum ExploreBrowseDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case competitions, rankings, records, stats, highlights
    var id: String { rawValue }
    var titleKey: String { self == .competitions ? "tab.competitions" : "explore.\(rawValue)" }
}

nonisolated enum ExploreContent: Hashable, Sendable {
    case competition(id: String)
    case record(id: String)
    case recentRecord(
        id: String,
        competitionID: String,
        roundID: String,
        personID: String,
        personWCAID: String?
    )
    case statistic(id: String)
    case highlight(id: String)
    case weeklyCompetition(id: String)

    var destination: ExploreBrowseDestination {
        switch self {
        case .competition, .weeklyCompetition: .competitions
        case .record, .recentRecord: .records
        case .statistic: .stats
        case .highlight: .highlights
        }
    }
}

nonisolated struct ExploreItem: Identifiable, Hashable, Sendable {
    let id: String
    let content: ExploreContent
    let title: String
    let subtitle: String
    let date: Date?
    var competition: ExploreCompetitionPresentation? = nil
    var result: ExploreResultPresentation? = nil
    var recordContext: ExploreRecordContext? = nil
}

nonisolated struct ExploreRecordContext: Hashable, Sendable {
    let eventName: String
    let resultType: String
    let personName: String
    let countryName: String
    let competitionName: String
}

nonisolated struct ExploreCompetitionPresentation: Hashable, Sendable {
    let start: Date
    let end: Date
    let eventCount: Int
    let registrationOpen: Bool
}

nonisolated struct ExploreResultPresentation: Hashable, Sendable {
    enum Level: String, Sendable { case world = "WR", continental = "CR", national = "NR" }
    let value: String
    let level: Level
    var showsValueInBadge = true
    // Achievement is immutable. Standing must come from an authoritative ranking,
    // never from the position of a result in the bounded WCA Live feed.
    var currentRank: Int? = nil
}

/// Editorial eligibility is supplied by the content source, never inferred from score.
nonisolated enum ExploreHeroEligibility: Sendable {
    case worldRecord, majorCompetition, editorialHighlight, weekly

    func accepts(_ content: ExploreContent) -> Bool {
        switch (self, content) {
        case (.worldRecord, .record), (.worldRecord, .recentRecord), (.majorCompetition, .competition),
             (.editorialHighlight, .highlight), (.weekly, .weeklyCompetition): true
        default: false
        }
    }
}

nonisolated enum ExplorePresentation: String, CaseIterable, Sendable {
    case hero, feature, carousel, compactList
}

nonisolated struct ExploreCandidate: Identifiable, Sendable {
    let id: String
    let titleKey: String
    let items: [ExploreItem]
    let presentation: ExplorePresentation
    var heroEligibility: ExploreHeroEligibility? = nil
    var importance = 0
    var publishedAt: Date? = nil
    var expiresAt: Date? = nil
    var isAvailable = true
    var regionCode: String? = nil
    var eventIDs: Set<String> = []
    var competitionIDs: Set<String> = []
    var seeAll: ExploreBrowseDestination? = nil
    var titleTable: String? = nil
}

/// Only public WCA participation/registration signals belong in this context.
nonisolated struct ExploreCompositionContext: Sendable {
    let now: Date
    var wcaRegionCode: String? = nil
    var officialEventIDs: Set<String> = []
    var registeredCompetitionIDs: Set<String> = []
}

nonisolated struct ExploreModule: Identifiable, Equatable, Sendable {
    let id: String
    let titleKey: String
    let presentation: ExplorePresentation
    let items: [ExploreItem]
    let seeAll: ExploreBrowseDestination?
    var titleTable: String? = nil
}

nonisolated enum ExploreComposer {
    static func compose(
        _ candidates: [ExploreCandidate],
        context: ExploreCompositionContext,
        limit: Int = 6
    ) -> [ExploreModule] {
        guard limit > 0 else { return [] }
        var remaining = candidates.filter {
            $0.isAvailable && !$0.items.isEmpty
                && ($0.expiresAt.map { $0 > context.now } ?? true)
        }.sorted {
            let left = score($0, context: context)
            let right = score($1, context: context)
            return left == right ? $0.id < $1.id : left > right
        }
        var modules: [ExploreModule] = []
        var usedItems: Set<String> = []
        var usedCandidates: Set<String> = []

        if let hero = remaining.first(where: {
            $0.items.count == 1 && ($0.heroEligibility?.accepts($0.items[0].content) == true)
        }) {
            modules.append(module(hero, presentation: .hero, items: hero.items))
            usedItems.insert(hero.items[0].id)
            usedCandidates.insert(hero.id)
            remaining.removeAll { $0.id == hero.id }
        }
        while !remaining.isEmpty && modules.count < limit {
            // Vary visual weight among comparably important candidates without
            // demoting breaking content solely for a different card shape.
            let firstScore = score(remaining[0], context: context)
            let index = remaining.firstIndex {
                effectivePresentation($0) != modules.last?.presentation
                    && firstScore - score($0, context: context) <= 100
            } ?? 0
            let candidate = remaining.remove(at: index)
            guard usedCandidates.insert(candidate.id).inserted else { continue }
            var itemIDs = usedItems
            let items = candidate.items.filter { itemIDs.insert($0.id).inserted }
            guard !items.isEmpty else { continue }
            let presentation = effectivePresentation(candidate)
            let selected = Array(items.prefix(candidate.id == "records.recent" ? 3 : (presentation == .feature ? 1 : 8)))
            usedItems.formUnion(selected.map(\.id))
            modules.append(module(candidate, presentation: presentation, items: selected))
        }
        return modules
    }

    private static func effectivePresentation(_ candidate: ExploreCandidate) -> ExplorePresentation {
        candidate.presentation == .hero ? .feature : candidate.presentation
    }

    private static func module(
        _ candidate: ExploreCandidate,
        presentation: ExplorePresentation,
        items: [ExploreItem]
    ) -> ExploreModule {
        ExploreModule(id: candidate.id, titleKey: candidate.titleKey,
                      presentation: presentation, items: items, seeAll: candidate.seeAll, titleTable: candidate.titleTable)
    }

    private static func score(_ candidate: ExploreCandidate, context: ExploreCompositionContext) -> Int {
        let ageDays = candidate.publishedAt.map { max(0, Int(context.now.timeIntervalSince($0) / 86_400)) }
        let freshness = ageDays.map { max(0, 100 - min($0, 20) * 5) } ?? 0
        let region = candidate.regionCode != nil && candidate.regionCode == context.wcaRegionCode ? 8 : 0
        let events = candidate.eventIDs.isDisjoint(with: context.officialEventIDs) ? 0 : 4
        let competitions = candidate.competitionIDs.isDisjoint(with: context.registeredCompetitionIDs) ? 0 : 8
        return min(100, max(0, candidate.importance)) * 10 + freshness + region + events + competitions
    }
}
