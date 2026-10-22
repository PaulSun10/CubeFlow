import XCTest
@testable import CubeFlow

private actor SectionLoadCounter {
    private(set) var starts = 0
    private(set) var cancellations = 0
    func start() { starts += 1 }
    func cancel() { cancellations += 1 }
}

@MainActor
final class CompetitionSectionLoadingTests: XCTestCase {
    func testChinaCompetitorsStartsBeforeInfoAndStillOwnsLoadingCompletion() {
        let initial = CompetitionSectionLoadingPlan.initialResources(china: true, explicitLive: false)
        XCTAssertEqual(initial.filter { $0 == .competitors }.count, 1)
        XCTAssertFalse(initial.contains(.tickets), "Ticket availability still requires provider evidence")
        XCTAssertFalse(initial.contains(.live), "Published archives must not start implicit Live")
        var state = CompetitionLoadingLifecycle()
        _ = state.begin(identity: "china-en", resources: initial, publication: false, refresh: false)
        XCTAssertTrue(state.detailResources.contains(.competitors), "Competitors cannot wait for Info")
        for resource in initial where resource != .competitors { state.finish(.detail(resource)) }
        XCTAssertTrue(state.isLoading, "Keep the indicator active for real pending work")
        state.finish(.detail(.competitors))
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(CompetitionSectionLoadingPlan.initialResources(china: false, explicitLive: false).contains(.competitors))
    }

    func testWholeSessionRemainsLoadingUntilPublicationAndScramblesFinish() {
        var state = CompetitionLoadingLifecycle()
        let run = state.begin(identity: "one-en", resources: [.info, .schedule], publication: true, refresh: false)
        state.finish(.detail(.info))
        XCTAssertFalse(state.detailResources.contains(.info), "Info can render while other sections load")
        state.finish(.detail(.schedule))
        XCTAssertTrue(state.isLoading, "Publication belongs to the same session")
        state.schedule(.scrambles)
        state.finish(.publication)
        XCTAssertTrue(state.isLoading, "The indicator must not end before gated Scrambles")
        state.finish(.scrambles)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.accepts(run, identity: "one-en"))
    }

    func testRefreshOwnsEverySectionAndRejectsSupersededSession() {
        var state = CompetitionLoadingLifecycle()
        let old = state.begin(identity: "one-en", resources: [.info], publication: true, refresh: false)
        let resources = CompetitionSectionLoadingPlan.initialResources(china: true, explicitLive: true)
        let fresh = state.begin(identity: "one-en", resources: resources, publication: true, refresh: true)
        state.schedule(.detail(.competitors))
        XCTAssertTrue(state.isRefresh)
        XCTAssertFalse(state.accepts(old, identity: "one-en"))
        XCTAssertFalse(state.accepts(fresh, identity: "another-en"))
        for resource in resources + [.competitors] { state.finish(.detail(resource)) }
        XCTAssertTrue(state.isLoading)
        state.finish(.publication)
        XCTAssertFalse(state.isLoading)
    }

    private func content(_ name: String) -> CompetitionDetailContent {
        var value = CompetitionDetailContent.empty
        value.localizedName = name
        return value
    }

    func testSharedResourceCoalescesAndReusesParsedResult() async {
        let store = CompetitionSectionStore(), counter = SectionLoadCounter(), expected = content("Info")
        let loader: @Sendable () async -> CompetitionDetailContent = {
            await counter.start()
            try? await Task.sleep(nanoseconds: 30_000_000)
            return expected
        }
        async let first = store.content(key: "one", lifetime: 60, loader: loader)
        async let second = store.content(key: "one", lifetime: 60, loader: loader)
        let values = await [first, second]
        XCTAssertEqual(values, [expected, expected])
        let warm = await store.content(key: "one", lifetime: 60, loader: loader)
        XCTAssertEqual(warm, expected)
        let starts = await counter.starts
        XCTAssertEqual(starts, 1)
    }

    func testRefreshAndIdentityKeysDoNotReturnOtherCompetitionOrLocale() async {
        let store = CompetitionSectionStore()
        let old = content("old"), fresh = content("fresh"), other = content("other")
        _ = await store.content(key: "a-en", lifetime: 60) { old }
        let refreshed = await store.content(key: "a-en", lifetime: 60, refresh: true) { fresh }
        let separate = await store.content(key: "a-zh", lifetime: 60) { other }
        XCTAssertEqual(refreshed, fresh); XCTAssertEqual(separate, other)
        let expired = await store.content(key: "a-en", lifetime: 0) { other }
        XCTAssertEqual(expired, other)
    }

    func testFailedResourceIsNotCached() async {
        let store = CompetitionSectionStore(), expected = content("retry")
        _ = await store.content(key: "one", lifetime: 60) { .empty }
        let retry = await store.content(key: "one", lifetime: 60) { expected }
        XCTAssertEqual(retry, expected)
    }

    func testLastDepartingConsumerCancelsUnderlyingWork() async throws {
        let store = CompetitionSectionStore(), counter = SectionLoadCounter(), expected = content("late")
        let consumer = Task {
            await store.content(key: "cancel", lifetime: 60) {
                await counter.start()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { await counter.cancel() }
                return expected
            }
        }
        while await counter.starts == 0 { await Task.yield() }
        consumer.cancel()
        let cancelled = await consumer.value
        XCTAssertEqual(cancelled, .empty)
        let cancellations = await counter.cancellations
        XCTAssertEqual(cancellations, 1)
        let replacement = content("replacement")
        let next = await store.content(key: "cancel", lifetime: 60) { replacement }
        XCTAssertEqual(next, replacement, "Cancelled work must not poison the next session's cache")
    }

    func testOneDepartingConsumerDoesNotCancelAnother() async throws {
        let store = CompetitionSectionStore(), counter = SectionLoadCounter(), expected = content("shared")
        let loader: @Sendable () async -> CompetitionDetailContent = {
            await counter.start()
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { await counter.cancel() }
            return expected
        }
        let first = Task { await store.content(key: "shared", lifetime: 60, loader: loader) }
        while await counter.starts == 0 { await Task.yield() }
        let second = Task { await store.content(key: "shared", lifetime: 60, loader: loader) }
        try await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        let value = await second.value
        _ = await first.value
        XCTAssertEqual(value, expected)
        let cancellations = await counter.cancellations
        XCTAssertEqual(cancellations, 0)
    }

    func testIndependentSectionsMergeInEitherCompletionOrder() {
        var info = content("Full Info")
        info.hasCompetitorsLink = true
        var competitors = CompetitionDetailContent.empty
        competitors.competitorsCount = 42
        var live = CompetitionDetailContent.empty
        live.liveAvailability = .available
        live.liveURLOverride = URL(string: "https://live.worldcubeassociation.org/competitions/42")
        let first = CompetitionDetailContent.empty.merging(info, resource: .info)
            .merging(competitors, resource: .competitors).merging(live, resource: .live)
        let reverse = CompetitionDetailContent.empty.merging(live, resource: .live)
            .merging(competitors, resource: .competitors).merging(info, resource: .info)
        XCTAssertEqual(first, reverse)
        XCTAssertEqual(reverse.localizedName, "Full Info")
        XCTAssertEqual(reverse.competitorsCount, 42)
        XCTAssertTrue(reverse.hasCompetitorsLink)
        XCTAssertEqual(reverse.liveAvailability, .available)
    }

    func testRichDocumentWorkerRetainsSemanticsAndResolvesRootLinks() async throws {
        let store = CompetitionRichDocumentStore()
        let html = "<h2>Full Info</h2><p><a href='/regulations'>Rules</a></p><table><tr><td>Cutoff</td><td>2:00</td></tr></table>"
        let elements = await store.elements(html: html, baseURL: URL(string: "https://www.worldcubeassociation.org/competitions/Test2026"))
        XCTAssertEqual(elements.count, 3)
        guard case .linkedText(let runs) = elements[1].kind else { return XCTFail("Lost rich link") }
        XCTAssertEqual(runs.first?.url?.absoluteString, "https://www.worldcubeassociation.org/regulations")
        guard case .table(let table) = elements[2].kind else { return XCTFail("Lost table") }
        XCTAssertEqual(table.rows, [["Cutoff", "2:00"]])
        let cached = await store.elements(html: html, baseURL: URL(string: "https://www.worldcubeassociation.org/competitions/Test2026"))
        XCTAssertEqual(cached.count, elements.count)
    }

    func testScheduleColorMatchesRoundAndGroupNotAnotherEventOrRoundTen() {
        let start = Date(timeIntervalSince1970: 0)
        func activity(_ code: String, _ color: String?, _ offset: Double = 0) -> CompetitionWCALiveActivity {
            CompetitionWCALiveActivity(id: code, activityCode: code, name: code,
                startTime: start.addingTimeInterval(offset), endTime: start.addingTimeInterval(offset + 60), roomColorHex: color)
        }
        let activities = [activity("222-r1", "#123456"), activity("333-r10", "#abcdef"),
            activity("333-r1-g2", "#00ff00", 60), activity("333-r1-g1", "#cc0022")]
        XCTAssertEqual(CompetitionLiveScheduleColor.hex(activities: activities, event: "333", round: 1), "#CC0022")
        XCTAssertNil(CompetitionLiveScheduleColor.hex(activities: activities, event: "444", round: 1))
        XCTAssertNil(CompetitionLiveScheduleColor.validated("not-a-color"))
    }

    func testExtraNumberAndChineseMeanLabel() throws {
        for extra in [false, true] {
            let row = "{\"id\":1,\"competition_id\":\"Test2026\",\"event_id\":\"333\",\"round_type_id\":\"f\",\"group_id\":\"A\",\"is_extra\":\(extra),\"scramble_num\":2,\"scramble\":\"R U\"}"
            let scramble = try JSONDecoder().decode(PublishedCompetitionScramble.self, from: Data(row.utf8))
            XCTAssertEqual(scramble.displayNumber, extra ? "E2" : "2")
        }
        XCTAssertEqual(PublishedCompetitionStrings.text("mean", "zh-Hans"), "平均")
        XCTAssertEqual(PublishedCompetitionStrings.text("mean", "zh-Hant"), "平均")
    }

    func testPublishedPresentationUsesCanonicalRowsWithoutLiveIDsOrAdvancement() throws {
        let bytes = Data(#"[{"id":1,"competition_id":"Test2026","event_id":"333","round_type_id":"f","format_id":"a","pos":1,"name":"Alice Test","wca_id":"2020TEST01","country_iso2":"CN","best":900,"average":1000,"attempts":[900,1000,1100,1200,1300],"regional_single_record":"AS","regional_average_record":null}]"#.utf8)
        let rows = try PublishedCompetitionService.decodeResults(bytes, competitionID: "Test2026")
        let data = PublishedCompetitionData(competitionID: "Test2026", results: rows)
        let round = PublishedCompetitionPresentation.round(try XCTUnwrap(data.rounds.first), language: "en")
        let result = try XCTUnwrap(round.results.first)
        XCTAssertNil(result.personID)
        XCTAssertEqual(result.personWCAID, "2020TEST01")
        XCTAssertNil(result.isAdvancing)
        XCTAssertFalse(round.isOpen); XCTAssertFalse(round.isActive)
        XCTAssertEqual(result.singleRecordTag, "CR")
        let competitor = try XCTUnwrap(PublishedCompetitionPresentation.competitor("2020TEST01", data: data, language: "en"))
        XCTAssertEqual(competitor.wcaID, "2020TEST01")
        XCTAssertEqual(competitor.results.first?.attempts, rows.first?.performedAttempts)
        XCTAssertEqual(competitor.results.first?.average, 1000)
    }

    func testResultCardAllResultsAndCloseUseTheSuppliedSource() async throws {
        let card = CompetitionResultCardState()
        let round = CompetitionWCALiveRound(id: "published-test", eventID: "333", eventName: "3x3",
            roundName: "Final", number: nil, formatID: "a", numberOfAttempts: 5, sortBy: "average",
            isFinished: true, advancementType: nil, advancementLevel: nil, isActive: false, isOpen: false, results: [])
        let row = CompetitionWCALiveResultPreview(id: "published-1", ranking: 1, personID: nil,
            personWCAID: "2020TEST01", name: "Alice Test", region: "China", attempts: [900], best: 900, average: 1000,
            isAdvancing: nil, isAdvancingQuestionable: nil, singleRecordTag: nil, averageRecordTag: nil)
        let competitor = CompetitionWCALiveCompetitorContent(id: "2020TEST01", name: row.name,
            wcaID: "2020TEST01", countryISO2: "CN", results: [])
        card.present(result: row, round: round, isPublished: true, loader: { _ in competitor })
        card.loadAllResults()
        while card.isLoadingCompetitorContent { await Task.yield() }
        XCTAssertEqual(card.selectedCompetitorContent, competitor)
        XCTAssertTrue(card.selection?.isPublished == true)
        card.close()
        XCTAssertNil(card.selection); XCTAssertNil(card.selectedCompetitorContent)
    }

    func testPublishedRequestPoolCancelsOnlyAfterLastConsumerLeaves() async throws {
        let pool = CompetitionRequestPool<Int>(), counter = SectionLoadCounter()
        let request = Task {
            try await pool.value(key: "scrambles") {
                await counter.start()
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { await counter.cancel(); throw error }
                return 42
            }
        }
        while await counter.starts == 0 { await Task.yield() }
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled consumer must not receive a value") }
        catch { }
        let cancelled = await counter.cancellations
        XCTAssertEqual(cancelled, 1)
        let fresh = try await pool.value(key: "scrambles") { 7 }
        XCTAssertEqual(fresh, 7)
    }

    func testLoadingPlanDownloadsOnlyAvailableHistoricalSections() {
        XCTAssertEqual(CompetitionSectionLoadingPlan.historicalResources(china: true, publicationChecked: true,
            lifecycle: .published, hasRegistration: true, hasCompetitors: true), [.registration, .competitors])
        XCTAssertTrue(CompetitionSectionLoadingPlan.historicalResources(china: false, publicationChecked: true,
            lifecycle: .published, hasRegistration: true, hasCompetitors: true).isEmpty)
        XCTAssertTrue(CompetitionSectionLoadingPlan.historicalResources(china: false, publicationChecked: false,
            lifecycle: .loading, hasRegistration: true, hasCompetitors: true).isEmpty)
        XCTAssertEqual(CompetitionSectionLoadingPlan.historicalResources(china: false, publicationChecked: true,
            lifecycle: .unpublished, hasRegistration: false, hasCompetitors: true), [.competitors])
    }

    func testExplicitLiveArchiveStartsWithInfoWithoutWaitingForPublication() {
        for china in [false, true] {
            let normal = CompetitionSectionLoadingPlan.initialResources(china: china, explicitLive: false)
            let explicit = CompetitionSectionLoadingPlan.initialResources(china: china, explicitLive: true)
            XCTAssertFalse(normal.contains(.live))
            XCTAssertEqual(explicit, normal + [.live])
            XCTAssertEqual(explicit.filter { $0 == .live }.count, 1)
        }
    }
}
