import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class CompetitionPhysicalRegressionTests: XCTestCase {
    func testNativeFilterPreservesOriginalEventMultiSelection() throws {
        let all = Set(CompetitionEventFilter.selectableCases)
        let first = try XCTUnwrap(CompetitionEventFilter.selectableCases.first)
        let second = try XCTUnwrap(CompetitionEventFilter.selectableCases.dropFirst().first)
        XCTAssertEqual(CompetitionEventFilter.selection(afterToggling: first, in: all), [first])
        XCTAssertEqual(CompetitionEventFilter.selection(afterToggling: second, in: [first]), [first, second])
        XCTAssertEqual(CompetitionEventFilter.selection(afterToggling: first, in: [first, second]), [second])
        XCTAssertEqual(CompetitionEventFilter.selection(afterToggling: first, in: [first]), all)
        XCTAssertEqual(CompetitionEventFilter.selection(afterToggling: .all, in: [second]), all)
    }

    func testSumDefaultViewportNeverExposesPartialCountAtAnyWidth() {
        for scale in [CGFloat(1), 1.25, 1.8, 2.2] {
            for width in stride(from: CGFloat(280), through: 800, by: 1) {
                let columns = CompetitionSumRankColumns(width: width, scale: scale)
                XCTAssertTrue(columns.countOrigin >= width - 0.01 || columns.countOrigin + columns.count <= width + 0.01)
                XCTAssertGreaterThanOrEqual(columns.name, 84 * scale - 0.01)
                XCTAssertGreaterThanOrEqual(columns.region, 104 * scale - 0.01)
            }
        }
    }

    func testBeijingColdLoaderInRealFlowCellsBothAppearancesKeepsDisclosureStationary() async throws {
        let competition = CompetitionPhysicalRegressionFixtures.beijing
        let values = try XCTUnwrap(CompetitionService.decodeCompetitionTopCuberPreviews(
            CompetitionPhysicalRegressionFixtures.beijingWCIF, eventIDs: competition.eventIDs))
        for glass in [false, true] {
            let state = CompetitionDisclosureAcceptanceState()
            let root = CompatibleNavigationContainer {
                CompetitionDisclosureAcceptanceSurface(state: state, controlled: true, boundary: false, glass: glass,
                    productionTop: .init(competition: competition, values: values))
                    .navigationTitle(competition.name)
            }
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = UIHostingController(rootView: root)
            window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            for _ in 0..<60 where state.visibility == nil { try await Task.sleep(nanoseconds: 50_000_000) }
            XCTAssertEqual(state.topState, .loaded(values))
            let visibility = try XCTUnwrap(state.visibility)
            XCTAssertEqual(visibility.total, 16)
            XCTAssertLessThan(visibility.collapsed, 16)
            XCTAssertEqual(visibility.visible, visibility.collapsed)
            let collection = try XCTUnwrap(allViews(window).compactMap { $0 as? UICollectionView }.first)
            let height = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 1, section: 0))).frame.height
            for expanded in [true, false, true, false] {
                CompetitionDisclosureViewportProbe.shared.begin()
                withAnimation(.easeInOut(duration: 0.32)) { state.expanded = expanded }
                try await Task.sleep(nanoseconds: 700_000_000)
                XCTAssertEqual(state.visibility?.visible, expanded ? 16 : visibility.collapsed)
                let currentHeight = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 1, section: 0))).frame.height
                if expanded { XCTAssertGreaterThan(currentHeight, height + 1) }
                else { XCTAssertEqual(currentHeight, height, accuracy: 1) }
                for _ in 0..<100 where !(collection.accessibilityValue ?? "").hasPrefix("{") {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                let trace = try XCTUnwrap(JSONSerialization.jsonObject(with: Data((collection.accessibilityValue ?? "").utf8)) as? [String: Any])
                for key in ["unexpected", "presentationDrift", "cellOriginDrift", "viewportOriginDrift"] {
                    XCTAssertLessThanOrEqual(try XCTUnwrap(trace[key] as? Double), 1, key)
                }
            }
        }
    }

    private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }

    func testOfficialSelectionPublishesWithAlreadyAvailableIdentityAndAllResults() throws {
        let rows = try PublishedCompetitionService.decodeResults(
            CompetitionPhysicalRegressionFixtures.beijingPublishedResults, competitionID: "BeijingAutumnRivalry2026")
        let data = PublishedCompetitionData(competitionID: "BeijingAutumnRivalry2026", results: rows)
        let content = try XCTUnwrap(PublishedCompetitionPresentation.competitor("2016KOLA02", data: data, language: "en"))
        XCTAssertEqual(content.results.count, 14)
        XCTAssertEqual(content.countryISO2, "PL")
        let card = CompetitionResultCardState()
        var visibleAtSelection: CompetitionWCALiveCompetitorContent?
        let observation = card.$selection.sink { selection in
            if selection?.entry == .competition { visibleAtSelection = card.selectedCompetitorContent }
        }
        card.presentCompetition(id: "2016KOLA02", name: content.name, isPublished: true, content: content)
        XCTAssertEqual(visibleAtSelection, content, "The production overlay must receive content before its first selection-driven mount")
        withExtendedLifetime(observation) {}
    }

    func testCompleteDownloadedBeijingWCIFDecodesThroughProductionParser() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/competition-physical-regressions/beijing-wcif.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("Local live-response validation; deterministic captured tests remain available")
        }
        let values = try XCTUnwrap(CompetitionService.decodeCompetitionTopCuberPreviews(
            Data(contentsOf: path), eventIDs: CompetitionPhysicalRegressionFixtures.eventIDs))
        XCTAssertEqual(values.count, 16)
    }

    func testBeijingPublicWCIFHasActualTopCubers() throws {
        let values = try XCTUnwrap(CompetitionService.decodeCompetitionTopCuberPreviews(
            CompetitionPhysicalRegressionFixtures.beijingWCIF,
            eventIDs: CompetitionPhysicalRegressionFixtures.eventIDs))
        XCTAssertEqual(values.count, 16)
        XCTAssertTrue(values.contains { $0.id == "2016KOLA02" && !$0.badges.isEmpty })
        XCTAssertTrue(values.contains { $0.id == "2019TARA09" && $0.badges.contains { $0.tier == .wr } })
    }

    func testColdProductionTopCubersViewActuallyStartsItsTask() async throws {
        let summary = CompetitionPhysicalRegressionFixtures.beijing
        let values = try XCTUnwrap(CompetitionService.decodeCompetitionTopCuberPreviews(
            CompetitionPhysicalRegressionFixtures.beijingWCIF, eventIDs: summary.eventIDs))
        var fetched = false
        var observed: CompetitionTopCuberLoadState = .idle
        let root = VStack(alignment: .leading) {
            Text(summary.name)
            CompetitionLoadedTopCubers(competition: summary, language: "en", initial: .idle,
                onState: { observed = $0 }, cache: { id in
                    XCTAssertEqual(id, summary.id); return nil
                }, fetch: { competition, _ in
                    XCTAssertEqual(competition.id, summary.id)
                    fetched = true; return values
                }) { previews in
                    Text("Top Cubers")
                    CompetitionExpandableTopCubers(previews: previews, language: "en") { preview in
                        Text(preview.name).font(.system(size: 13))
                    }
                } placeholder: { ProgressView() }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: root)
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<40 where !fetched { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(fetched, "The real mounted component must start from idle, not only an explicitly invoked model")
        XCTAssertEqual(observed, .loaded(values))
    }
}
