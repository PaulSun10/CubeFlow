import Foundation
import Testing
@testable import CubeFlow

@MainActor
struct ExploreCompositionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func heroIsUniqueAndCompositionIgnoresInputOrder() {
        let candidates = [candidate("a", .feature, hero: true), candidate("b", .feature, hero: true),
                          candidate("c", .carousel), candidate("d", .compactList)]
        let context = ExploreCompositionContext(now: now)
        let result = ExploreComposer.compose(candidates, context: context)
        #expect(result.filter { $0.presentation == .hero }.count == 1)
        #expect(result == ExploreComposer.compose(candidates.reversed(), context: context))
        #expect(result == ExploreComposer.compose(candidates, context: ExploreCompositionContext(now: now.addingTimeInterval(20))))
    }

    @Test func freshImportantContentOutranksPersonalRelevance() {
        var record = candidate("record", .feature, hero: true)
        record.importance = 100
        record.publishedAt = now
        var local = candidate("local", .feature, hero: true)
        local.importance = 30
        local.regionCode = "CN"
        local.eventIDs = ["333"]
        local.competitionIDs = ["registered"]
        let result = ExploreComposer.compose([local, record], context: ExploreCompositionContext(
            now: now, wcaRegionCode: "CN", officialEventIDs: ["333"], registeredCompetitionIDs: ["registered"]))
        #expect(result.first?.id == "record")
    }

    @Test func freshnessBreaksEqualImportanceBeforePersonalRelevance() {
        var old = candidate("old", .feature)
        old.publishedAt = now.addingTimeInterval(-20 * 86_400)
        old.regionCode = "CN"
        var fresh = candidate("fresh", .feature)
        fresh.publishedAt = now
        let result = ExploreComposer.compose([old, fresh], context: ExploreCompositionContext(now: now, wcaRegionCode: "CN"))
        #expect(result.first?.id == "fresh")
    }

    @Test func unavailableExpiredAndEmptyCandidatesAreOmitted() {
        var unavailable = candidate("unavailable", .feature)
        unavailable.isAvailable = false
        var expired = candidate("expired", .feature)
        expired.expiresAt = now
        let empty = ExploreCandidate(id: "empty", titleKey: "test", items: [], presentation: .carousel)
        #expect(ExploreComposer.compose([unavailable, expired, empty], context: ExploreCompositionContext(now: now)).isEmpty)
        #expect(ExploreComposer.compose([], context: ExploreCompositionContext(now: now)).isEmpty)
    }

    @Test func similarPrioritiesVaryPresentationAndDuplicateContentIsNotRepeated() {
        var duplicate = candidate("duplicate", .compactList)
        duplicate = ExploreCandidate(id: duplicate.id, titleKey: "test", items: candidate("a", .carousel).items, presentation: .compactList)
        let result = ExploreComposer.compose([candidate("a", .carousel), candidate("b", .carousel),
            candidate("c", .feature), duplicate], context: ExploreCompositionContext(now: now))
        #expect(result.count == 3)
        #expect(result[0].presentation != result[1].presentation)
        let ids = result.flatMap(\.items).map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test func homePreviewIsBoundedAndDoesNotRepeatTheHero() {
        let items = (0..<22).map { index in
            ExploreItem(
                id: "recent-record.\(index)",
                content: .recentRecord(id: "\(index)", competitionID: "competition", roundID: "round",
                                       personID: "person", personWCAID: nil),
                title: "Record \(index)", subtitle: "Person", date: nil
            )
        }
        let list = ExploreCandidate(id: "records.recent", titleKey: "recent", items: items,
                                    presentation: .compactList, importance: 55)
        let hero = ExploreCandidate(id: "records.recent-world", titleKey: "world",
                                    items: [items[10]], presentation: .hero,
                                    heroEligibility: .worldRecord, importance: 85)

        let modules = ExploreComposer.compose([list, hero], context: ExploreCompositionContext(now: now))
        #expect(modules.first?.id == "records.recent-world")
        #expect(modules.first(where: { $0.id == "records.recent" })?.items.map(\.id) == Array(items.prefix(3)).map(\.id))
        #expect(Set(modules.flatMap(\.items).map(\.id)).count == modules.flatMap(\.items).count)
        let leadingHero = ExploreCandidate(id: hero.id, titleKey: hero.titleKey, items: [items[0]],
            presentation: .hero, heroEligibility: .worldRecord, importance: 85)
        let leading = ExploreComposer.compose([list, leadingHero], context: ExploreCompositionContext(now: now))
        #expect(leading.first(where: { $0.id == "records.recent" })?.items.map(\.id) == Array(items[1...3]).map(\.id))
    }

    @Test func weeklyContentUsesExistingPresentations() {
        let weekly = ExploreItem(id: "weekly", content: .weeklyCompetition(id: "week-1"), title: "Fixture", subtitle: "", date: nil)
        for presentation in ExplorePresentation.allCases {
            let candidate = ExploreCandidate(id: "weekly", titleKey: "test", items: [weekly], presentation: presentation, heroEligibility: presentation == .hero ? .weekly : nil)
            let modules = ExploreComposer.compose([candidate], context: ExploreCompositionContext(now: now))
            #expect(modules.count == 1)
            #expect(modules.first?.items.first?.content == .weeklyCompetition(id: "week-1"))
        }
    }

    @Test func upcomingCompetitionsAreUsefulWithoutLoginButNeverBecomeHero() {
        let ended = competition("ended", date: now.addingTimeInterval(-3 * 86_400))
        let spotlight = competition("spotlight", date: now.addingTimeInterval(86_400))
        let unknown = competition("unknown", date: now.addingTimeInterval(2 * 86_400))
        var open = competition("open", date: now.addingTimeInterval(3 * 86_400), registrationOpen: now.addingTimeInterval(-100), registrationClose: now.addingTimeInterval(100))
        open.registrationStatus = .open
        let input = [ended, spotlight, unknown, open]
        #expect(ExploreCompetitionCandidates.make(input, now: now).first?.id == "competition.upcoming")
        #expect(ExploreCompetitionCandidates.make(input, now: now, wcaRegionCode: "HK").isEmpty)
        #expect(ExploreCompetitionCandidates.make(input, now: now, wcaRegionCode: "invalid").first?.id == "competition.upcoming")
        var candidates = ExploreCompetitionCandidates.make(input, now: now, wcaRegionCode: "CN")
        #expect(candidates.count == 1)
        candidates[0].importance = 100
        let modules = ExploreComposer.compose(candidates, context: ExploreCompositionContext(now: now))
        #expect(!modules.flatMap(\.items).contains { $0.id == "competition.ended" })
        #expect(modules.allSatisfy { $0.presentation != .hero })
        #expect(modules.first?.id == "competition.nearby")
        #expect(modules.flatMap(\.items).first { $0.id == "competition.open" }?.competition?.registrationOpen == true)
        #expect(modules.first?.items.first?.id == "competition.spotlight")
    }

    @Test func nearYouUsesAnExactPublicRegionNotUnrelatedGlobalEvents() {
        let local = competition("local", date: now.addingTimeInterval(86400), country: "HK")
        let foreign = competition("foreign", date: now.addingTimeInterval(86400), country: "ES")
        let input = ExploreCompetitionCandidates.make([foreign, local], now: now, wcaRegionCode: "HK")
        #expect(input.flatMap(\.items).map(\.id) == ["competition.local"])
    }

    @Test func publicRegionChangesRecomposeAndUseRegionScopedCache() async {
        let provider = FixtureProvider(snapshot: ExploreCompetitionSnapshot(
            competitions: [competition("local", date: now.addingTimeInterval(86_400), country: "HK")],
            fetchedAt: now), fails: false)
        let store = ExploreStore(provider: provider)
        await store.load(language: "en", now: now)
        #expect(store.modules.map(\.id) == ["competition.upcoming"])
        store.setWCARegionCode("hk", now: now)
        await store.load(language: "en", now: now)
        #expect(store.modules.map(\.id) == ["competition.nearby"])
        store.setWCARegionCode(nil, now: now)
        #expect(store.modules.isEmpty)
        await store.load(language: "en", now: now)
        #expect(provider.cachedRegions == [nil, "HK", nil])
    }

    @Test func scopedCompetitionQueryUsesOfficialCountry() {
        let provider = ExploreCompetitionProvider()
        #expect(provider.query("en", regionCode: "HK").region == .country("HK"))
        #expect(provider.query("en", regionCode: nil).region == .all)
    }

    @Test func heroEligibilityCannotBeBorrowedFromAnotherFamily() {
        var candidate = candidate("ordinary", .feature)
        candidate.heroEligibility = .worldRecord
        #expect(ExploreComposer.compose([candidate], context: ExploreCompositionContext(now: now)).allSatisfy { $0.presentation != .hero })
    }

    @Test func recentCacheFailureStaysQuietAndStaleFailureOffersRetry() async {
        let ages: [TimeInterval] = [0, 7 * 3600, 48 * 3600]
        for age in ages {
            let provider = FixtureProvider(snapshot: ExploreCompetitionSnapshot(
                competitions: [competition("cached", date: now.addingTimeInterval(86400))],
                fetchedAt: now.addingTimeInterval(-age)), fails: true)
            let store = ExploreStore(provider: provider, wcaRegionCode: "CN")
            await store.load(language: "en", force: true, now: now)
            #expect(store.showsSavedDataNotice == (age > 24 * 3600))
            #expect(store.canRetry == (age > 24 * 3600))
            #expect(!store.modules.isEmpty)
        }
    }

    @Test func endedCachedContentIsEmptyNotAnError() async {
        let store = ExploreStore(provider: FixtureProvider(snapshot: ExploreCompetitionSnapshot(
            competitions: [competition("foreign", date: now.addingTimeInterval(-86400))],
            fetchedAt: now.addingTimeInterval(-48 * 3600)), fails: true))
        await store.load(language: "en", now: now)
        #expect(store.modules.isEmpty)
        #expect(store.state == .empty)
        #expect(!store.canRetry)
    }

    @Test func cachedContentSurvivesRefreshFailureAndOtherSourcesContinue() async {
        let provider = FixtureProvider(snapshot: ExploreCompetitionSnapshot(competitions: [competition("cached", date: now.addingTimeInterval(86_400))], fetchedAt: now.addingTimeInterval(-86_400)), fails: true)
        let store = ExploreStore(provider: provider, wcaRegionCode: "CN")
        store.setSupplementalCandidates([candidate("editorial", .feature)], now: now)
        await store.load(language: "en", now: now)
        #expect(store.state == .failedWithCache)
        #expect(store.modules.contains { $0.id == "editorial" })
        #expect(store.modules.contains { $0.id == "competition.nearby" })
        #expect(provider.calls == 1)
        await store.load(language: "en", now: now.addingTimeInterval(10))
        #expect(provider.calls == 1)
    }

    @Test func firstFailureEmptyAndFreshCacheAreDistinct() async {
        let failed = ExploreStore(provider: FixtureProvider(snapshot: nil, fails: true))
        await failed.load(language: "en", now: now)
        #expect(failed.state == .failed)
        let provider = FixtureProvider(snapshot: ExploreCompetitionSnapshot(competitions: [], fetchedAt: now), fails: false)
        let empty = ExploreStore(provider: provider)
        await empty.load(language: "en", now: now)
        #expect(empty.state == .empty)
        #expect(provider.calls == 0)
    }

    @Test func optionalProviderFailureStillShowsIndependentContent() async {
        let store = ExploreStore(provider: FixtureProvider(snapshot: nil, fails: true))
        store.setSupplementalCandidates([candidate("available", .feature)], now: now)
        await store.load(language: "en", now: now)
        #expect(store.modules.map(\.id) == ["available"])
        #expect(store.state == .failedWithCache)
    }

    @Test func snapshotRoundTripPreservesFreshnessAndCompetitionDestination() throws {
        let original = ExploreCompetitionSnapshot(competitions: [competition("persisted", date: now)], fetchedAt: now)
        let decoded = try JSONDecoder().decode(ExploreCompetitionSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded.fetchedAt == now)
        #expect(decoded.competitions.first?.id == "persisted")
    }

    private func candidate(_ id: String, _ presentation: ExplorePresentation, hero: Bool = false) -> ExploreCandidate {
        ExploreCandidate(id: id, titleKey: "test", items: [ExploreItem(id: id, content: .highlight(id: id), title: id, subtitle: "", date: nil)],
                         presentation: presentation, heroEligibility: hero ? .editorialHighlight : nil, importance: 40)
    }

    private func competition(_ id: String, date: Date, registrationOpen: Date? = nil, registrationClose: Date? = nil, country: String = "CN") -> CompetitionSummary {
        CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: date, endDate: date,
            registrationOpen: registrationOpen, registrationClose: registrationClose, competitorLimit: nil,
            venue: "", venueAddress: "", venueDetails: nil, city: "Test city", countryISO2: country,
            latitude: nil, longitude: nil, url: "https://www.worldcubeassociation.org/competitions/\(id)",
            website: nil, dateRange: "", eventIDs: ["333"], championshipTypes: nil,
            localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
    }
}

@MainActor
private final class FixtureProvider: ExploreCompetitionProviding {
    let snapshot: ExploreCompetitionSnapshot?
    let fails: Bool
    var calls = 0
    var cachedRegions: [String?] = []
    init(snapshot: ExploreCompetitionSnapshot?, fails: Bool) { self.snapshot = snapshot; self.fails = fails }
    func cached(language: String, regionCode: String?) async -> ExploreCompetitionSnapshot? {
        cachedRegions.append(regionCode)
        return snapshot
    }
    func refresh(language: String, regionCode: String?) async throws -> ExploreCompetitionSnapshot {
        calls += 1
        if fails { throw URLError(.notConnectedToInternet) }
        return snapshot ?? ExploreCompetitionSnapshot(competitions: [], fetchedAt: Date())
    }
}
