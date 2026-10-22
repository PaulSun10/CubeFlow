import XCTest
import Combine
@testable import CubeFlow

nonisolated private final class PersonalDiscoveryTransport: CubingChinaLiveTransport, @unchecked Sendable {
    let values: [CubingChinaLiveResult]
    let metadata: [CubingChinaLiveRound]
    private let lock = NSLock()
    private var calls = 0
    var personalCalls: Int { lock.withLock { calls } }
    init(values: [CubingChinaLiveResult], rounds: [CubingChinaLiveRound]) { self.values = values; metadata = rounds }
    func rounds(slug: String) async throws -> [CubingChinaLiveRound] { metadata }
    func results(slug: String, key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot { throw CubingChinaLiveError.unsupported }
    func messages(slug: String) async throws -> [CubingChinaLiveMessage] { [] }
    func events(slug: String, viewerID: String) async throws -> CubingChinaLiveConnection { throw CubingChinaLiveError.unsupported }
    func competitorResults(slug: String, number: Int) async throws -> [CubingChinaLiveResult] {
        lock.withLock { calls += 1 }
        return values.filter { $0.competitor?.number == number }
    }
}

@MainActor final class CompetitionRecordIntegrityTests: XCTestCase {
    private func fixture() throws -> CubingChinaLiveSnapshot {
        try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: CubingChinaModernLiveFixtures.beijing).validated()
    }
    func testSelectorRegionalPrecedenceAndOnlyCanonicalOwnPersonalRecord() {
        let own = "2019SHAY01", other = "2019TARA09"
        let mine: (String?, String?, String?) = ("PR", "PR", own)
        XCTAssertEqual(CubingLiveRecordIndicators.selector([mine], ownWCAID: own), "PR")
        XCTAssertNil(CubingLiveRecordIndicators.selector([mine], ownWCAID: other))
        XCTAssertNil(CubingLiveRecordIndicators.selector([mine], ownWCAID: nil))
        XCTAssertNil(CubingLiveRecordIndicators.selector([("PR", nil, nil)], ownWCAID: own))
        for tag in ["NR", "CR", "WR"] {
            XCTAssertEqual(CubingLiveRecordIndicators.selector([mine, (tag, nil, other)], ownWCAID: own), tag)
        }
        XCTAssertEqual(CubingLiveRecordIndicators.selector([mine, ("NR", "CR", other), ("WR", nil, other)], ownWCAID: own), "WR")
        XCTAssertFalse(CubingLiveRecordIndicators.isOwnPR("WR", ownWCAID: own, competitorWCAID: own))
        XCTAssertTrue(CubingLiveRecordIndicators.isOwnPR("PR", ownWCAID: " 2019shay01 ", competitorWCAID: own))
        XCTAssertFalse(CubingLiveRecordIndicators.isOwnPR(nil, ownWCAID: own, competitorWCAID: own))
        XCTAssertFalse(CubingLiveRecordIndicators.isOwnPR("PR", ownWCAID: "Yinzhi Sha", competitorWCAID: own))
    }
    func testVerifiedAssociationRejectsMissingAndAmbiguousProviderIdentity() throws {
        let source = try fixture(), person = try XCTUnwrap(source.results[4].competitor)
        XCTAssertEqual(CubingChinaPersonalRecords.association(ownWCAID: person.wcaId, candidates: [person])?.number, 146)
        let duplicate = CubingChinaLiveResult.Competitor(id: .init(person.id.rawValue + 1), number: 147,
            name: person.name, localName: person.localName, wcaId: person.wcaId, regionIso2: person.regionIso2)
        XCTAssertNil(CubingChinaPersonalRecords.association(ownWCAID: person.wcaId, candidates: [person, duplicate]))
        XCTAssertNil(CubingChinaPersonalRecords.association(ownWCAID: nil, candidates: [person]))
        XCTAssertNil(CubingChinaPersonalRecords.association(ownWCAID: "2020TEST01", candidates: [person]))
    }
    func testOwnPersonalRecordDiscoveredWithoutOpeningAnyRound() async throws {
        let source = try fixture(), own = source.results[4], competitor = try XCTUnwrap(own.competitor)
        let transport = PersonalDiscoveryTransport(values: source.results, rounds: [source.round])
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [source.round])
        let session = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        let extras = CubingChinaLiveExtrasStore()
        XCTAssertNil(session.snapshot)
        await session.discoverPersonalRecords(ownWCAID: competitor.wcaId, candidates: [competitor])
        XCTAssertNil(session.snapshot, "Personal discovery must not select or load the round table")
        XCTAssertEqual(transport.personalCalls, 1)
        XCTAssertEqual(session.roundRecordTags(in: extras, ownWCAID: competitor.wcaId)[source.round.key.selectionID], "PR")
        XCTAssertNil(session.roundRecordTags(in: extras, ownWCAID: nil)[source.round.key.selectionID])
        XCTAssertNil(session.roundRecordTags(in: extras, ownWCAID: "2020TEST01")[source.round.key.selectionID])
        await session.discoverPersonalRecords(ownWCAID: competitor.wcaId, candidates: [competitor])
        XCTAssertEqual(transport.personalCalls, 1, "An unchanged evidence scope must not repeat the personal GET")
    }
    func testPersonalStoreSingleAverageCorrectionAndAuthoritativeEmpty() async throws {
        let source = try fixture(), row = source.results[4], competitor = try XCTUnwrap(row.competitor)
        let store = CubingChinaPersonalRecords()
        await store.load(ownWCAID: competitor.wcaId, candidates: [competitor], rounds: [source.round], evidence: "a") { _ in [row] }
        XCTAssertEqual(store.tag(for: source.round, ownWCAID: competitor.wcaId, evidence: "a"), "PR")
        XCTAssertNil(store.tag(for: source.round, ownWCAID: competitor.wcaId, evidence: "newer"))
        await store.load(ownWCAID: competitor.wcaId, candidates: [competitor], rounds: [source.round], evidence: "b") { _ in [] }
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertNil(store.tag(for: source.round, ownWCAID: competitor.wcaId, evidence: "b"))
    }
    func testAccountSwitchClearsPersonalEvidenceBeforeFetchAndRejectsWrongOwner() async throws {
        let source = try fixture(), row = source.results[4], competitor = try XCTUnwrap(row.competitor)
        let store = CubingChinaPersonalRecords()
        await store.load(ownWCAID: competitor.wcaId, candidates: [competitor], rounds: [source.round], evidence: "a") { _ in [row] }
        await store.load(ownWCAID: "2020TEST01", candidates: [competitor], rounds: [source.round], evidence: "a") { _ in XCTFail("Unmatched identity must not fetch"); return [row] }
        XCTAssertTrue(store.rows.isEmpty)
        await store.load(ownWCAID: nil, candidates: [competitor], rounds: [source.round], evidence: "a") { _ in XCTFail("Signed out"); return [] }
        XCTAssertNil(store.wcaID)
    }
    func testFullResultsRetainOtherCompetitorsExplicitPRIndependentOfSelectors() throws {
        let source = try fixture()
        let row = try XCTUnwrap(source.results.first { $0.competitor?.wcaId == "2019SHAY01" })
        let preview = CubingChinaLivePresentation.preview(row, language: "en")
        XCTAssertEqual(preview.averageRecordTag, "PR")
        XCTAssertFalse(CubingLiveRecordIndicators.isOwnPR(preview.averageRecordTag, ownWCAID: "2020TEST01", competitorWCAID: preview.personWCAID))
        XCTAssertEqual(row.averageIndicator, "PR")
    }
    func testDetailLifetimeHydratesModernSelectorsSynchronouslyAndRetainsTheSameOwners() throws {
        let source = try fixture(), content = CubingChinaLivePresentation.content(
            try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [source.round]), language: "en")
        let transport = PersonalDiscoveryTransport(values: source.results, rounds: [source.round])
        let owner = CompetitionCubingLiveStores()
        let cold = owner.entry(content: content, language: "en", transport: transport)
        XCTAssertNotNil(cold.session.modernSession, "The very first body must not wait for a .task to configure its session")
        XCTAssertEqual(cold.session.roundOptions.map(\.id), [source.round.key.selectionID])
        cold.session.stop(); cold.extras.stop()
        let warm = owner.entry(content: content, language: "en", transport: transport)
        XCTAssertTrue(warm.session === cold.session); XCTAssertTrue(warm.extras === cold.extras)
        XCTAssertEqual(warm.session.roundOptions, cold.session.roundOptions)
        let otherTransport = PersonalDiscoveryTransport(values: source.results, rounds: [source.round])
        let isolated = owner.entry(content: content, language: "en", transport: otherTransport)
        XCTAssertFalse(isolated.session === cold.session, "Different provider transports must not share retained state")
    }
    func testWarmDisconnectedRoundPresentationDoesNotPretendPriorStreamAuthority() async throws {
        let source = try fixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var round = json["round"] as! [String: Any], rules = round["round"] as! [String: Any]
        round["id"] = 9951; round["competitionRoundId"] = 12995; round["eventId"] = "333"; round["roundNumber"] = 1
        rules["id"] = 12995; round["round"] = rules; json["round"] = round; json["results"] = []
        let other = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let transport = FakeCubingChinaTransport(snapshot: source, additional: [other])
        let session = CubingChinaModernLiveSession(bootstrap: try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [source.round, other.round]), transport: transport)
        session.start(); defer { session.stop() }
        for _ in 0..<200 where session.snapshot == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        session.select(source.round.key)
        for _ in 0..<200 where session.snapshot?.round.key != source.round.key { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(session.snapshot?.results, source.results)
        session.stop()
        session.select(other.round.key)
        session.select(source.round.key)
        XCTAssertEqual(session.snapshot?.results, source.results, "Known rows must restore before a new connection or HTTP response")
        XCTAssertFalse(session.hasCurrentSnapshot, "Prior-stream data is presentation only until revalidation")
        let tags = session.roundRecordTags(in: CubingChinaLiveExtrasStore())
        XCTAssertEqual(tags[source.round.key.selectionID], "WR", "Known selector evidence must not blank on a warm return")
    }

    func testRetainedBridgeDoesNotReapplyDeepLinkOrRepublishEquivalentRows() throws {
        let rounds = try JSONDecoder().decode([CubingChinaLiveRound].self, from: CubingChinaUnifiedFixtures.rounds)
        let source = try fixture(), transport = PersonalDiscoveryTransport(values: source.results, rounds: rounds)
        let content = CubingChinaLivePresentation.content(try .make(slug: "Beijing-Autumn-Rivalry-2026", rounds: rounds), language: "en")
        let owner = CompetitionCubingLiveStores()
        let first = owner.entry(content: content, language: "en", transport: transport)
        let initial = try XCTUnwrap(rounds.first?.key.selectionID), chosen = try XCTUnwrap(rounds.last?.key.selectionID)
        XCTAssertNotEqual(initial, chosen)
        first.session.applyInitialRoundOption(initial)
        first.session.selectedRoundOptionID = chosen
        let warm = owner.entry(content: content, language: "en", transport: transport)
        var publications = 0
        let observation = warm.session.$resultRows.dropFirst().sink { _ in publications += 1 }
        warm.session.configure(with: content, language: "en", transport: transport)
        warm.session.applyInitialRoundOption(initial)
        warm.session.configure(with: content, language: "en", transport: transport)
        XCTAssertEqual(warm.session.selectedRoundOptionID, chosen)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(observation) {}
    }

}
