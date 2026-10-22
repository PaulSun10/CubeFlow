import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor
final class CubingChinaModernLivePresentationTests: XCTestCase {
    private func snapshot() throws -> CubingChinaLiveSnapshot {
        try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: CubingChinaModernLiveFixtures.beijing)
    }

    func testBridgeUsesNestedIdentityServerPositionAndVerifiedBadges() async throws {
        let value = try snapshot(), transport = FakeCubingChinaTransport(snapshot: value)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let bridge = CompetitionCubingLiveSession()
        bridge.configure(with: CubingChinaLivePresentation.content(bootstrap, language: "en"), transport: transport)
        bridge.start()
        for _ in 0..<100 where bridge.resultRows.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(bridge.resultRows.count, 17)
        XCTAssertEqual(bridge.resultRows.first?.personWCAID, "2019TARA09")
        XCTAssertEqual(bridge.resultRows.first?.singleRecordTag, "WR")
        XCTAssertEqual(bridge.resultRows.first?.averageRecordTag, "WR")
        XCTAssertEqual(bridge.resultRows.first?.bestResultText, "1:27.47")
        XCTAssertEqual(bridge.resultRows.first?.averageResultText, "1:35.93")
        XCTAssertEqual(bridge.resultRows.first?.rankText, "1")
        XCTAssertEqual(bridge.roundOptions.first?.roundID, "2")
        bridge.stop()
    }

    func testNativeArchivedSectionAndPersonalRowsMountedLightDark() async throws {
        for (name, bytes) in [("beijing", CubingChinaModernLiveFixtures.beijing), ("guangzhou", CubingChinaModernLiveFixtures.guangzhou)] {
            let value = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: bytes)
            let bootstrap = try CubingChinaLiveBootstrap.make(slug: name == "beijing" ? "Beijing-Autumn-Rivalry-2026" : "Guangzhou-Grand-Open-2026",
                rounds: [value.round])
            for dark in [false, true] {
                let transport = FakeCubingChinaTransport(snapshot: value)
                try await mount(ScrollView {
                    CompetitionCubingLiveSection(content: CubingChinaLivePresentation.content(bootstrap, language: "en"),
                        appLanguage: "en", liveURL: URL(string: "https://cubing.com/competition/\(bootstrap.slug)/live"),
                        areCompetitionEventIconsReady: true, modernTransport: transport,
                        extrasTransport: UnifiedExtrasFixture(), resultCard: CompetitionResultCardState()).padding(16)
                }.background(Color(uiColor: .systemGroupedBackground))
                    .environment(\.competitionLivePreviewIdentity, value.rankedResults.first?.competitor?.wcaId),
                    name: "\(name)-native-\(dark ? "dark" : "light")", dark: dark,
                    afterPresentation: {
                        for _ in 0..<200 where transport.connections() == 0 {
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }
                    }) { image in
                        let requests = transport.connections()
                        XCTAssertEqual(requests, 1)
                        XCTAssertGreaterThanOrEqual(try Self.longestBlueAccent(image), 24 * image.scale)
                    }
            }
        }
    }

    func testWCALivePersonalTreatmentMountedWithoutChangingProviderTransport() async throws {
        let value = try snapshot()
        // This presentation DTO exercises WCA's existing shared renderer, not a CCC transport adapter.
        let round = CubingChinaLivePresentation.round(value, rounds: [value.round], language: "en")
        for dark in [false, true] {
            let card = CompetitionResultCardState()
            try await mount(ScrollView {
                CompetitionResultExperience(round: round, languageCode: "en", cardState: card).padding(16)
            }.environment(\.competitionLivePreviewIdentity, "2019TARA09"),
                name: "wca-shared-own-row-\(dark ? "dark" : "light")", dark: dark) { image in
                    XCTAssertGreaterThanOrEqual(try Self.longestBlueAccent(image), 24 * image.scale)
                }
        }
    }

    func testPersonalEmphasisIsDrawingOnlyAndMissingIdentityHasNoEmphasis() async throws {
        let value = try snapshot(), round = CubingChinaLivePresentation.round(value, rounds: [value.round], language: "en")
        for scheme in [ColorScheme.light, .dark] {
            let row = CompetitionResultTableRow(rank: "1", name: "Verified competitor",
                values: [.init(id: "best", text: "1:27.47", recordTag: "WR", width: 74)])
            let ordinary = UIHostingController(rootView: row.environment(\.colorScheme, scheme))
            let own = UIHostingController(rootView: row.modifier(CompetitionPersonalRowTreatment(isOwn: true)).environment(\.colorScheme, scheme))
            let size = CGSize(width: 393, height: 200)
            XCTAssertEqual(ordinary.sizeThatFits(in: size), own.sizeThatFits(in: size))
            XCTAssertEqual(own.sizeThatFits(in: size).height, 34)
        }
        try await mount(CompetitionResultExperience(round: round, languageCode: "en", cardState: CompetitionResultCardState()),
            name: "unmatched-no-shortcut", dark: false) { image in
                XCTAssertLessThan(try Self.longestBlueAccent(image), 24 * image.scale)
            }
        try await mount(CompetitionResultExperience(round: round, languageCode: "en", cardState: CompetitionResultCardState(), isPublished: true)
            .environment(\.competitionLivePreviewIdentity, "2019TARA09"), name: "official-exact-id-emphasis", dark: false) { image in
                XCTAssertGreaterThanOrEqual(try Self.longestBlueAccent(image), 24 * image.scale)
            }
    }

    func testPublishedLifecycleNativeLiveSeparateAndChinaProviderColorUnchanged() throws {
        var detail = CompetitionDetailContent.empty
        let value = try snapshot()
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        detail.liveContent = CubingChinaLivePresentation.content(bootstrap, language: "en"); detail.liveAvailability = .available
        XCTAssertTrue(CompetitionDetailNavigationPolicy.showsLive(content: detail, cubingChina: true))
        XCTAssertFalse(CompetitionDetailNavigationPolicy.showsLive(content: detail, cubingChina: false))
        XCTAssertEqual(CompetitionDetailNavigationPolicy.tabs(lifecycle: .published, cubingChina: true,
            showLive: true, language: "en"), [.info, .results, .scrambles, .live])
        let color = UIColor(CubingChinaNavigationColors.Section.live.selectedBackground)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 230.0 / 255, accuracy: 0.005); XCTAssertEqual(b, 118.0 / 255, accuracy: 0.005)
    }

    func testLegacyModeSwitchClearsModernRowsAndKeepsLegacyOptions() async throws {
        let value = try snapshot(), transport = FakeCubingChinaTransport(snapshot: value)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let content = CubingChinaLivePresentation.content(bootstrap, language: "en")
        let bridge = CompetitionCubingLiveSession()
        bridge.configure(with: content, transport: transport); bridge.start()
        for _ in 0..<100 where bridge.resultRows.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(bridge.resultRows.isEmpty)
        let legacy = CompetitionLiveContent(competitionID: content.competitionID, sourceType: "legacy",
            roundOptions: [.init(id: "777|f", eventID: "777", roundID: "f", eventName: "7x7x7 Cube",
                roundName: "Final", statusText: nil, recordedCount: 0, totalCount: 0, formatID: "m")],
            filterOptions: [], defaultEventID: "777", defaultRoundID: "f", defaultFilterValue: "all",
            staticMessages: [], sumOfRanksURL: nil, podiumsURL: nil, sumOfRanksContent: nil, podiumSections: [])
        bridge.configure(with: legacy)
        XCTAssertNil(bridge.modernSession); XCTAssertTrue(bridge.resultRows.isEmpty)
        XCTAssertEqual(bridge.selectedRoundOptionID, "777|f")
        XCTAssertEqual(bridge.roundOptions, legacy.roundOptions)
        bridge.stop()
    }

    func testModernMyResultsDeepLinkUsesExistingCardAndAvailableAllResults() async throws {
        let value = try snapshot(), transport = FakeCubingChinaTransport(snapshot: value)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let card = CompetitionResultCardState()
        try await mount(CompatibleNavigationContainer { ScrollView {
            CompetitionCubingLiveSection(content: CubingChinaLivePresentation.content(bootstrap, language: "en"),
                appLanguage: "en", liveURL: nil, areCompetitionEventIconsReady: true,
                initialRoundOptionID: "777|2", initialPersonWCAID: "2019TARA09", modernTransport: transport, resultCard: card)
        } }, name: "native-deep-link-section", dark: false) { _ in
            for _ in 0..<100 where card.selection == nil { try await Task.sleep(nanoseconds: 5_000_000) }
            XCTAssertEqual(card.selection?.result.personWCAID, "2019TARA09")
            XCTAssertEqual(card.selection?.round.number, 2)
            XCTAssertFalse(card.selection?.isPublished ?? true)
            card.loadAllResults()
            for _ in 0..<100 where card.isLoadingCompetitorContent { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertEqual(card.selectedCompetitorContent?.wcaID, "2019TARA09")
            XCTAssertEqual(card.selectedCompetitorContent?.results.count, 1)
        }
        for _ in 0..<100 where card.selection != nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNil(card.selection, "Leaving Live closes the existing shared card")
    }

    func testCompletePublishedCompetitionNativeLiveAndViewportCardMountedLightDark() async throws {
        let value = try snapshot(), slug = "Beijing-Autumn-Rivalry-2026", id = "BeijingAutumnRivalry2026"
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: slug, rounds: [value.round])
        CubingChinaHTTPFixture.configure(CompetitionRecordFixtures.beijing)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CubingChinaHTTPFixture.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let store = PublishedCompetitionStore(service: PublishedCompetitionService(session: network))
        await store.load(id: id, events: ["444", "555", "666", "777"])
        XCTAssertEqual(store.lifecycle, .published)
        var content = CompetitionDetailContent.empty
        content.localizedName = "Beijing Autumn Rivalry 2026"; content.wcaCompetitionID = id
        content.liveContent = CubingChinaLivePresentation.content(bootstrap, language: "en")
        content.liveAvailability = .available
        let summary = CompetitionSummary(id: slug, name: "Beijing Autumn Rivalry 2026", shortDisplayName: nil,
            startDate: .distantPast, endDate: .distantPast, registrationOpen: nil, registrationClose: nil,
            competitorLimit: nil, venue: "Venue", venueAddress: "Address", venueDetails: nil, city: "Beijing",
            countryISO2: "CN", latitude: nil, longitude: nil, url: "https://cubing.com/competition/\(slug)",
            website: nil, dateRange: "Oct 1-3", eventIDs: ["777"], championshipTypes: ["world"], wcaCompetitionID: id,
            localizedRegionLineOverride: nil, localizedAddressLineOverride: nil, localizedStatusOverride: nil,
            localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
        let target = CompetitionWCALiveResultDeepLink(roundID: "not-a-CCC-provider-id", personID: nil,
            personWCAID: "2019TARA09", eventID: "777", roundNumber: 2)
        for dark in [false, true] {
            for (name, tab, link) in [("official", CompetitionDetailTab.results, nil),
                                     ("live", .live, nil), ("live-card", .live, Optional(target))] {
                try await mount(CompatibleNavigationContainer {
                    CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: content,
                        renderingPublishedStore: store, renderingTab: tab, renderingLiveResultDeepLink: link)
                }.environment(\.competitionLivePreviewTransport, FakeCubingChinaTransport(snapshot: value))
                    .environment(\.competitionLivePreviewIdentity, "2019TARA09"),
                    name: "full-published-\(name)-\(dark ? "dark" : "light")", dark: dark) { _ in
                        XCTAssertEqual(store.lifecycle, .published)
                    }
            }
        }
        let navigationTarget = CompetitionWCALiveResultDeepLink(roundID: "explicit-live", personID: nil,
            personWCAID: nil, eventID: "777", roundNumber: 2)
        for explicitLive in [false, true] {
            let transitioning = PublishedCompetitionStore(service: PublishedCompetitionService(session: network))
            try await mount(CompatibleNavigationContainer {
                CompetitionDetailView(competition: summary, appLanguage: "en", renderingContent: content,
                    renderingPublishedStore: transitioning, renderingTab: .live,
                    renderingLiveResultDeepLink: explicitLive ? navigationTarget : nil)
            }.environment(\.competitionLivePreviewTransport, FakeCubingChinaTransport(snapshot: value)),
                name: "publication-transition-\(explicitLive ? "explicit-live" : "official-default")", dark: false,
                afterPresentation: { await transitioning.load(id: id, events: ["777"]) }) { image in
                    XCTAssertEqual(transitioning.lifecycle, .published)
                    XCTAssertGreaterThan(try Self.colorPixels(image, hex: explicitLive ? 0xE60076 : 0x9810FA), 30_000)
                }
        }
    }

    private func mount<V: View>(_ view: V, name: String, dark: Bool,
                               afterPresentation: (() async throws -> Void)? = nil,
                               check: (UIImage) async throws -> Void) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 960)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        if let afterPresentation {
            try await Task.sleep(nanoseconds: 150_000_000)
            try await afterPresentation()
        }
        try await Task.sleep(nanoseconds: 450_000_000)
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        try await check(image)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let directory = URL(fileURLWithPath: "/tmp/cubeflow-modern-live-goal/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.pngData()?.write(to: directory.appendingPathComponent(name + ".png"))
        host.beginAppearanceTransition(false, animated: false)
        host.endAppearanceTransition()
        await Task.yield()
    }

    private static func longestBlueAccent(_ image: UIImage) throws -> CGFloat {
        let source = try XCTUnwrap(image.cgImage), width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Text/link glyphs are shorter than a row. The drawing-only leading accent is continuous.
        var longest = 0
        for x in 0..<width {
            var run = 0
            for y in 0..<height {
                let offset = (y * width + x) * 4
                let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                if b > r + 20 && b > g + 10 { run += 1; longest = max(longest, run) }
                else { run = 0 }
            }
        }
        return CGFloat(longest)
    }

    private static func colorPixels(_ image: UIImage, hex: Int) throws -> Int {
        let source = try XCTUnwrap(image.cgImage), width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let r = (hex >> 16) & 255, g = (hex >> 8) & 255, b = hex & 255
        return stride(from: 0, to: bytes.count, by: 4).filter {
            abs(Int(bytes[$0]) - r) <= 3 && abs(Int(bytes[$0 + 1]) - g) <= 3 && abs(Int(bytes[$0 + 2]) - b) <= 3
        }.count
    }
}
