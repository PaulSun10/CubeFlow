import Foundation
import Testing
@testable import CubeFlow

@MainActor
struct WCAExplorePublicDataTests {
    @Test func browseOrderIncludesStatsBetweenRecordsAndHighlights() {
        #expect(ExploreBrowseDestination.allCases == [.competitions, .rankings, .records, .stats, .highlights])
    }

    @Test func rankingsDecodeAndPreserveResultRows() throws {
        let data = Data("""
        {"rankings":[
          {"id":1,"person_id":"2020TEST01","person_name":"First Cuber","country_id":"China","competition_country_id":"China","competition_id":"Test2026","competition_name":"Test Open","start_date":"2026-01-02","event_id":"333","attempts":[313,400,500,600,700],"best":313,"average":500,"value":313},
          {"id":2,"person_id":"2020TEST01","person_name":"First Cuber","country_id":"China","competition_country_id":"China","competition_id":"Other2026","competition_name":"Other Open","start_date":"2026-02-02","event_id":"333","attempts":[313],"best":313,"average":0,"value":313}
        ],"timestamp":"2026-09-22"}
        """.utf8)
        let response = try JSONDecoder().decode(WCARankingsResponse.self, from: data)
        #expect(response.rankings.count == 2)
        #expect(response.rankings.map(\.personId) == ["2020TEST01", "2020TEST01"])
        #expect(WCAExplorePublicDataService.rankedRows(response.rankings).map(\.rank) == [1, 1])
    }

    @Test func rankingAndRecordQueriesPreserveAllFilterSemantics() throws {
        let rankingURL = try #require(WCAExplorePublicDataService.rankingsURL(WCARankingsQuery(
            eventID: "333oh", type: .average, region: .country("HK"), gender: .female, show: .results
        )))
        let rankingItems = try #require(URLComponents(url: rankingURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(rankingURL.path.hasSuffix("/333oh/average"))
        #expect(rankingItems.contains(URLQueryItem(name: "region", value: "HK")))
        #expect(rankingItems.contains(URLQueryItem(name: "show", value: "100 results")))
        #expect(rankingItems.contains(URLQueryItem(name: "gender", value: "Female")))

        let byRegionURL = try #require(WCAExplorePublicDataService.rankingsURL(WCARankingsQuery(
            eventID: "333", type: .single, region: .continent(.africa), gender: .all, show: .byRegion
        )))
        let byRegionItems = try #require(URLComponents(url: byRegionURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(byRegionItems.contains(URLQueryItem(name: "region", value: "world")))

        let recordsURL = try #require(WCAExplorePublicDataService.recordsURL(WCARecordsQuery(
            region: .continent(.europe), gender: .male, show: .history
        )))
        let recordItems = try #require(URLComponents(url: recordsURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(recordItems.contains(URLQueryItem(name: "region", value: "_Europe")))
        #expect(recordItems.contains(URLQueryItem(name: "show", value: "history")))
        #expect(recordItems.contains(URLQueryItem(name: "gender", value: "Male")))
    }

    @Test func rankingTiesUseCompetitionRanks() {
        let ranked = WCAExplorePublicDataService.rankedRows([
            row(id: 1, value: 313), row(id: 2, value: 313), row(id: 3, value: 400)
        ])
        #expect(ranked.map(\.rank) == [1, 1, 3])
    }

    @Test func officialRecordsFallbackRetainsLocallySelectedEventAndLayout() throws {
        for show in WCARecordsShow.allCases {
            let query = WCARecordsQuery(region: .country("HK"), gender: .female, show: show)
            let url = try #require(WCAExplorePublicDataService.recordsWebsiteURL(query, eventID: "sq1"))
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(url.path == "/results/records")
            #expect(items.contains(URLQueryItem(name: "region", value: "HK")))
            #expect(items.contains(URLQueryItem(name: "gender", value: "Female")))
            #expect(items.contains(URLQueryItem(name: "show", value: show.rawValue)))
            #expect(items.contains(URLQueryItem(name: "event_id", value: "sq1")))
        }
    }

    @Test func byRegionIncludesWorldContinentCountryAndTies() {
        let rows = [
            row(id: 1, person: "A", country: "China", value: 300),
            row(id: 2, person: "B", country: "China", value: 300),
            row(id: 3, person: "C", country: "Japan", value: 320)
        ]
        let countries = [
            CompetitionRecognizedCountry(code: "CN", wcaName: "China"),
            CompetitionRecognizedCountry(code: "JP", wcaName: "Japan")
        ]
        let groups = WCAExplorePublicDataService.regionalBests(
            from: rows,
            selectedRegion: .country("CN"),
            countries: countries
        )
        #expect(groups.first?.results.map(\.id) == [1, 2])
        #expect(groups.contains { group in
            if case .continent(.asia) = group.scope { return group.results.map(\.id) == [1, 2] }
            return false
        })
        #expect(groups.last?.results.map(\.id) == [1, 2])
    }

    @Test func recordPresentationsUseCurrentAndHistoryLayouts() {
        let records = [
            "333": [row(id: 1, event: "333", value: 313, type: "single"),
                    row(id: 2, event: "333", value: 500, type: "average")],
            "222": [row(id: 3, event: "222", value: 47, type: "single")]
        ]
        #expect(WCAExplorePublicDataService.recordSections(records, show: .mixed, eventID: "333").count == 1)
        #expect(WCAExplorePublicDataService.recordSections(records, show: .slim, eventID: nil).count == 2)
        let separate = WCAExplorePublicDataService.recordSections(records, show: .separate, eventID: nil)
        #expect(separate.map(\.id) == ["type-single", "type-average"])
        let mixedHistory = WCAExplorePublicDataService.recordSections(records, show: .mixedHistory, eventID: nil)
        #expect(mixedHistory.count == 1)
        #expect(mixedHistory.first?.rows.count == 3)
    }

    @Test func recentLiveRecordsDecodeInSourceOrderAndCreateOnlyRealWRHero() throws {
        let data = Data("""
        [
          {"id":"r1","tag":"NR","type":"single","attemptResult":500,"result":{"id":"result-1","person":{"id":"1","wcaId":"2020TEST01","name":"National Cuber","country":{"iso2":"CN","name":"China"}},"round":{"id":"round-1","competitionEvent":{"event":{"id":"333","name":"3x3x3 Cube"},"competition":{"id":"1","wcaId":"NationalOpen2026","name":"National Open"}}}}},
          {"id":"r2","tag":"WR","type":"average","attemptResult":600,"result":{"id":"result-2","person":{"id":"2","wcaId":"2020TEST02","name":"World Cuber","country":{"iso2":"US","name":"United States"}},"round":{"id":"round-2","competitionEvent":{"event":{"id":"333","name":"3x3x3 Cube"},"competition":{"id":"2","wcaId":"WorldOpen2026","name":"World Open"}}}}},
          {"id":"r3","tag":"ER","type":"single","attemptResult":700,"result":{"id":"result-3","person":{"id":"3","wcaId":"2020TEST03","name":"Other Cuber","country":{"iso2":"GB","name":"United Kingdom"}},"round":{"id":"round-3","competitionEvent":{"event":{"id":"333","name":"3x3x3 Cube"},"competition":{"id":"3","wcaId":"OtherOpen2026","name":"Other Open"}}}}}
        ]
        """.utf8)
        let records = try JSONDecoder().decode([WCARecentRecord].self, from: data)
        #expect(records.map(\.id) == ["r1", "r2", "r3"])
        let candidates = WCAExplorePublicDataService.recentRecordsCandidate(records, language: "en")
        #expect(candidates.first?.items.map(\.id) == ["recent-record.r1", "recent-record.r2", "recent-record.r3"])
        #expect(candidates.first?.items.last?.result == nil)
        #expect(candidates.filter { $0.heroEligibility != nil }.map(\.id) == ["records.recent-world"])
        #expect(candidates.last?.items.first?.content.destination == .records)
        let localized = WCAExplorePublicDataService.recentRecordsCandidate(records, language: "zh-Hans")
        #expect(localized.first?.items.first?.title.contains("3x3x3 Cube") == false)
        #expect(localized.first?.items.first?.subtitle.contains("China") == false)
        if case .recentRecord(_, let competitionID, let roundID, let personID, let personWCAID) =
            candidates.first?.items.first?.content {
            #expect(competitionID == "NationalOpen2026")
            #expect(roundID == "round-1")
            #expect(personID == "1")
            #expect(personWCAID == "2020TEST01")
        } else {
            Issue.record("Recent record did not preserve its typed Live destination")
        }
    }

    @Test func resultFormattingCoversTimedFewestMovesAndMultiBlind() {
        #expect(WCAExplorePublicDataService.formatResult(313, eventID: "333") == "3.13")
        #expect(WCAExplorePublicDataService.formatResult(2534, eventID: "333fm") == "25.34")
        #expect(WCAExplorePublicDataService.formatResult(980243002, eventID: "333mbf") == "3/5 40:30")
        #expect(WCAExplorePublicDataService.formatResult(1960502430, eventID: "333mbo") == "3/5 40:30")
        #expect(WCAExplorePublicDataService.formatResult(-1, eventID: "333") == "DNF")
        #expect(WCAExplorePublicDataService.formatResult(-1, eventID: "333mbf") == "DNF")
        #expect(WCAExplorePublicDataService.formatResult(-2, eventID: "333mbf") == "DNS")
    }

    @Test func homeAndLiveRecordsResolveTheSameRoundCompetitorResult() throws {
        let expected = liveResult(id: "result-1", personID: "live-person", personWCAID: "2020TEST01")
        let round = liveRound(results: [expected, liveResult(id: "result-2", personID: "other", personWCAID: nil)])
        let homeLink = CompetitionWCALiveResultDeepLink(
            roundID: round.id,
            personID: "live-person",
            personWCAID: "2020TEST01"
        )
        let liveRecord = CompetitionWCALiveRecord(
            id: "record-1",
            tag: "WR",
            type: "single",
            attemptResult: 313,
            eventID: "333",
            eventName: "3x3x3 Cube",
            roundID: round.id,
            personID: "live-person",
            personWCAID: "2020TEST01",
            personName: "Cuber",
            countryName: "China"
        )

        #expect(homeLink.result(in: round)?.id == expected.id)
        #expect(liveRecord.resultDeepLink.result(in: round)?.id == expected.id)

        let wcaFallback = CompetitionWCALiveResultDeepLink(
            roundID: round.id,
            personID: "stale-live-id",
            personWCAID: "2020TEST01"
        )
        #expect(wcaFallback.result(in: round)?.id == expected.id)
        #expect(CompetitionWCALiveResultDeepLink(
            roundID: "missing-round",
            personID: "live-person",
            personWCAID: "2020TEST01"
        ).result(in: round) == nil)
    }

    @Test func recentRecordLocalizationKeysExistInEveryExploreLocale() throws {
        let requiredKeys: Set<String> = [
            "explore.public.recent_records",
            "explore.public.recent_record_title",
            "explore.public.recent_record_person",
            "explore.public.sentence_single",
            "explore.public.sentence_average"
        ]
        let localizations = [
            "ar", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "pl",
            "pt-BR", "pt-PT", "ru", "th", "tr", "vi", "zh-Hans", "zh-Hant"
        ]

        for localization in localizations {
            let path = try #require(Bundle.main.path(
                forResource: "ExplorePublicData",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: localization
            ))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let table = try #require(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            )
            #expect(requiredKeys.isSubset(of: Set(table.keys)), "Missing Recent Records key in \(localization)")
        }
    }

    private func liveResult(
        id: String,
        personID: String,
        personWCAID: String?
    ) -> CompetitionWCALiveResultPreview {
        CompetitionWCALiveResultPreview(
            id: id,
            ranking: 1,
            personID: personID,
            personWCAID: personWCAID,
            name: "Cuber",
            region: "China",
            attempts: [313],
            best: 313,
            average: 0,
            isAdvancing: nil,
            isAdvancingQuestionable: nil,
            singleRecordTag: "WR",
            averageRecordTag: nil
        )
    }

    private func liveRound(results: [CompetitionWCALiveResultPreview]) -> CompetitionWCALiveRound {
        CompetitionWCALiveRound(
            id: "round-1",
            eventID: "333",
            eventName: "3x3x3 Cube",
            roundName: "Final",
            number: 1,
            formatID: "1",
            numberOfAttempts: 1,
            sortBy: "best",
            isFinished: true,
            advancementType: nil,
            advancementLevel: nil,
            isActive: false,
            isOpen: false,
            results: results
        )
    }

    private func row(
        id: Int,
        person: String = "Cuber",
        country: String = "China",
        event: String = "333",
        value: Int,
        type: String? = nil
    ) -> WCAPublicResult {
        WCAPublicResult(
            id: id,
            personId: "2020TEST\(String(format: "%02d", id))",
            personName: person,
            countryId: country,
            competitionCountryId: country,
            competitionId: "TestOpen2026",
            competitionName: "Test Open",
            startDate: "2026-01-0\(min(id, 9))",
            eventId: event,
            attempts: [value],
            best: value,
            average: type == "average" ? value : 0,
            value: value,
            type: type,
            regionalSingleRecord: type == "single" ? "WR" : nil,
            regionalAverageRecord: type == "average" ? "WR" : nil
        )
    }
}
