import SwiftUI
import XCTest
@testable import CubeFlow

@MainActor
final class CompetitionRefinementTests: XCTestCase {
    private func ticket(reason: String?) -> CubingChinaTicket {
        CubingChinaTicket(id: 1, name: "Fixture", description: nil, feeCents: 6000,
            validDates: ["2026-10-01"], saleStart: nil, saleEnd: "2026-09-30T16:00:00Z",
            purchaseLimit: 2, competitorsOnly: true, unavailableReason: reason)
    }

    func testSharedTicketStatusUsesOnlyUnanimousOfficialReasons() {
        XCTAssertEqual(CubingChinaTicketPresentation.commonUnavailableReason(
            [ticket(reason: "sale-ended"), ticket(reason: "sale-ended")]), "sale-ended")
        XCTAssertNil(CubingChinaTicketPresentation.commonUnavailableReason([]))
        XCTAssertNil(CubingChinaTicketPresentation.commonUnavailableReason([ticket(reason: nil)]),
            "Past sale dates do not establish an official availability reason")
        XCTAssertNil(CubingChinaTicketPresentation.commonUnavailableReason([ticket(reason: "")]))
        XCTAssertNil(CubingChinaTicketPresentation.commonUnavailableReason(
            [ticket(reason: "sale-ended"), ticket(reason: "not-on-sale")]))
        XCTAssertNil(CubingChinaTicketPresentation.commonUnavailableReason(
            [ticket(reason: "sale-ended"), ticket(reason: nil)]))
    }

    func testTicketValidityDatesKeepTheirCalendarDayInBothTimeZonesAndLocalize() throws {
        for identifier in ["Asia/Shanghai", "America/Los_Angeles"] {
            let zone = try XCTUnwrap(TimeZone(identifier: identifier))
            XCTAssertEqual(CubingChinaTicketPresentation.validDate("2026-10-01", language: "en_US", timeZone: zone),
                "Oct 1, 2026")
            XCTAssertTrue(CubingChinaTicketPresentation.validDate("2026-10-01", language: "zh-Hans", timeZone: zone)
                .contains("10"))
        }
        XCTAssertEqual(CubingChinaTicketPresentation.validDate("2026-02-30", language: "en"), "2026-02-30")
        XCTAssertEqual(CubingChinaTicketPresentation.validDate("unknown", language: "en"), "unknown")
        XCTAssertEqual(PublishedCompetitionStrings.text("tickets.details", "en"), "Ticket details")
        XCTAssertEqual(PublishedCompetitionStrings.text("tickets.details", "zh-Hans"), "入场券详情")
        XCTAssertEqual(PublishedCompetitionStrings.text("tickets.details", "zh-Hant"), "入場券詳情")
    }

    func testLoadingStageNamesOnlyCurrentlyPendingWorkWithoutInventingATotal() {
        var state = CompetitionLoadingLifecycle()
        _ = state.begin(identity: "fixture-en", resources: [.info, .competitors], publication: true, refresh: false)
        XCTAssertEqual(CompetitionLoadingPresentation.title(state.currentWork, language: "en", cubingChina: true), "Loading About")
        state.finish(.detail(.info))
        XCTAssertEqual(CompetitionLoadingPresentation.title(state.currentWork, language: "en", cubingChina: true), "Checking results")
        state.schedule(.scrambles)
        state.finish(.publication)
        XCTAssertEqual(CompetitionLoadingPresentation.title(state.currentWork, language: "en", cubingChina: true), "Loading Scrambles")
        state.finish(.scrambles)
        XCTAssertEqual(state.currentWork, .detail(.competitors))
        state.finish(.detail(.competitors))
        XCTAssertEqual(CompetitionLoadingPresentation.title(state.currentWork, language: "en", cubingChina: true), "Not Loading")
        _ = state.begin(identity: "other-en", resources: [.schedule], publication: false, refresh: true)
        XCTAssertEqual(state.currentWork, .detail(.schedule))
        state.finishSession()
        XCTAssertNil(state.currentWork)
    }

    func testCutoffRoundTitlesUseOfficialNamesWithoutCombinedSuffix() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            for (cutoff, full) in [("c", "f"), ("d", "1"), ("e", "2"), ("g", "3"), ("h", "0")] {
                XCTAssertEqual(PublishedCompetitionStrings.round(cutoff, language: language),
                    PublishedCompetitionStrings.round(full, language: language))
            }
        }
    }

    func testPublishedChinaInfoOrderPlacesCompetitorsBeforeRegisterAndTicketsLast() {
        XCTAssertEqual(CompetitionDetailNavigationPolicy.infoSections(lifecycle: .published, cubingChina: true,
            language: "en", showTickets: true).map(\.rawValue),
            ["info", "rules", "schedule", "travel", "competitors", "register", "custom-spectator-ticket"])
        XCTAssertTrue(CompetitionDetailNavigationPolicy.infoSections(lifecycle: .published, cubingChina: false,
            language: "en", showTickets: true).isEmpty)
    }

    func testOfficialSaleEndedReasonAndZeroLimitDoNotBecomeUnavailableOrAZeroPurchaseLimit() throws {
        // Observed Beijing public ticket fields: configured on-sale, but actually sale-ended.
        let html = #"<script id="__NUXT_DATA__">[{"id":1,"name":2,"fee":3,"validDates":4,"purchaseLimit":5,"unavailableReason":6,"status":7,"saleEndAt":8},38,"One-day ticket",6000,[],0,"sale-ended","on-sale","2026-09-30T16:00:00.000Z"]</script>"#
        let ticket = try XCTUnwrap(CubingChinaTicket.parse(html: html, language: "en").first)
        XCTAssertNil(ticket.purchaseLimit)
        XCTAssertEqual(ticket.unavailableReason, "sale-ended")
        XCTAssertEqual(PublishedCompetitionStrings.text("tickets.status.sale-ended", "en"), "Sales have ended")
        XCTAssertEqual(PublishedCompetitionStrings.text("tickets.status.sale-ended", "zh-Hans"), "已停售")
        XCTAssertEqual(PublishedCompetitionStrings.text("tickets.status.sale-ended", "zh-Hant"), "已停售")
        XCTAssertFalse(PublishedCompetitionStrings.text("tickets.unavailable", "en").contains("unavailable"))
    }

    func testKnownChinaResourcesJoinTheInitialSessionWithoutInventingInternationalSections() {
        let china = CompetitionSectionLoadingPlan.initialResources(china: true, explicitLive: false,
            knownTickets: true)
        XCTAssertTrue(china.contains(.competitors) && china.contains(.tickets))
        XCTAssertEqual(china.filter { $0 == .registration }.count, 1)
        XCTAssertFalse(china.contains(.live))
        let international = CompetitionSectionLoadingPlan.initialResources(china: false, explicitLive: false,
            knownTickets: true)
        XCTAssertEqual(international, [.info, .schedule])
    }
    private func row(_ id: Int, event: String = "333", round: String = "1", person: String = "2020TEST01",
                     single: String = "", average: String = "") throws -> PublishedCompetitionResult {
        let object: [String: Any] = ["id": id, "competition_id": "Fixture2026", "event_id": event,
            "round_type_id": round, "format_id": "a", "pos": 1, "name": "Fixture Cuber", "wca_id": person,
            "country_iso2": "CN", "best": 800, "average": 1000, "attempts": [800, 1000, 900, 1000, 1200],
            "regional_single_record": single, "regional_average_record": average]
        return try JSONDecoder().decode(PublishedCompetitionResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testSelectorRecordPriorityIsOfficialAndScopedToEventAndRound() throws {
        let data = try PublishedCompetitionData(competitionID: "Fixture2026", results: [
            row(1, single: "NR"), row(2, average: "AS"), row(3, round: "f", single: "WR"),
            row(4, event: "222", single: "PB"), row(5, event: "444", average: "NR")])
        XCTAssertEqual(data.eventRecordTags, ["333": "WR", "444": "NR"])
        XCTAssertEqual(data.roundRecordTags, ["333|1": "CR", "333|f": "WR", "444|1": "NR"])
        XCTAssertNil(data.eventRecordTags["222"], "Fast times or PB labels cannot establish official records")
    }

    func testPublishedAdvancementRequiresNextRoundParticipationNotRank() throws {
        let data = try PublishedCompetitionData(competitionID: "Fixture2026", results: [row(1),
            row(2, person: "2020TEST02"), row(3, round: "f"), row(4, event: "222", round: "f", person: "2020TEST02")])
        let first = try XCTUnwrap(data.rounds(for: "333").first)
        let previews = PublishedCompetitionPresentation.round(first, language: "en", data: data).results
        XCTAssertEqual(previews.first?.isAdvancing, true)
        XCTAssertNil(previews.last?.isAdvancing, "A missing next-round result does not prove elimination")
        XCTAssertTrue(previews.allSatisfy { $0.personID == nil && $0.isAdvancingQuestionable == nil })
        XCTAssertTrue(data.confirmedAdvancingPeople(from: try XCTUnwrap(data.finals.first)).isEmpty)
    }

    func testTicketAvailabilityDoesNotConfuseVenueAdmissionWithSpectatorSales() {
        XCTAssertFalse(CubingChinaTicket.isAvailable(competition: ["entryTicket": true, "showTickets": false]))
        XCTAssertFalse(CubingChinaTicket.isAvailable(competition: ["entryTicket": true]))
        XCTAssertTrue(CubingChinaTicket.isAvailable(competition: ["showTickets": true]))
        XCTAssertFalse(CubingChinaTicket.isAvailable(competition: nil))
        let ticket = CompetitionDetailTab.spectatorTicket(language: "en")
        XCTAssertTrue(CompetitionDetailNavigationPolicy.tabs(lifecycle: .unpublished, cubingChina: true,
            showLive: false, language: "en", showTickets: true).contains(ticket))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.tabs(lifecycle: .published, cubingChina: true,
            showLive: false, language: "en", showTickets: true).contains(ticket))
        XCTAssertTrue(CompetitionDetailNavigationPolicy.infoSections(lifecycle: .published, cubingChina: true,
            language: "en", showTickets: true).contains(ticket))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.tabs(lifecycle: .unpublished, cubingChina: false,
            showLive: false, language: "en", showTickets: true).contains(ticket))
        XCTAssertEqual(CubingChinaTicket.website(slug: "Example-2026")?.absoluteString,
            "https://cubing.com/competition/Example-2026/ticket")
        XCTAssertNil(CubingChinaTicket.website(slug: "../../other"))
    }

    func testPublicTicketSSRRetainsCentsDatesAndPurchaseRestrictions() throws {
        let html = #"<script id="__NUXT_DATA__">[{"id":1,"name":2,"fee":3,"validDates":4,"competitorsOnly":6,"purchaseLimit":7},31,"Day pass",6000,[5],"2026-02-06",true,2]</script>"#
        let tickets = CubingChinaTicket.parse(html: html, language: "en")
        let ticket = try XCTUnwrap(tickets.first)
        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(ticket.feeCents, 6000)
        XCTAssertEqual(ticket.validDates, ["2026-02-06"])
        XCTAssertEqual(ticket.purchaseLimit, 2)
        XCTAssertTrue(ticket.competitorsOnly)
        XCTAssertTrue(CubingChinaTicket.parse(html: "<p>Sign in</p>", language: "en").isEmpty)
    }
}
