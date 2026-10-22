import Foundation
import XCTest
@testable import CubeFlow

@MainActor
final class CubingChinaDetailTests: XCTestCase {
    func testNuxtEventReferenceSeventeenResolvesToItsSemanticEventNotAnEventNumber() throws {
        let payload: [Any] = [["schedule": 1], [2], ["id": 3, "eventId": 17, "startTime": 4, "endTime": 5],
            123, "2026-10-05T00:30:00.000Z", "2026-10-05T01:30:00.000Z"]
            + Array(repeating: NSNull(), count: 11) + ["clock"]
        let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let rows = CubingChinaDetailAdapter.schedule(html: "<script id='__NUXT_DATA__'>\(json)</script>", language: "en")
        let entry = try XCTUnwrap(rows.first?.entries.first)
        XCTAssertEqual(entry.eventCode, "clock")
        XCTAssertEqual(entry.title, "Clock")
        XCTAssertNotNil(CompetitionEventIconFont.glyph(for: entry.eventCode!))
        XCTAssertNil(CompetitionEventIconFont.glyph(for: "17"), "Serialization positions are not WCA event IDs")
        XCTAssertEqual(CompetitionEventPresentation.localizedFullName(for: entry.eventCode!, languageCode: "en"), "Clock")
    }

    /// Minimal public Nuxt/devalue-shaped fixture with observed v2 semantic fields.
    private func page(_ object: [String: Any]) throws -> String {
        var table: [Any] = []
        func reference(_ value: Any) -> Int {
            let index = table.count
            table.append(NSNull())
            if let object = value as? [String: Any] {
                table[index] = object.mapValues { reference($0) }
            } else if let array = value as? [Any] {
                table[index] = array.map { reference($0) }
            } else { table[index] = value }
            return index
        }
        _ = reference(object)
        let payload = String(data: try JSONSerialization.data(withJSONObject: table), encoding: .utf8)!
        return "<script type='application/json' id='__NUXT_DATA__'>\(payload)</script>"
    }

    func testSemanticSectionsPreserveIntroTablesImagesListsAndArbitraryContent() {
        let html = """
        <nav>Ignore navigation</nav><div class="changed-wrappers">
        <section><header><h2>Rail and buses</h2></header><div><p>Organizer guidance.</p>
        <table><tr><td>Railway</td><td>25 yuan</td></tr></table><ul><li>Parking</li></ul>
        <img src="https://example.org/map.png"><a href="https://example.org/rail">Route</a>
        <section><h3>Transfers</h3><p>Bus 12</p></section></div></section>
        <section><h2>Unusual organizer policy</h2><p>Keep this too.</p></section></div>
        <script>doNotExecute()</script><footer>Ignore footer</footer>
        """
        let parsed = CubingChinaDetailAdapter.blocks(html: html, section: .travel, language: "en")
        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertEqual(parsed.blocks.first?.title, "Rail and buses")
        XCTAssertTrue(parsed.blocks.first?.body.contains("Organizer guidance") == true)
        XCTAssertTrue(parsed.blocks.first?.body.contains("25 yuan") == true)
        XCTAssertTrue(parsed.blocks.first?.body.contains("Bus 12") == true)
        XCTAssertTrue(parsed.blocks.first?.html?.contains("map.png") == true)
        XCTAssertFalse(parsed.blocks.contains { $0.body.contains("Ignore navigation") || $0.body.contains("doNotExecute") })
    }

    func testEmbeddedOrganizerDocumentRetainsLeadingTextAndLanguage() throws {
        let html = try page(["competition": ["wcaCompetitionId": "Test2025", "i18nAttributes": [
            ["key": "travel", "locale": "en", "value": "<p>Airport bus fare.</p><h3>Rail</h3><p>Station advice.</p>"],
            ["key": "travel", "locale": "zh", "value": "<p>机场大巴票价</p>"]]]])
        let english = CubingChinaDetailAdapter.blocks(html: html, section: .travel, language: "en")
        XCTAssertEqual(english.source, "embedded-organizer-content")
        XCTAssertTrue(english.blocks.first?.body.hasPrefix("Airport bus fare") == true)
        XCTAssertEqual(CubingChinaDetailAdapter.blocks(html: html, section: .travel, language: "zh-Hans").blocks.first?.body, "机场大巴票价")
        XCTAssertEqual(CubingChinaDetailAdapter.wcaID(in: html), "Test2025")
    }

    func testAutomaticVenueSectionDoesNotHideOrganizerTravelOutsideSections() throws {
        let state = try page(["competition": ["wcaCompetitionId": "BeijingAutumnRivalry2026", "i18nAttributes": [
            ["key": "travel", "locale": "zh", "value": "火车/高铁：<br>北京站：地铁二号线<br>机场：首都机场线"]]]])
        let html = "<section><h2>Travel</h2></section><div>火车/高铁：<br>北京站：地铁二号线<br>机场：首都机场线</div><section><h2>Venue overview</h2><p>Hotel and map</p></section>" + state
        let parsed = CubingChinaDetailAdapter.blocks(html: html, section: .travel, language: "en")
        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertTrue(parsed.blocks.first?.body.contains("首都机场线") == true)
        XCTAssertEqual(parsed.blocks.last?.title, "Venue overview")
        let elements = CompetitionRichHTMLElement.parse(parsed.blocks.first?.html ?? "")
        XCTAssertFalse(elements.isEmpty)
    }

    func testOrganizerContentAlreadyRenderedIsNotDuplicated() throws {
        let rich = "<p>Airport bus: 25 yuan.</p>"
        let state = try page(["competition": ["wcaCompetitionId": "Test2025", "i18nAttributes": [
            ["key": "travel", "locale": "en", "value": rich]]]])
        let parsed = CubingChinaDetailAdapter.blocks(html: "<section><h2>Airport</h2>\(rich)</section>" + state, section: .travel, language: "en")
        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks.first?.title, "Airport")
    }

    func testSectionsFailIndependentlyWithIdentifiableDiagnostic() throws {
        let about = "<section><h2>About</h2><p>Venue information</p></section>"
        let changed = try page(["competition": ["wcaCompetitionId": "Test2025"]]) + "<p>Nonempty changed section</p>"
        let travel = "<section><h2>Travel</h2><p>Bus guidance</p></section>"
        XCTAssertEqual(CubingChinaDetailAdapter.blocks(html: about, section: .about, language: "en").blocks.count, 1)
        let failed = CubingChinaDetailAdapter.blocks(html: changed, section: .regulations, language: "en")
        XCTAssertTrue(failed.nonemptyContentFailed)
        XCTAssertTrue(failed.blocks.isEmpty)
        XCTAssertEqual(CubingChinaDetailAdapter.blocks(html: travel, section: .travel, language: "en").blocks.count, 1)
    }

    func testCurrentRegulationsH3SectionsRetainAutomaticAndOrganizerRules() {
        let html = """
        <section><div><h2>Regulations</h2></div></section>
        <section><div><h3>WCA-certified competition</h3><p>Official regulations link.</p></div></section>
        <section><div><h3>Registration</h3><ol><li>Check identification.</li></ol>
        <h3>Check-in</h3><p>In person.</p><h3>Other</h3><p>Organizer award policy.</p></div></section>
        """
        let parsed = CubingChinaDetailAdapter.blocks(html: html, section: .regulations, language: "en")
        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertEqual(parsed.blocks[1].title, "Registration")
        XCTAssertTrue(parsed.blocks[1].body.contains("Check-in"))
        XCTAssertTrue(parsed.blocks[1].body.contains("Organizer award policy"))
    }

    func testValidCompetitorsDoNotFailLegacy404SubstringGuard() throws {
        let html = try page(["competitors": [["id": 404, "number": 404,
            "user": ["name": "Valid Person", "wcaId": "2020TEST01"],
            "registrationEvents": [["eventId": "333"]]]]])
        XCTAssertEqual(CompetitionService.extractCubingCompetitorPreviews(from: html).first?.name, "Valid Person")
    }

    func testImageOnlyOrganizerSectionsSurvive() {
        let parsed = CubingChinaDetailAdapter.blocks(html: "<section><h2>Venue map</h2><img src='/map.png'></section>", section: .travel, language: "en")
        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertTrue(parsed.blocks[0].html?.contains("/map.png") == true)
    }

    func testPublicRegistrationIdentityAndEventFieldsNotTableColumnPositions() throws {
        let html = try page(["competitors": [["id": 10, "number": 9,
            "user": ["name": "Test Person", "localName": "测试选手", "wcaId": "2020TEST01", "regionIso2": "CN", "gender": "m"],
            "registrationEvents": [["eventId": "333"], ["eventId": "222"]]]]])
        let rows = CubingChinaDetailAdapter.competitors(html: html, language: "zh-Hans")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "测试选手")
        XCTAssertEqual(rows.first?.wcaID, "2020TEST01")
        XCTAssertEqual(rows.first?.registeredEventIDs, ["333", "222"])
        XCTAssertEqual(rows.first?.number, "9")
    }

    @MainActor
    func testStructuredScheduleUsesAbsoluteTimeAndShanghaiDayNotPhoneTimeZone() throws {
        let row: [String: Any] = ["id": 1, "eventId": "333", "startTime": "2026-10-05T00:30:00.000Z", "endTime": "2026-10-05T01:30:00.000Z",
            "venue": ["id": 2, "name": "Main Stage", "nameZh": "主赛台", "color": "#6091ba"],
            "round": ["roundNumber": 1, "format": "a", "timeLimit": ["centiseconds": 6000],
                "cutoff": ["attemptResult": 3000], "advancementCondition": ["type": "ranking", "level": 100]]]
        let html = try page(["schedule": [row]])
        let days = CubingChinaDetailAdapter.schedule(html: html, language: "en")
        XCTAssertEqual(days.first?.title, "2026-10-05")
        let entry = try XCTUnwrap(days.first?.entries.first)
        XCTAssertEqual(entry.timeText, "08:30–09:30")
        XCTAssertEqual(entry.startMinuteOfDay, 510)
        XCTAssertEqual(entry.endMinuteOfDay, 570)
        XCTAssertEqual(entry.eventCode, "333")
        XCTAssertEqual(entry.timeLimit, "1:00.00")
        XCTAssertEqual(entry.cutoff, "30.00")
        XCTAssertEqual(entry.advancingCount, "100")
        XCTAssertEqual(days.first?.venues.first?.id, "cubing-room-2")
    }

    func testLocationCoordinatesUsePublicStructuredVenue() throws {
        let html = try page(["wcaCompetitionId": "Test2025", "locations": [["id": 3, "latitude": 23.0, "longitude": 113.0, "venue": "Hotel", "venueZh": "酒店"]]])
        let rows = CubingChinaDetailAdapter.mapLocations(html: html, language: "zh-Hans")
        XCTAssertEqual(rows.first?.venue, "酒店")
        XCTAssertEqual(rows.first?.latitude, 23.0)
    }

    func testCyclicAndUnknownStateReducersFailSafely() {
        let cyclic = "<script id='__NUXT_DATA__'>[{\"wcaCompetitionId\":0}]</script>"
        XCTAssertNil(CubingChinaDetailAdapter.wcaID(in: cyclic))
        let unknown = "<script id='__NUXT_DATA__'>[{\"schedule\":1},[\"UnexpectedReducer\",2],{}]</script>"
        XCTAssertTrue(CubingChinaDetailAdapter.schedule(html: unknown, language: "en").isEmpty)
        XCTAssertNil(CubingChinaPageState(html: "<script id='__NUXT_DATA__'>broken</script>"))
    }

    func testSerializationIndicesAndPresentationClassesAreNotContracts() throws {
        let fixture = "<script id='__NUXT_DATA__'>[[\"ShallowReactive\",1],{\"competition\":2},{\"wcaCompetitionId\":3},\"Test2025\"]</script>"
        XCTAssertEqual(CubingChinaDetailAdapter.wcaID(in: fixture), "Test2025")
        let plain = "<div class='arbitrary'><section class='no-panel'><h2 class='no-panel-title'>Regulations</h2><p>Rules</p></section></div>"
        XCTAssertEqual(CubingChinaDetailAdapter.blocks(html: plain, section: .regulations, language: "en").blocks.first?.body, "Rules")
    }
}
