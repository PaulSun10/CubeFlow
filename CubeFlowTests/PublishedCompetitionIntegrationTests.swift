import Foundation
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import CubeFlow

private final class PublishedFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated static let lock = NSLock()
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Data, Int, Double))?
    nonisolated(unsafe) static var paths: [String] = []
    nonisolated static func configure(_ responder: @escaping @Sendable (URLRequest) -> (Data, Int, Double)) {
        lock.lock(); defer { lock.unlock() }
        self.responder = responder
        paths = []
    }
    nonisolated static func requestedPaths() -> [String] {
        lock.lock(); defer { lock.unlock() }; return paths
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.paths.append(request.url!.path)
        let handler = Self.responder
        Self.lock.unlock()
        guard let handler else { return }
        let (data, status, delay) = handler(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
private final class ScrambleNavigationProbe: ObservableObject {
    @Published var showsScrambles = true
}

private struct ScrambleResponsivenessView: View {
    @ObservedObject var probe: ScrambleNavigationProbe
    let data: PublishedCompetitionData
    let provider: PublishedCompetitionService
    let state: PublishedCompetitionScramblesStore
    var body: some View {
        ScrollView {
            if probe.showsScrambles {
                PublishedCompetitionScramblesContent(data: data, language: "en", state: state)
            } else {
                Text("Info remains responsive")
            }
        }
        .task { await state.load(id: data.competitionID) }
    }
}

@MainActor
final class PublishedCompetitionIntegrationTests: XCTestCase {
    private func competition(_ id: String, url: String, canonical: String? = nil) -> CompetitionSummary {
        CompetitionSummary(id: id, name: id, shortDisplayName: nil, startDate: .distantPast, endDate: .distantPast,
            registrationOpen: nil, registrationClose: nil, competitorLimit: nil, venue: "Venue", venueAddress: "Address",
            venueDetails: nil, city: "Beijing", countryISO2: "CN", latitude: nil, longitude: nil, url: url, website: nil,
            dateRange: "Oct 1-3", eventIDs: ["333", "222"], championshipTypes: nil, wcaCompetitionID: canonical,
            localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
    }
    private func payload(_ id: String, count: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: (1...count).map { index -> [String: Any] in
            ["id": index, "competition_id": id, "event_id": index.isMultiple(of: 2) ? "222" : "333",
             "round_type_id": "f", "format_id": "a", "pos": index, "name": "Alexandra Chen (陈晓琳)",
             "wca_id": "2020TEST\(index)", "country_iso2": "CN", "best": 831, "average": 1012,
             "attempts": [831, 954, -1, 1025, 1077], "regional_single_record": "NR"]
        })
    }
    private func service() -> PublishedCompetitionService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublishedFixtureProtocol.self]
        return PublishedCompetitionService(session: URLSession(configuration: configuration))
    }

    func testBeijingCanonicalIdentityNeverUsesRegionalSlugOrDisplayName() {
        let slug = "Beijing-Autumn-Rivalry-2026"
        let regional = competition(slug, url: "https://cubing.com/competition/\(slug)")
        XCTAssertNil(CompetitionPublishedIdentity.resolve(regional))
        XCTAssertEqual(CompetitionPublishedIdentity.resolve(regional, embeddedID: "BeijingAutumnRivalry2026"), "BeijingAutumnRivalry2026")
        XCTAssertEqual(CompetitionPublishedIdentity.resolve(competition(slug, url: "https://cubing.com/competition/\(slug)", canonical: "BeijingAutumnRivalry2026")), "BeijingAutumnRivalry2026")
        XCTAssertEqual(CompetitionPublishedIdentity.resolve(competition(slug,
            url: "https://www.worldcubeassociation.org/competitions/BeijingAutumnRivalry2026", canonical: "Wrong2026")), "BeijingAutumnRivalry2026")
        XCTAssertNil(CompetitionPublishedIdentity.resolve(competition(slug,
            url: "https://worldcubeassociation.org.evil.example/competitions/BeijingAutumnRivalry2026")))
    }

    func testChineseCompetitionLoadsOfficialPublishedResultsThroughCanonicalIdentity() async throws {
        let bytes = try payload("BeijingAutumnRivalry2026")
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(competition: competition("Beijing-Autumn-Rivalry-2026",
            url: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026", canonical: "BeijingAutumnRivalry2026"), language: "en")
        XCTAssertEqual(store.lifecycle, .published)
        XCTAssertEqual(store.data?.competitionID, "BeijingAutumnRivalry2026")
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths(), ["/api/v0/competitions/BeijingAutumnRivalry2026/results"])
    }

    func testPublishedNavigationRetainsInfoAndUnpublishedDestinationsStayOriginal() {
        for china in [false, true] {
            XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: .published, cubingChina: china, showLive: true, language: "en"), [.info, .results, .scrambles, .live])
            for state in [PublishedCompetitionLifecycle.unknown, .loading, .failed, .unpublished] {
                let expected: [CompetitionDetailTab] = [.info, .register, .competitors, .live]
                XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: state, cubingChina: china, showLive: true, language: "en"), expected)
            }
        }
        XCTAssertEqual(CompetitionDetailTab.info.rawValue, "info")
        XCTAssertEqual(CompetitionDetailTab.results.localizedTitle(languageCode: "en"), "Results")
    }

    func testChinaInfoSectionsKeepHistoricalRegistrationAndParticipantsInOrder() {
        for state in [PublishedCompetitionLifecycle.unknown, .loading, .failed, .unpublished] {
            XCTAssertEqual(CompetitionDetailNavigationPolicy.infoSections(lifecycle: state, cubingChina: true,
                language: "en"), [.info, .rules, .schedule, .travel])
            XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: state, cubingChina: true,
                showLive: false, language: "en"), [.info, .register, .competitors])
        }
        let sections = CompetitionDetailNavigationPolicy.infoSections(lifecycle: .published, cubingChina: true, language: "en")
        XCTAssertEqual(sections, [.info, .rules, .schedule, .travel, .competitors, .register])
        XCTAssertEqual(sections.first?.localizedTitle(languageCode: "en"), "About")
        XCTAssertEqual(Set(sections).count, 6)
        XCTAssertTrue(CompetitionDetailNavigationPolicy.infoSections(lifecycle: .published, cubingChina: false, language: "en").isEmpty)
    }

    func testPublishedSelectionPreservesHistoricalDestinationAndVisibleLive() {
        for tab in [CompetitionDetailTab.register, .competitors, .rules, .schedule, .travel] {
            let recovered = CompetitionDetailNavigationPolicy.selection(lifecycle: .published, cubingChina: true,
                showLive: true, explicitLive: false, primary: tab, section: .info)
            XCTAssertEqual(recovered.primary, .info)
            XCTAssertEqual(recovered.section, tab)
        }
        let live = CompetitionDetailNavigationPolicy.selection(lifecycle: .published, cubingChina: true,
            showLive: true, explicitLive: false, primary: .live, section: .travel)
        XCTAssertEqual(live.primary, .live)
        XCTAssertEqual(live.section, .travel)
        for china in [false, true] {
            XCTAssertEqual(CompetitionDetailNavigationPolicy.selection(lifecycle: .published, cubingChina: china,
                showLive: true, explicitLive: true, primary: .live, section: .info).primary, .live)
        }
        XCTAssertEqual(CompetitionDetailNavigationPolicy.selection(lifecycle: .published, cubingChina: false,
            showLive: true, explicitLive: false, primary: .live, section: .info).primary, .live)
    }

    func testInvalidSelectionRecoversWithoutInventingPublishedState() {
        for state in [PublishedCompetitionLifecycle.unknown, .loading, .failed, .unpublished] {
            let recovered = CompetitionDetailNavigationPolicy.selection(lifecycle: state, cubingChina: true,
                showLive: false, explicitLive: false, primary: .results, section: .competitors)
            XCTAssertEqual(recovered.primary, .info)
            XCTAssertEqual(recovered.section, .info)
        }
        let retained = CompetitionDetailNavigationPolicy.selection(lifecycle: .published, cubingChina: true,
            showLive: false, explicitLive: false, primary: .info, section: .competitors)
        XCTAssertEqual(retained.section, .competitors)
    }

    func testHistoricalRegistrationNeverExposesExpiredAction() {
        let past = competition("BeijingAutumnRivalry2026", url: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026")
        XCTAssertFalse(CompetitionDetailNavigationPolicy.permitsRegistrationAction(past, lifecycle: .unpublished, now: Date()))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.permitsRegistrationAction(past, lifecycle: .published, now: .distantPast))
    }

    func testChinaLiveRequiresValidatedProviderNotASynthesizedURL() {
        let urlOnly = CompetitionDetailContent.empty.replacingWCALiveAvailability(.available,
            url: URL(string: "https://cubing.com/live/example"))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.showsLive(content: urlOnly, cubingChina: true))
        XCTAssertTrue(CompetitionDetailNavigationPolicy.showsLive(content: urlOnly, cubingChina: false))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.showsLive(content: .empty, cubingChina: true))
    }

    private func rgba(_ color: Color, _ style: UIUserInterfaceStyle) -> [CGFloat] {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    func testCurrentChinaSemanticColorsNeutralInfoAndInternationalAccentIsolation() {
        let mappings: [(CompetitionDetailTabKind, CubingChinaNavigationColors.Section)] = [
            (.rules, .regulations), (.schedule, .schedule), (.travel, .travel), (.register, .register),
            (.competitors, .competitors), (.results, .results), (.live, .live), (.scrambles, .scrambles)]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (kind, section) in mappings {
                XCTAssertEqual(rgba(CubingChinaNavigationColors.accent(for: kind), style), rgba(section.foreground, style))
                XCTAssertEqual(rgba(CubingChinaNavigationColors.primaryAccent(for: kind, cubingChina: false), style), rgba(.accentColor, style))
            }
            XCTAssertEqual(rgba(CubingChinaNavigationColors.accent(for: .info), style), rgba(.primary, style))
            XCTAssertEqual(rgba(CubingChinaNavigationColors.accent(for: .info, about: true), style), rgba(CubingChinaNavigationColors.Section.about.foreground, style))
            let sky = rgba(CubingChinaNavigationColors.Section.scrambles.foreground, style)
            for section in [CubingChinaNavigationColors.Section.competitors, .spectatorTicket, .results, .schedule, .travel] {
                let other = rgba(section.foreground, style)
                func hue(_ components: [CGFloat]) -> CGFloat {
                    var h: CGFloat = 0
                    UIColor(red: components[0], green: components[1], blue: components[2], alpha: 1)
                        .getHue(&h, saturation: nil, brightness: nil, alpha: nil)
                    return h
                }
                XCTAssertGreaterThan(abs(hue(sky) - hue(other)), 0.03)
            }
        }
        XCTAssertEqual(rgba(CubingChinaNavigationColors.Section.results.foreground, .light)[0], 130 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgba(CubingChinaNavigationColors.Section.competitors.foreground, .dark)[0], 81 / 255.0, accuracy: 0.001)
    }

    func testAttemptsRemainSecondaryButHaveOpaqueReadableContrast() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ink = rgba(PublishedResultsStyle.attemptForeground, style)
            let paper = rgba(Color(uiColor: .systemGroupedBackground), style)
            func luminance(_ components: [CGFloat]) -> CGFloat {
                let linear = components.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
            }
            let a = luminance(ink), b = luminance(paper)
            XCTAssertGreaterThan((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5)
            XCTAssertEqual(ink[3], 1)
            XCTAssertNotEqual(ink, rgba(.primary, style))
        }
    }

    func testExactChinaLightDarkForegroundAndSelectedBackgroundTokens() {
        let tokens: [(CubingChinaNavigationColors.Section, UInt32, UInt32, UInt32, UInt32)] = [
            (.about, 0xC10007, 0xFF6467, 0xC10007, 0xE7000B),
            (.regulations, 0xF54900, 0xD42300, 0xFF6900, 0xDE4400),
            (.schedule, 0xD08700, 0xB16A00, 0xF0B100, 0xC98B00),
            (.travel, 0x008236, 0x05DF72, 0x00A63E, 0x00A63E),
            (.competitors, 0x1447E6, 0x51A2FF, 0x155DFC, 0x155DFC),
            (.register, 0x45556C, 0xABB9CB, 0x62748E, 0x62748E),
            (.results, 0x8200DB, 0xC27AFF, 0x9810FA, 0x9810FA),
            (.live, 0xC6005C, 0xFB64B6, 0xE60076, 0xE60076),
            (.spectatorTicket, 0x00786F, 0x00D5BE, 0x009689, 0x009689),
            (.scrambles, 0x0069A8, 0x00BCFF, 0x0069A8, 0x0077A8)]
        func check(_ color: Color, _ hex: UInt32, _ style: UIUserInterfaceStyle) {
            let actual = rgba(color, style)
            for (i, shift) in [16, 8, 0].enumerated() {
                XCTAssertEqual(actual[i], CGFloat((hex >> shift) & 255) / 255, accuracy: 0.001)
            }
        }
        for (section, lightInk, darkInk, lightFill, darkFill) in tokens {
            check(section.foreground, lightInk, .light); check(section.foreground, darkInk, .dark)
            check(section.selectedBackground, lightFill, .light); check(section.selectedBackground, darkFill, .dark)
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let sky = rgba(CubingChinaNavigationColors.Section.scrambles.selectedBackground, style)
            let linear = sky.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            let luminance = linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
            XCTAssertGreaterThan(1.05 / (luminance + 0.05), 4.5)
            XCTAssertEqual(rgba(CubingChinaNavigationColors.selectedForeground(for: .scrambles), style), rgba(.white, style))
        }
    }

    func testNativeTitleRemovesInheritedFontOverridesWithoutChangingColors() {
        let inherited = UINavigationBarAppearance()
        inherited.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label]
        inherited.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 22)]
        let native = CompetitionNativeDetailTitleController.nativeAppearance(inherited)
        let defaults = UINavigationBarAppearance()
        XCTAssertEqual((native.titleTextAttributes[.font] as? UIFont)?.fontDescriptor,
            (defaults.titleTextAttributes[.font] as? UIFont)?.fontDescriptor)
        XCTAssertEqual((native.largeTitleTextAttributes[.font] as? UIFont)?.fontDescriptor,
            (defaults.largeTitleTextAttributes[.font] as? UIFont)?.fontDescriptor)
        XCTAssertNotNil(native.titleTextAttributes[.foregroundColor])
        XCTAssertNotNil(inherited.titleTextAttributes[.font], "Do not mutate the parent/international appearance")
    }

    private func fullSizeScrambles(_ id: String) throws -> Data {
        let events = ["333", "222", "444", "555", "666", "777", "333bf", "333fm", "333oh", "clock", "minx", "pyram", "skewb", "sq1", "444bf", "555bf", "333mbf"]
        var rows: [[String: Any]] = []
        for set in 0..<92 {
            for number in 1...(set < 66 ? 7 : 6) {
                rows.append(["id": rows.count + 1, "competition_id": id, "event_id": events[set % events.count],
                    "round_id": set / events.count % 3, "round_type_id": ["1", "2", "f"][set / events.count % 3],
                    "group_id": set < 51 ? "A" : "B", "is_extra": number > 5,
                    "scramble_num": number > 5 ? number - 5 : number, "scramble": " R U' F2 D L2 B' "])
            }
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }

    func testFullSizeScramblesRenderQuicklyAndKeepExactText() async throws {
        let id = "BeijingAutumnRivalry2026", bytes = try fullSizeScrambles(id)
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 0) }
        let provider = service()
        let data = PublishedCompetitionData(competitionID: id, results: [], eventOrder: ["333", "222"])
        let started = PublishedCompetitionClock.now()
        var firstRowMS: Double?
        try await snapshot(ScrollView {
            PublishedCompetitionScramblesContent(data: data, language: "en", service: provider, onFirstScramble: {
                if firstRowMS == nil { firstRowMS = PublishedCompetitionClock.milliseconds(since: started) }
            }).padding(16)
        }, name: "full-size-618-scrambles", dark: false)
        let elapsed = try XCTUnwrap(firstRowMS)
        print("[CompetitionCritical] 618 scrambles first visible row=\(elapsed)ms")
        XCTAssertLessThan(elapsed, 1500)
        let sets = try await provider.scrambles(competitionID: id)
        XCTAssertEqual(sets.count, 92)
        XCTAssertEqual(sets.flatMap(\.scrambles).count, 618)
        XCTAssertTrue(sets.flatMap(\.scrambles).allSatisfy { $0.scramble == " R U' F2 D L2 B' " })
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().count, 1)
    }

    func testSlowScramblesKeepMainActorAndTabSwitchResponsiveAndCoalesceRequests() async throws {
        let id = "Slow2026", bytes = try fullSizeScrambles(id)
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 1.2) }
        let provider = service(), probe = ScrambleNavigationProbe()
        let data = PublishedCompetitionData(competitionID: id, results: [], eventOrder: ["333"])
        let state = PublishedCompetitionScramblesStore(service: provider)
        try await snapshot(ScrambleResponsivenessView(probe: probe, data: data, provider: provider, state: state),
            name: "scrambles-loading-responsive", dark: false, afterPresentation: {
                let start = PublishedCompetitionClock.now()
                probe.showsScrambles = false
                try await Task.sleep(nanoseconds: 30_000_000)
                XCTAssertLessThan(PublishedCompetitionClock.milliseconds(since: start), 250)
                probe.showsScrambles = true
            })
        await state.load(id: id)
        XCTAssertFalse(state.sets.isEmpty)
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().count, 1)
    }

    func testScramblesParentCanJoinSectionRequestAndSurviveItsCancellation() async throws {
        let id = "Joined2026", bytes = try fullSizeScrambles(id)
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 0.15) }
        let state = PublishedCompetitionScramblesStore(service: service())
        let section = Task { await state.load(id: id) }
        while !state.loading { await Task.yield() }
        let parent = Task { await state.load(id: id) }
        try await Task.sleep(nanoseconds: 20_000_000)
        section.cancel()
        await parent.value
        await section.value
        XCTAssertFalse(state.loading)
        XCTAssertFalse(state.failed)
        XCTAssertEqual(state.sets.count, 92)
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().count, 1)
    }

    func testTorontoLoadingFailureRetryAndPublishedRefreshFailureAreDistinct() async throws {
        let id = "TorontoWeeknightsI2026"
        let store = PublishedCompetitionStore(service: service())
        PublishedFixtureProtocol.configure { _ in (Data("[]".utf8), 503, 0.05) }
        let load = Task { await store.load(id: id, events: ["333"]) }
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(store.loading)
        XCTAssertEqual(store.lifecycle, .loading)
        await load.value
        XCTAssertTrue(store.failed)
        XCTAssertEqual(store.lifecycle, .failed)
        let bytes = try payload(id)
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 0) }
        await store.load(id: id, events: ["333"], refresh: true)
        XCTAssertEqual(store.lifecycle, .published)
        XCTAssertFalse(store.failed)
        PublishedFixtureProtocol.configure { _ in (Data(), 503, 0) }
        await store.load(id: id, events: ["333"], refresh: true)
        XCTAssertEqual(store.lifecycle, .published)
        XCTAssertNotNil(store.data)
        XCTAssertTrue(store.failed)
    }

    func testEmptyResultsAreUnpublishedButUnknownIdentityIsNotProofOfUnpublished() async {
        PublishedFixtureProtocol.configure { _ in (Data("[]".utf8), 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: "Future2026", events: [])
        XCTAssertEqual(store.lifecycle, .unpublished)
        XCTAssertNil(store.data)
        await store.load(competition: competition("local", url: "https://example.org/local"), language: "en")
        XCTAssertEqual(store.lifecycle, .unknown)
        XCTAssertFalse(store.loading)
    }

    func testCancellationAndSupersedingRequestDoNotPublishStaleState() async throws {
        let a = try payload("A2026"), b = try payload("B2026")
        PublishedFixtureProtocol.configure { request in request.url!.path.contains("A2026") ? (a, 200, 0.1) : (b, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        let old = Task { await store.load(id: "A2026", events: []) }
        try await Task.sleep(nanoseconds: 10_000_000)
        await store.load(id: "B2026", events: [])
        await old.value
        XCTAssertEqual(store.data?.competitionID, "B2026")
        let cancelledStore = PublishedCompetitionStore(service: service())
        let cancelled = Task { await cancelledStore.load(id: "A2026", events: []) }
        try await Task.sleep(nanoseconds: 10_000_000)
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(cancelledStore.lifecycle, .unknown)
        XCTAssertFalse(cancelledStore.loading)
        XCTAssertNil(cancelledStore.data)
    }

    func testResultsDoNotWaitForScramblesAndConcurrentLoadsCoalesce() async throws {
        let id = "TorontoWeeknightsI2026", bytes = try payload("TorontoWeeknightsI2026", count: 100)
        PublishedFixtureProtocol.configure { request in request.url!.path.hasSuffix("scrambles") ? (Data("[]".utf8), 200, 0.2) : (bytes, 200, 0.04) }
        let provider = service()
        let scrambles = Task { try await provider.scrambles(competitionID: id) }
        let second = Task { try await provider.results(competitionID: id, eventOrder: ["333", "222"]) }
        let result = try await provider.resultSnapshot(competitionID: id, eventOrder: ["333", "222"])
        _ = try await second.value
        XCTAssertTrue(result.data.isPublished)
        XCTAssertEqual(result.metrics.httpStatus, 200)
        XCTAssertEqual(result.metrics.bytes, bytes.count)
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().filter { $0.hasSuffix("results") }.count, 1)
        let warm = try await provider.resultSnapshot(competitionID: id, eventOrder: ["333", "222"])
        XCTAssertTrue(warm.metrics.cacheHit)
        XCTAssertEqual(warm.metrics.modelMS, 0)
        XCTAssertEqual(warm.metrics.decodeMS, 0)
        _ = try await scrambles.value
    }

    func testNativeRichDocumentRetainsSemanticTableImageAndLinkElements() throws {
        let html = "<section><h2>Travel</h2><p><a href='/rail'>Railway</a>: 25 yuan</p><table><tr><th>Bus</th><th>Fare</th></tr><tr><td>12</td><td>2 yuan</td></tr></table><img src='/venue.png'></section>"
        let block = try XCTUnwrap(CubingChinaDetailAdapter.blocks(html: html, section: .travel, language: "en").blocks.first)
        let elements = CompetitionRichHTMLElement.parse(try XCTUnwrap(block.html))
        XCTAssertTrue(elements.contains { if case .table = $0.kind { return true }; return false })
        XCTAssertTrue(elements.contains { if case .image = $0.kind { return true }; return false })
        XCTAssertTrue(elements.contains { if case .linkedText = $0.kind { return true }; return false })
        XCTAssertTrue(block.body.contains("25 yuan"))
    }

    func testGlyphForegroundResolvesWithContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let selected = UIColor(PublishedEventSelectorStyle.foreground(selected: true)).resolvedColor(with: traits)
            let unselected = UIColor(PublishedEventSelectorStyle.foreground(selected: false)).resolvedColor(with: traits)
            var selectedWhite: CGFloat = 0, selectedAlpha: CGFloat = 0
            XCTAssertTrue(selected.getWhite(&selectedWhite, alpha: &selectedAlpha))
            XCTAssertEqual(selectedWhite, 1, accuracy: 0.001)
            XCTAssertEqual(selectedAlpha, 1, accuracy: 0.001)
            var white: CGFloat = 0, alpha: CGFloat = 0
            unselected.getWhite(&white, alpha: &alpha)
            XCTAssertTrue(style == .light ? white < 0.25 : white > 0.75)
        }
    }

    func testOriginalDetailRendersInfoResultsScramblesAndSecondaryChinaSections() async throws {
        let id = "BeijingAutumnRivalry2026", bytes = try payload("BeijingAutumnRivalry2026", count: 80)
        let scramble = Data(#"[{"id":1,"competition_id":"BeijingAutumnRivalry2026","event_id":"333","round_type_id":"f","group_id":"A","is_extra":false,"scramble_num":1,"scramble":"R U' F2 D L2 B'"},{"id":2,"competition_id":"BeijingAutumnRivalry2026","event_id":"333","round_type_id":"f","group_id":"A","is_extra":true,"scramble_num":1,"scramble":"F2 U R' D2"}]"#.utf8)
        PublishedFixtureProtocol.configure { request in (request.url!.path.hasSuffix("scrambles") ? scramble : bytes, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: id, events: ["333", "222"])
        let about = CubingChinaDetailAdapter.blocks(html: "<section><h2>Venue overview</h2><p>Kun Tai Glory Hotel Beijing Wangjing</p></section><section><h2>Organizing team</h2><p>Organizers and delegates remain in the original document.</p></section>", section: .about, language: "en").blocks
        let regulations = CubingChinaDetailAdapter.blocks(html: "<section><h2>Regulations</h2><p>WCA regulations and organizer policies.</p></section>", section: .regulations, language: "en").blocks
        let travel = CubingChinaDetailAdapter.blocks(html: "<section><h2>Rail and buses</h2><p>Railway connection: 25 yuan.</p><table><tr><th>Route</th><th>Fare</th></tr><tr><td>Bus 12</td><td>2 yuan</td></tr></table></section>", section: .travel, language: "en").blocks
        let registration = [CompetitionDetailTextBlock(id: "historical-registration", title: "Registration information",
            body: "Registration closed on September 20. Public historical fees and policies remain available.", html: nil)]
        let participants = [CompetitionCompetitorPreview(id: "registered-only", number: "370", name: "Registered Participant",
            gender: nil, subtitle: "Hong Kong", registeredEventIDs: ["333"], wcaID: nil)]
        let detail = CompetitionDetailContent(overviewBlocks: about, noteBlocks: [], regulationBlocks: regulations,
            travelBlocks: travel, travelMapLocations: [], registerBlocks: registration, scheduleDays: [], scheduleEventSummaries: [],
            wcaEvents: [], scheduleIntroHTML: nil, scheduleCommentHTML: nil, scheduleDebugInfo: nil,
            localizedName: "2026 WCA Beijing Autumn Rivalry", championshipTitles: nil, competitorsCount: nil,
            competitorPreviews: participants, registrationRequiresSignIn: true, hasRegisterLink: true, hasCompetitorsLink: true,
            liveAvailability: .ended, liveURLOverride: nil,
            liveContent: CompetitionLiveContent(competitionID: 123, sourceType: "fixture", roundOptions: [], filterOptions: [],
                defaultEventID: "333", defaultRoundID: "f", defaultFilterValue: "all", staticMessages: [],
                sumOfRanksURL: nil, podiumsURL: nil, sumOfRanksContent: nil, podiumSections: []),
            wcaLiveContent: nil, wcaCompetitionID: id)
        XCTAssertTrue(CompetitionDetailNavigationPolicy.showsLive(content: detail, cubingChina: true))
        XCTAssertEqual(detail.competitorPreviews.map(\.id), ["registered-only"])
        XCTAssertFalse(store.data?.people(query: "", currentWCAID: nil).contains { $0.id == "registered-only" } ?? true)
        XCTAssertEqual(detail.registerBlocks, registration)
        let summary = competition("Beijing-Autumn-Rivalry-2026", url: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026", canonical: id)
        for scheme in [ColorScheme.light, .dark] {
            for tab in [CompetitionDetailTab.info, .results, .scrambles] {
                let view = CompatibleNavigationContainer {
                    CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: detail,
                        renderingPublishedStore: store, renderingTab: tab)
                }.environment(\.colorScheme, scheme)
                try await snapshot(view, name: "china-published-\(tab.rawValue)-\(scheme)", dark: scheme == .dark)
            }
            for section in [CompetitionDetailTab.register, .competitors] {
                try await snapshot(CompatibleNavigationContainer {
                    CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: detail,
                        renderingPublishedStore: store, renderingTab: .info, renderingInfoSection: section)
                }.environment(\.colorScheme, scheme), name: "china-historical-\(section.rawValue)-\(scheme)", dark: scheme == .dark)
            }
            let unpublished = PublishedCompetitionStore(service: service())
            for tab in [CompetitionDetailTab.info, .register, .competitors] {
                try await snapshot(CompatibleNavigationContainer {
                    CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: detail,
                        renderingPublishedStore: unpublished, renderingTab: tab)
                }.environment(\.colorScheme, scheme), name: "china-unpublished-\(tab.rawValue)-\(scheme)", dark: scheme == .dark)
            }
        }
        try await snapshot(CompatibleNavigationContainer {
            CompetitionDetailView(competition: summary, appLanguage: "zh-Hant", renderingContent: detail,
                renderingPublishedStore: store, renderingTab: .info, renderingInfoSection: .competitors)
        }.environment(\.dynamicTypeSize, .accessibility2), name: "china-navigation-accessibility", dark: false)
        try await snapshot(CompatibleNavigationContainer {
            CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: detail,
                renderingPublishedStore: store, renderingTab: .results)
        }, name: "china-results-final-row", dark: false, scrollToBottom: true)
        for destination in [CompetitionDetailTab.register, .competitors] {
            let transitioning = PublishedCompetitionStore(service: service())
            try await snapshot(CompatibleNavigationContainer {
                CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: detail,
                    renderingPublishedStore: transitioning, renderingTab: destination)
            }, name: "publication-arrives-on-\(destination.rawValue)", dark: false, afterPresentation: {
                await transitioning.load(id: id, events: ["333", "222"])
                XCTAssertEqual(transitioning.lifecycle, .published)
            })
        }
        for section in [CompetitionDetailTab.rules, .travel] {
            try await snapshot(CompatibleNavigationContainer {
                CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: detail,
                    renderingPublishedStore: store, renderingTab: .info, renderingInfoSection: section)
            }, name: "original-info-\(section.rawValue)", dark: false)
        }
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().filter { $0.hasSuffix("scrambles") }.count, 1)
        let torontoID = "TorontoWeeknightsI2026", torontoBytes = try payload("TorontoWeeknightsI2026", count: 24)
        let torontoScrambles = Data(String(decoding: scramble, as: UTF8.self).replacingOccurrences(of: id, with: torontoID).utf8)
        PublishedFixtureProtocol.configure { request in (request.url!.path.hasSuffix("scrambles") ? torontoScrambles : torontoBytes, 200, 0) }
        let torontoStore = PublishedCompetitionStore(service: service())
        await torontoStore.load(id: torontoID, events: ["333", "222"])
        for scheme in [ColorScheme.light, .dark] {
            for tab in [CompetitionDetailTab.info, .results, .scrambles] {
                try await snapshot(CompatibleNavigationContainer {
                    CompetitionDetailView(competition: competition(torontoID, url: "https://www.worldcubeassociation.org/competitions/\(torontoID)"),
                        appLanguage: "en", renderingContent: .empty, renderingPublishedStore: torontoStore, renderingTab: tab)
                }.environment(\.colorScheme, scheme), name: "global-\(tab.rawValue)-\(scheme)", dark: scheme == .dark)
            }
        }
    }

    func testFirstMeaningfulRenderWithSmallAndLargeDeterministicResults() async throws {
        for count in [106, 1938] {
            let rows = try PublishedCompetitionService.decodeResults(payload("Render2026", count: count), competitionID: "Render2026")
            let data = PublishedCompetitionData(competitionID: "Render2026", results: rows, eventOrder: ["333", "222"])
            let start = PublishedCompetitionClock.now()
            var firstRowMS: Double?
            try await snapshot(ScrollView {
                PublishedCompetitionResultsContent(data: data, language: "en", onFirstResult: {
                    if firstRowMS == nil { firstRowMS = PublishedCompetitionClock.milliseconds(since: start) }
                }).padding(16)
            }, name: "results-\(count)-rows", dark: false)
            print("[CompetitionPublished] first-meaningful-row rows=\(count) appear=\(try XCTUnwrap(firstRowMS))ms")
        }
    }

    func testLastOfficialScrambleScrollsAboveRealTabBarInBothAppearances() async throws {
        let id = "BeijingAutumnRivalry2026", bytes = try payload("BeijingAutumnRivalry2026")
        let text = "R U' F2 D L2 B' R2 U F D2 B L' U2 R' F2 D B2 U' L2 R U2"
        let rows = (1...24).map { index -> [String: Any] in
            ["id": index, "competition_id": id, "event_id": "333", "round_type_id": "f",
             "group_id": "A", "is_extra": false, "scramble_num": index, "scramble": text]
        }
        let scrambles = try JSONSerialization.data(withJSONObject: rows)
        PublishedFixtureProtocol.configure { request in
            (request.url!.path.hasSuffix("scrambles") ? scrambles : bytes, 200, 0)
        }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: id, events: ["333"])
        for scheme in [ColorScheme.light, .dark] {
            try await snapshot(CompatibleNavigationContainer {
                CompetitionDetailView(competition: competition("Beijing-Autumn-Rivalry-2026",
                    url: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026", canonical: id),
                    appLanguage: "en", renderingContent: .empty, renderingPublishedStore: store, renderingTab: .scrambles)
            }.environment(\.colorScheme, scheme), name: "scrambles-final-row-\(scheme)", dark: scheme == .dark, scrollToBottom: true)
        }
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().filter { $0.hasSuffix("scrambles") }.count, 1)
        let decoded = try PublishedCompetitionService.decodeScrambles(scrambles, competitionID: id)
        XCTAssertEqual(decoded.last?.scramble, text)
    }

    func testChinaNativeLargeAndCollapsedTitlesAcrossAllPublishedDestinations() async throws {
        let id = "BeijingAutumnRivalry2026", resultBytes = try payload(id, count: 80)
        let scrambles = try JSONSerialization.data(withJSONObject: (1...24).map { index -> [String: Any] in
            ["id": index, "competition_id": id, "event_id": "333", "round_type_id": "f", "group_id": "A",
             "is_extra": false, "scramble_num": index, "scramble": "R U' F2 D L2 B' R2 U F D2 B L' U2 R' F2 D B2"]
        })
        PublishedFixtureProtocol.configure { request in (request.url!.path.hasSuffix("scrambles") ? scrambles : resultBytes, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: id, events: ["333", "222"])
        let title = "2026 WCA Beijing Autumn Rivalry"
        let content = CompetitionDetailContent(overviewBlocks: [CompetitionDetailTextBlock(id: "long-info", title: "About",
            body: Array(repeating: "Organizer-authored information remains available.", count: 70).joined(separator: "\n"), html: nil)],
            noteBlocks: [], regulationBlocks: [], travelBlocks: [], travelMapLocations: [], registerBlocks: [], scheduleDays: [],
            scheduleEventSummaries: [], wcaEvents: [], scheduleIntroHTML: nil, scheduleCommentHTML: nil, scheduleDebugInfo: nil,
            localizedName: title, championshipTitles: nil, competitorsCount: nil, competitorPreviews: [],
            registrationRequiresSignIn: false, hasRegisterLink: true, hasCompetitorsLink: true,
            liveAvailability: .unavailable, liveURLOverride: nil, liveContent: nil, wcaLiveContent: nil, wcaCompetitionID: id)
        for china in [true, false] {
            for dark in [false, true] {
                for tab in [CompetitionDetailTab.info, .results, .scrambles] {
                    for collapsed in [false, true] {
                        try await snapshot(CompatibleNavigationContainer {
                            CompetitionDetailView(competition: competition(china ? "Beijing-Autumn-Rivalry-2026" : id,
                                url: china ? "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026" : "https://www.worldcubeassociation.org/competitions/\(id)", canonical: id),
                                appLanguage: "en", renderingContent: content, renderingPublishedStore: store, renderingTab: tab)
                        }, name: "\(china ? "china" : "wca")-native-title-\(tab.rawValue)-\(dark ? "dark" : "light")-\(collapsed ? "inline" : "large")",
                            dark: dark, scrollToBottom: collapsed, nativeTitle: title)
                    }
                }
            }
        }
    }

    private func snapshot<V: View>(_ view: V, name: String, dark: Bool, scrollToBottom: Bool = false,
                                   nativeTitle: String? = nil,
                                   afterPresentation: (() async throws -> Void)? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let wrapped = TabView {
            view.tabItem { Label("Explore", systemImage: "binoculars") }
            Text("Timer").tabItem { Label("Timer", systemImage: "clock") }
            Text("Data").tabItem { Label("Data", systemImage: "chart.bar") }
            Text("Algs").tabItem { Label("Algs", systemImage: "book") }
            Text("Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }.compatibleSoftScrollEdgeEffect().compatibleTabBarBackground()
        window.rootViewController = UIHostingController(rootView: wrapped)
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 300_000_000)
        if let afterPresentation {
            try await afterPresentation()
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        if scrollToBottom {
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let scroll = try XCTUnwrap(descendants(window).compactMap { $0 as? UIScrollView }
                .filter { $0.bounds.height > 250 && $0.bounds.width > 250 }.max { $0.contentSize.height < $1.contentSize.height })
            for _ in 0..<12 {
                let bottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(nanoseconds: 50_000_000)
                scroll.layoutIfNeeded()
            }
            let tabBar = try XCTUnwrap(descendants(window).compactMap { $0 as? UITabBar }.first { !$0.isHidden })
            let readableBottom = scroll.convert(scroll.bounds, to: window).maxY - scroll.adjustedContentInset.bottom
            let barTop = tabBar.convert(tabBar.bounds, to: window).minY
            XCTAssertLessThanOrEqual(readableBottom, barTop + 1, "Content must scroll clear of the actual Tab Bar")
            print("[CompetitionNavigation] \(name) offset=\(scroll.contentOffset.y) content=\(scroll.contentSize.height) inset=\(scroll.adjustedContentInset.bottom) readableBottom=\(readableBottom) barTop=\(barTop)")
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
        XCTAssertGreaterThan(Int(pixels.max() ?? 0) - Int(pixels.min() ?? 0), 32)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        if let nativeTitle {
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let bar = try XCTUnwrap(descendants(window).compactMap { $0 as? UINavigationBar }.first)
            XCTAssertEqual(bar.topItem?.title, nativeTitle)
            XCTAssertNil(bar.topItem?.titleView, "Native title, not a custom principal label")
            XCTAssertEqual((bar.standardAppearance.titleTextAttributes[.font] as? UIFont)?.fontDescriptor,
                (UINavigationBarAppearance().titleTextAttributes[.font] as? UIFont)?.fontDescriptor)
            XCTAssertEqual(bar.topItem?.largeTitleDisplayMode, .never,
                "Large Title is restored below the menu in content, not above it in UINavigationBar")
            if let font = bar.scrollEdgeAppearance?.largeTitleTextAttributes[.font] as? UIFont {
                XCTAssertEqual(font.pointSize, UIFont.preferredFont(forTextStyle: .largeTitle,
                    compatibleWith: bar.traitCollection).pointSize,
                    "UIKit may populate its native default font; it must not use the custom body-title fit")
            }
            let labels = descendants(bar).compactMap { $0 as? UILabel }.filter {
                $0.text == nativeTitle && !$0.isHidden && $0.alpha > 0.5
                    && $0.convert($0.bounds, to: bar).intersects(bar.bounds)
            }
            let font = try XCTUnwrap(labels.first?.font)
            print("[CompetitionCritical] \(name) native title fonts=\(labels.map { $0.font.pointSize })")
            XCTAssertGreaterThanOrEqual(font.pointSize, UIFont.preferredFont(forTextStyle: .headline).pointSize)
        }
        window.isHidden = true
    }

    func testCoordinatedScramblesNeverStartASeparateChildLoad() async throws {
        let id = "Coordinated2026", bytes = try payload("Coordinated2026")
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: id, events: ["333"])
        let data = try XCTUnwrap(store.data)
        try await snapshot(ScrollView {
            PublishedCompetitionScramblesContent(data: data, language: "en", state: store.scrambles,
                isCoordinated: true, isPreparing: true)
        }, name: "coordinated-scrambles-loading", dark: false)
        XCTAssertFalse(PublishedFixtureProtocol.requestedPaths().contains { $0.hasSuffix("scrambles") })
        XCTAssertFalse(store.scrambles.loading)
    }

    func testTicketHierarchyFourOfficialProductsLightDarkAndLargeText() async throws {
        let tickets = (1...3).map { day in
            CubingChinaTicket(id: 37 + day, name: "One-day Ticket for Oct. \(day)",
                description: "Ticket Only Valid for Oct. \(day)", feeCents: 6000,
                validDates: ["2026-10-0\(day)"], saleStart: nil, saleEnd: "2026-09-30T16:00:00.000Z",
                purchaseLimit: nil, competitorsOnly: false, unavailableReason: "sale-ended")
        } + [CubingChinaTicket(id: 41, name: "Ticket for the whole competition",
            description: "3-Day Ticket Valid for Oct. 1st to 3rd", feeCents: 15000, validDates: [],
            saleStart: nil, saleEnd: "2026-09-30T16:00:00.000Z", purchaseLimit: nil,
            competitorsOnly: false, unavailableReason: "sale-ended")]
        XCTAssertEqual(CubingChinaTicketPresentation.commonUnavailableReason(tickets), "sale-ended")
        for (name, scheme, size) in [("light", ColorScheme.light, DynamicTypeSize.large),
                                    ("dark", .dark, .large), ("large-text", .light, .accessibility2)] {
            try await snapshot(ScrollView {
                CubingChinaTicketsContent(tickets: tickets, isLoading: false,
                    slug: "Beijing-Autumn-Rivalry-2026", language: "en").padding(16)
            }.background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size),
                name: "ticket-hierarchy-\(name)", dark: scheme == .dark)
        }
    }

    func testRecentOfficialRecordArrivingAfterMountSelectsMatchingEventAndRoundLightDark() async throws {
        let id = "BeijingAutumnRivalry2026", bytes = CompetitionRecordFixtures.beijing
        PublishedFixtureProtocol.configure { _ in (bytes, 200, 0) }
        let target = PublishedCompetitionResultDeepLink(competitionID: id, resultID: 8581097, eventID: "777")
        for scheme in [ColorScheme.light, .dark] {
            let store = PublishedCompetitionStore(service: service())
            try await snapshot(CompatibleNavigationContainer {
                CompetitionDetailView(competition: competition("Beijing-Autumn-Rivalry-2026",
                    url: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026", canonical: id),
                    appLanguage: "en", renderingContent: .empty, renderingPublishedStore: store,
                    renderingTab: .info, renderingPublishedResultDeepLink: target)
            }.environment(\.colorScheme, scheme), name: "official-record-target-\(scheme)", dark: scheme == .dark,
            afterPresentation: {
                await store.load(id: id, events: ["444", "555", "666", "777"])
                XCTAssertEqual(store.lifecycle, .published)
                XCTAssertEqual(target.result(in: try XCTUnwrap(store.data))?.roundKey, "777|954912")
            })
        }
        XCTAssertEqual(PublishedFixtureProtocol.requestedPaths().filter { $0.hasSuffix("results") }.count, 2)
    }

    func testPublishedChinaArchiveKeepsVisiblePinkLiveWebsiteFallbackLightDark() async throws {
        let id = "BeijingAutumnRivalry2026", slug = "Beijing-Autumn-Rivalry-2026"
        PublishedFixtureProtocol.configure { _ in (CompetitionRecordFixtures.beijing, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: id, events: ["444", "555", "666", "777"])
        let archive = CubingChinaLiveWebsite(url: URL(string: "https://cubing.com/competition/\(slug)/live")!,
            rounds: [.init(eventID: "777", number: 1), .init(eventID: "777", number: 2)])
        var content = CompetitionDetailContent.empty
        content.localizedName = "Beijing Autumn Rivalry 2026"
        content.cubingChinaLiveWebsite = archive
        content.liveURLOverride = archive.url; content.liveAvailability = .available
        XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: store.lifecycle, cubingChina: true,
            showLive: CompetitionDetailNavigationPolicy.showsLive(content: content, cubingChina: true),
            language: "en"), [.info, .results, .scrambles, .live])
        for dark in [false, true] {
            try await snapshot(CompatibleNavigationContainer {
                CompetitionDetailView(competition: competition(slug,
                    url: "https://cubing.com/competition/\(slug)", canonical: id), appLanguage: "en",
                    renderingContent: content, renderingPublishedStore: store, renderingTab: .live)
            }.environment(\.colorScheme, dark ? .dark : .light),
                name: "published-china-live-fallback-\(dark ? "dark" : "light")", dark: dark,
                afterPresentation: {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    print("[AppearanceHold] published-china-live-fallback-\(dark ? "dark" : "light")")
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                })
        }
    }

    func testRefinedTicketScramblesAndRecordsRenderingLightDark() async throws {
        let id = "Refined2026", bytes = try payload("Refined2026", count: 6)
        let scramble = Data(#"[{"id":1,"competition_id":"Refined2026","event_id":"333","round_type_id":"1","group_id":"A","is_extra":false,"scramble_num":1,"scramble":"R U F2 D2 L B'"},{"id":2,"competition_id":"Refined2026","event_id":"222","round_type_id":"f","group_id":"A","is_extra":false,"scramble_num":1,"scramble":"R U R' F2 U'"}]"#.utf8)
        PublishedFixtureProtocol.configure { request in (request.url!.path.hasSuffix("scrambles") ? scramble : bytes, 200, 0) }
        let store = PublishedCompetitionStore(service: service())
        await store.load(id: id, events: ["333", "222"])
        await store.scrambles.load(id: id)
        let data = try XCTUnwrap(store.data)
        let ticket = CubingChinaTicket(id: 38, name: "One-day Spectator Ticket", description: "Valid for one competition day.",
            feeCents: 6000, validDates: ["2026-10-01"], saleStart: "2026-08-31T16:00:00Z",
            saleEnd: "2026-09-30T16:00:00Z", purchaseLimit: nil, competitorsOnly: false,
            unavailableReason: "sale-ended", payableFeeCents: nil, stock: 197)
        for scheme in [ColorScheme.light, .dark] {
            try await snapshot(ScrollView {
                PublishedCompetitionScramblesContent(data: data, language: "en", state: store.scrambles,
                    isCoordinated: true).padding(16)
            }.environment(\.colorScheme, scheme), name: "refined-scrambles-\(scheme)", dark: scheme == .dark)
            try await snapshot(ScrollView {
                CubingChinaTicketsContent(tickets: [ticket], isLoading: false, slug: "Fixture-2026", language: "en").padding(16)
            }.environment(\.colorScheme, scheme), name: "refined-tickets-\(scheme)", dark: scheme == .dark)
            try await snapshot(ScrollView {
                ExploreModuleView(module: ExplorePreviewFixtures.module(.compactList), store: ExploreStore(), language: "en").padding(20)
            }.environment(\.colorScheme, scheme), name: "refined-recent-records-\(scheme)", dark: scheme == .dark)
        }
    }

    func testActualSwiftUIRenderingLightDarkAndAccessibilitySize() async throws {
        let rows = try PublishedCompetitionService.decodeResults(payload("Visual2026", count: 12), competitionID: "Visual2026")
        let data = PublishedCompetitionData(competitionID: "Visual2026", results: rows, eventOrder: ["333", "222"])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (label, scheme, size) in [("light", ColorScheme.light, DynamicTypeSize.large), ("dark", .dark, .large), ("accessibility", .light, .accessibility2)] {
            let presentationStart = PublishedCompetitionClock.now()
            var firstRowMS: Double?
            let view = ScrollView {
                PublishedCompetitionResultsContent(data: data, language: "en", onFirstResult: {
                    if firstRowMS == nil { firstRowMS = PublishedCompetitionClock.milliseconds(since: presentationStart) }
                }).padding(16)
            }.background(Color(uiColor: .systemGroupedBackground)).environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.windowLevel = .alert + 1
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 250_000_000)
            let started = PublishedCompetitionClock.now()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            print("[CompetitionPublished] hosted-render \(label) capture=\(PublishedCompetitionClock.milliseconds(since: started))ms")
            print("[CompetitionPublished] first-meaningful-row \(label) appear=\(try XCTUnwrap(firstRowMS))ms")
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Int(pixels.max() ?? 0) - Int(pixels.min() ?? 0), 32)
            let attachment = XCTAttachment(image: image); attachment.name = "published-results-\(label)"; attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5_000)
            window.isHidden = true
        }
    }
}
