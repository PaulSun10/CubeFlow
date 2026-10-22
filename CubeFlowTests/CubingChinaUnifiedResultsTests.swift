import XCTest
import SwiftUI
@testable import CubeFlow

nonisolated final class UnifiedExtrasFixture: CubingChinaLiveExtrasTransport, @unchecked Sendable {
    func podiums(slug: String) async throws -> [CubingChinaLivePodium] {
        try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLivePodium]>.self, from: CubingChinaUnifiedFixtures.podiums).data
    }
    func records(slug: String) async throws -> [CubingChinaLiveResult] {
        try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveResult]>.self, from: CubingChinaUnifiedFixtures.records).data
    }
    func sumOfRanks(slug: String) async throws -> [CubingChinaLiveSumRank] {
        try JSONDecoder().decode(CubingChinaLiveData<[CubingChinaLiveSumRank]>.self, from: CubingChinaUnifiedFixtures.sums).data
    }
}

nonisolated final class UnifiedCoreFixture: CubingChinaLiveTransport, @unchecked Sendable {
    let core: FakeCubingChinaTransport
    init(snapshot: CubingChinaLiveSnapshot) { core = FakeCubingChinaTransport(snapshot: snapshot) }
    func rounds(slug: String) async throws -> [CubingChinaLiveRound] {
        try JSONDecoder().decode([CubingChinaLiveRound].self, from: CubingChinaUnifiedFixtures.rounds)
    }
    func results(slug: String, key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot {
        if key == core.value.round.key { return try await core.results(slug: slug, key: key) }
        let rounds = try await rounds(slug: slug)
        guard let round = rounds.first(where: { $0.key == key }) else { throw CubingChinaLiveError.invalidData }
        let results = try await UnifiedExtrasFixture().records(slug: slug)
        return .init(round: round, results: results.filter { $0.belongs(to: round) })
    }
    func messages(slug: String) async throws -> [CubingChinaLiveMessage] { try await core.messages(slug: slug) }
    func events(slug: String, viewerID: String) async throws -> CubingChinaLiveConnection { try await core.events(slug: slug, viewerID: viewerID) }
    func competitorResults(slug: String, number: Int) async throws -> [CubingChinaLiveResult] { try await core.competitorResults(slug: slug, number: number) }
}

@MainActor final class CubingChinaUnifiedResultsTests: XCTestCase {
    func testAllResultsAndRoundKeepExplicitRegionalAndPersonalRecordsSeparate() throws {
        for bytes in [CubingChinaModernLiveFixtures.beijing, CubingChinaModernLiveFixtures.guangzhou] {
            let source = try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: bytes)
            let rounds = [source.round]
            var personalOnly = 0
            for value in source.results {
                let preview = CubingChinaLivePresentation.preview(value, language: "en")
                let all = try XCTUnwrap(CubingChinaLivePresentation.competitor([value], rounds: rounds, language: "en")?.results.first)
                let single = value.singleBadge ?? (value.personalSingleRecord == "PR" ? "PR" : nil)
                let average = value.averageBadge ?? (value.personalAverageRecord == "PR" ? "PR" : nil)
                XCTAssertEqual(preview.singleRecordTag, single)
                XCTAssertEqual(preview.averageRecordTag, average)
                XCTAssertEqual(all.singleRecordTag, single)
                XCTAssertEqual(all.averageRecordTag, average)
                if single == "PR" || average == "PR" { personalOnly += 1 }
                // Global record discovery must still exclude personal-only records.
                XCTAssertNotEqual(value.singleBadge, "PR")
                XCTAssertNotEqual(value.averageBadge, "PR")
            }
            XCTAssertGreaterThan(personalOnly, 0, "Exercise actual captured PR metadata")
        }
    }
    private func rounds() throws -> [CubingChinaLiveRound] {
        try JSONDecoder().decode([CubingChinaLiveRound].self, from: CubingChinaUnifiedFixtures.rounds)
    }
    private func snapshot() throws -> CubingChinaLiveSnapshot {
        try JSONDecoder().decode(CubingChinaLiveSnapshot.self, from: CubingChinaModernLiveFixtures.beijing)
    }
    func testVerifiedAggregatesAndCategoriesUseCanonicalRoundIdentity() async throws {
        let rounds = try rounds(), fixture = UnifiedExtrasFixture()
        let p = try await fixture.podiums(slug: "fixture"), r = try await fixture.records(slug: "fixture")
        XCTAssertEqual(p.count, 27)
        XCTAssertEqual(CubingChinaLiveExtrasStore.validatedPodiums(p, rounds: rounds).count, 27)
        XCTAssertEqual(CubingChinaLiveExtrasStore.validatedRecords(r, rounds: rounds).count, 10)
        XCTAssertTrue(CubingChinaLiveExtrasStore.validatedRecords(r, rounds: [try snapshot().round]).count < r.count)
        XCTAssertTrue(CubingChinaLiveExtrasStore.validatedRecords(r + r, rounds: rounds).isEmpty)
        let sums = try await fixture.sumOfRanks(slug: "fixture")
        XCTAssertTrue(sums.allSatisfy { $0.isValid(events: Set(rounds.map(\.eventId))) })
        XCTAssertEqual(sums.first?.sum, 335)
        let store = CubingChinaLiveExtrasStore(), bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: rounds)
        store.refresh(bootstrap, transport: fixture)
        for _ in 0..<100 where store.isLoading { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(store.podiums.count, 27); XCTAssertEqual(store.records.count, 10); XCTAssertEqual(store.sums.count, 5)
        XCTAssertEqual(store.sums.map(\.sum), sums.map(\.sum), "Server order is not a fabricated overall rank")
        store.stop()
    }
    func testHeaderCountsTimestampsAndViewerFreshnessHaveProvenance() throws {
        var value = try snapshot()
        let now = Date(timeIntervalSince1970: 1_791_734_000)
        XCTAssertEqual(CubingChinaLiveHeaderMetadata.counts(value)?.expected, 17)
        XCTAssertEqual(CubingChinaLiveHeaderMetadata.counts(value)?.recorded, 17)
        XCTAssertNil(CubingChinaLiveHeaderMetadata.updatedAt(value, now: now))
        var result = value.results[0]
        result.updatedByOperatorAt = "2026-10-01T12:00:00.000Z"
        value = .init(round: value.round, results: [result, result])
        XCTAssertEqual(CubingChinaLiveHeaderMetadata.counts(value)?.expected, 1, "Registration groups, not duplicate rows")
        XCTAssertNotNil(CubingChinaLiveHeaderMetadata.updatedAt(value, now: now))
        XCTAssertEqual(CubingChinaLiveHeaderMetadata.freshViewers(0, observedAt: now, now: now), 0)
        XCTAssertNil(CubingChinaLiveHeaderMetadata.freshViewers(2, observedAt: nil, now: now))
        XCTAssertNil(CubingChinaLiveHeaderMetadata.freshViewers(2, observedAt: now, now: now.addingTimeInterval(46)))
        XCTAssertNil(CubingChinaLiveHeaderMetadata.viewerObservation(occurredAt: "invalid", now: now))
        let old = CubingChinaLiveHeaderMetadata.viewerObservation(occurredAt: "2026-10-01T12:00:00.000Z", now: now)
        XCTAssertNil(CubingChinaLiveHeaderMetadata.freshViewers(2, observedAt: old, now: now))
        XCTAssertEqual(CubingChinaLiveHeaderMetadata.viewerObservation(occurredAt: nil, now: now), now)
    }
    func testViewerObservationClearsOnStop() async throws {
        let value = try snapshot(), transport = FakeCubingChinaTransport(snapshot: value)
        let bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: [value.round])
        let manager = CubingChinaModernLiveSession(bootstrap: bootstrap, transport: transport)
        manager.start()
        for _ in 0..<100 where manager.snapshot == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        try transport.emit("heartbeat", payload: [:])
        for _ in 0..<100 where manager.viewersObservedAt == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNotNil(manager.viewersObservedAt)
        manager.stop(); XCTAssertNil(manager.viewersObservedAt)
    }
    func testHeaderCompleteMetadataMountedAtNarrowWidth() async throws {
        let original = try snapshot()
        var results = original.results
        results[0].updatedByOperatorAt = "2026-10-02T15:40:48.048Z"
        let value = CubingChinaLiveSnapshot(round: original.round, results: results)
        for dark in [false, true] {
            try await mount(VStack(spacing: 0) {
                CubingChinaIntegratedResultsHeader(snapshot: value, rounds: [value.round], language: "en", current: true,
                    viewers: 8, viewersObservedAt: Date())
                Divider()
                CompetitionResultExperience(round: CubingChinaLivePresentation.round(value, rounds: [value.round], language: "en"),
                    languageCode: "en", cardState: CompetitionResultCardState(), decoratesList: false)
            }.frame(maxHeight: 650, alignment: .top).padding(16), name: "header-complete-\(dark)", dark: dark, width: 320) { _, _ in }
        }
    }
    func testVerifiedPhotoLinksRejectUntrustedSchemesAndCredentials() {
        XCTAssertEqual(CubingChinaPhotoStream.verified([["title": "Photo", "url": "https://live.photoplus.cn/live/47488695"]]).count, 1)
        for value in ["javascript:alert(1)", "http://example.com/photo", "https://user:pass@example.com/photo"] {
            XCTAssertTrue(CubingChinaPhotoStream.verified([["title": "Photo", "url": value]]).isEmpty)
        }
    }
    func testExtrasHTTPUsesObservedEnvelopesAndPaths() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CubingChinaHTTPFixture.self]
        let network = URLSession(configuration: config); defer { network.invalidateAndCancel() }
        let client = CubingChinaLiveHTTPClient(session: network), slug = "Beijing-Autumn-Rivalry-2026"
        CubingChinaHTTPFixture.configure(CubingChinaUnifiedFixtures.podiums)
        let podiums = try await client.podiums(slug: slug); XCTAssertEqual(podiums.count, 27)
        XCTAssertTrue(CubingChinaHTTPFixture.recordedRequests()[0].url!.path.hasSuffix("/live/podiums"))
        CubingChinaHTTPFixture.configure(CubingChinaUnifiedFixtures.records)
        let records = try await client.records(slug: slug); XCTAssertEqual(records.count, 10)
        XCTAssertTrue(CubingChinaHTTPFixture.recordedRequests()[0].url!.path.hasSuffix("/live/records"))
        CubingChinaHTTPFixture.configure(CubingChinaUnifiedFixtures.sums)
        let sums = try await client.sumOfRanks(slug: slug); XCTAssertEqual(sums.count, 5)
        let request = CubingChinaHTTPFixture.recordedRequests()[0]
        XCTAssertTrue(request.url!.path.hasSuffix("/live/statistics/sum-of-ranks"))
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testBadgeReserveAccommodatesActualCompactBadgeAndLongScores() {
        let badge = UIHostingController(rootView: CompetitionWCARecordTagView(tag: "WR", variant: .compact))
        XCTAssertLessThanOrEqual(badge.sizeThatFits(in: .init(width: 100, height: 100)).width, 23)
        XCTAssertEqual(CompetitionAllResultsLayout.badgeReserve, 25)
        let width = CompetitionAllResultsLayout.scoreWidth(texts: ["48/50 59:59"], base: 62, emphasized: true)
        XCTAssertGreaterThan(width, 62)
        XCTAssertGreaterThan(CompetitionAllResultsLayout.minimumWidth(scoreWidths: [width, width]), 276)
        let nextInk = CompetitionAllResultsLayout.scoreWidth(texts: ["1:27.47"], base: 0, emphasized: false)
        let reserve = CompetitionAllResultsLayout.trailingReserve(nextWidth: 62, nextInkWidth: nextInk)
        XCTAssertLessThanOrEqual(CompetitionAllResultsLayout.minimumWidth(scoreWidths: [72, 62], reserves: [reserve, 25]), 276)
        XCTAssertEqual(CompetitionAllResultsLayout.trailingReserve(nextWidth: 62, nextInkWidth: 62), 21)
    }
    func testNativeLiveToolbarMountedLightDarkAndNarrow() async throws {
        let value = try snapshot(), bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: rounds())
        var content = CubingChinaLivePresentation.content(bootstrap, language: "en")
        content.photoStreams = CubingChinaPhotoStream.verified([["title": "Photo", "url": "https://live.photoplus.cn/live/47488695"]])
        for (dark, width) in [(false, CGFloat(430)), (true, 430), (false, 320)] {
            let transport = UnifiedCoreFixture(snapshot: value)
            try await mount(CompatibleNavigationContainer {
                ScrollView {
                    CompetitionCubingLiveSection(content: content,
                        appLanguage: "en", liveURL: URL(string: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/live"),
                        areCompetitionEventIconsReady: true, initialRoundOptionID: "777|2", modernTransport: transport,
                        extrasTransport: UnifiedExtrasFixture(), openOfficialResults: {}, resultCard: CompetitionResultCardState()).padding(16)
                }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Live").navigationBarTitleDisplayMode(.inline)
            }.environment(\.competitionLivePreviewIdentity, "2019TARA09"),
                name: "unified-live-\(dark ? "dark" : "light")-\(Int(width))", dark: dark, width: width) { window, _ in
                    let views = self.descendants(window)
                    let hierarchy = views.map { "\(type(of: $0)) \($0.convert($0.bounds, to: window)) id=\($0.accessibilityIdentifier ?? "")" }.joined(separator: "\n")
                    try hierarchy.write(toFile: "/tmp/cubeflow-unified-results-goal/toolbar-hierarchy-\(Int(width)).txt", atomically: true, encoding: .utf8)
                    let buttons = views.filter { String(describing: type(of: $0)) == "ToolbarTAMICAdaptorView" && !$0.isHidden && $0.alpha > 0 }
                        .map { $0.convert($0.bounds, to: window) }.filter { $0.minY > window.bounds.height - 150 }.sorted { $0.minX < $1.minX }
                    XCTAssertEqual(buttons.count, 1, "Chat is the only bottom action; preferences remain in Chat")
                    XCTAssertGreaterThan(try XCTUnwrap(buttons.last).midX, width * 2 / 3, "Chat remains bottom-right")
                }
        }
    }
    func testVerifiedSectionsAndChatSheetAndDirectMyResultsMounted() async throws {
        let value = try snapshot(), bootstrap = try CubingChinaLiveBootstrap.make(slug: "Beijing-Autumn-Rivalry-2026", rounds: rounds())
        for destination in ["podiums", "records", "sum_ranks", "chat", "my_results"] {
            let card = CompetitionResultCardState()
            try await mount(CompatibleNavigationContainer {
                ScrollView {
                    CompetitionCubingLiveSection(content: CubingChinaLivePresentation.content(bootstrap, language: "en"),
                        appLanguage: "en", liveURL: URL(string: "https://cubing.com/competition/Beijing-Autumn-Rivalry-2026/live"),
                        areCompetitionEventIconsReady: true, initialRoundOptionID: "777|2", modernTransport: UnifiedCoreFixture(snapshot: value),
                        extrasTransport: UnifiedExtrasFixture(), resultCard: card).padding(16)
                }.navigationTitle("Live").navigationBarTitleDisplayMode(.inline)
            }.environment(\.competitionLivePreviewIdentity, "2019TARA09")
                .environment(\.competitionLivePreviewDestination, destination)
                .environment(\.competitionLivePreviewSheet, ["chat", "my_results"].contains(destination) ? destination : nil),
                name: "native-\(destination)", dark: false) { window, _ in
                    if destination == "chat" {
                        XCTAssertNotNil(window.rootViewController?.presentedViewController, "Existing content is presented in a native sheet")
                    }
                    if destination == "my_results" {
                        XCTAssertNil(window.rootViewController?.presentedViewController, "My Results uses the shared card, not a separate sheet")
                        XCTAssertEqual(card.selection?.entry, .competition)
                        XCTAssertNotNil(card.selectedCompetitorContent)
                        card.close()
                        XCTAssertNil(card.selection)
                    }
                }
        }
    }
    func testAllResultsMountedNarrowLongFormatAndBadgeSpace() async throws {
        let value = try snapshot(), round = CubingChinaLivePresentation.round(value, rounds: [value.round], language: "en")
        var content = try XCTUnwrap(CubingChinaLivePresentation.competitor([value.results[0]], rounds: [value.round], language: "en"))
        let long = CompetitionWCALiveCompetitorResult(id: "long", ranking: 1, isAdvancing: nil, isAdvancingQuestionable: nil,
            attempts: [970_354_050], best: 970_354_050, average: 0, singleRecordTag: "WR", averageRecordTag: nil,
            roundID: "multi", roundName: "Final", roundNumber: 1, eventID: "333mbf", eventName: "3x3x3 Multi-Blind",
            eventRank: nil, formatID: "1", numberOfAttempts: 1, sortBy: "best")
        content = .init(id: content.id, name: content.name, wcaID: content.wcaID, countryISO2: content.countryISO2, results: content.results + [long])
        let state = CompetitionResultCardState(); state.selectedCompetitorContent = content
        for dark in [false, true] {
            try await mount(ScrollView {
                CompetitionResultExperience(round: round, languageCode: "en", cardState: state, mode: .competitor, showsCompetitorBack: false)
            }, name: "all-results-narrow-\(dark ? "dark" : "light")", dark: dark, width: 320) { _, image in
                XCTAssertGreaterThan(image.size.height, 0)
            }
        }
    }
    func testDarkShadowChangesOutsideFillButLightDoesNot() async throws {
        for dark in [false, true] {
            let base = RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .systemBackground)).frame(width: 250, height: 180)
            var ordinary: UIImage?
            try await mount(base, name: "shadow-off-\(dark)", dark: dark) { _, image in ordinary = image }
            try await mount(base.modifier(CompetitionResultsDarkShadow()), name: "shadow-on-\(dark)", dark: dark) { _, image in
                let first = try XCTUnwrap(ordinary?.pngData()), second = try XCTUnwrap(image.pngData())
                if dark { XCTAssertNotEqual(first, second) } else { XCTAssertEqual(first, second) }
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func mount<V: View>(_ view: V, name: String, dark: Bool, width: CGFloat = 430,
        check: (UIWindow, UIImage) throws -> Void) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: width, height: 960)
        window.overrideUserInterfaceStyle = dark ? .dark : .light; window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 550_000_000); host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let directory = URL(fileURLWithPath: "/tmp/cubeflow-unified-results-goal/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.pngData()?.write(to: directory.appendingPathComponent(name + ".png"))
        try check(window, image)
        host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition(); await Task.yield()
    }
}
