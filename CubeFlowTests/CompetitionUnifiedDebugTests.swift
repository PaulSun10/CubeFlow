import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CompetitionUnifiedDebugTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var domain: String!
    private var original: CompetitionDebugStore!
    override func setUp() async throws {
        try await super.setUp()
        domain = "UnifiedDebugTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: domain)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent(domain, isDirectory: true)
        original = CompetitionDebugStore.shared
        CompetitionDebugStore.shared = CompetitionDebugStore(defaults: defaults, root: root)
    }
    override func tearDown() async throws {
        CompetitionDebugStore.shared.stop(.filter)
        CompetitionDebugStore.shared.stop(.separator)
        CompetitionDebugStore.shared = original
        defaults.removePersistentDomain(forName: domain)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }
    func testFreshOffPersistenceMigrationAndNoAutomaticRecording() throws {
        let store = CompetitionDebugStore.shared
        XCTAssertFalse(store.enabled)
        store.start(.filter)
        XCTAssertFalse(store.filterRecording)
        store.setEnabled(true)
        XCTAssertTrue(defaults.bool(forKey: CompetitionTopCubersDebugBounds.key))
        XCTAssertFalse(store.filterRecording); XCTAssertFalse(store.separatorRecording)
        XCTAssertFalse(SmartCubeDiagnostics.shared.enabled, "The master switch alone must not start protocol traces")
        let relaunched = CompetitionDebugStore(defaults: defaults, root: root)
        XCTAssertTrue(relaunched.enabled)
        defaults.removeObject(forKey: CompetitionDebugStore.key)
        defaults.set(true, forKey: "competitionTopCubersDebugBounds")
        let migrated = CompetitionDebugStore(defaults: defaults, root: root)
        XCTAssertTrue(migrated.enabled)
        XCTAssertNil(defaults.object(forKey: "competitionTopCubersDebugBounds"))
    }
    func testFilterStopsOnMasterOffRetainsAndExportsThroughNativeCoordinator() throws {
        let store = CompetitionDebugStore.shared
        store.setEnabled(true); store.start(.filter)
        let presentation = CompetitionFilterPresentation()
        presentation.open(); presentation.close(); presentation.open()
        for index in 0..<600 { CompetitionFilterTrace.event("touch-test", generation: index, fields: ["actualTargetPath": ["UIHostingView"]]) }
        store.start(.separator)
        store.setEnabled(false)
        XCTAssertFalse(store.filterRecording); XCTAssertFalse(store.separatorRecording)
        let capture = try XCTUnwrap(store.captures.first)
        let metadata = try store.metadata(capture)
        let events = try XCTUnwrap(metadata["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 512)
        XCTAssertEqual(events.last?["reason"] as? String, "debug-mode-off")
        XCTAssertGreaterThan(metadata["droppedEvents"] as? Int ?? 0, 0)
        CompetitionFilterTrace.event("must-not-record")
        XCTAssertEqual(try store.metadata(capture)["events"] as? NSArray, events as NSArray)
        let archive = try store.export(capture)
        XCTAssertEqual(Array(try Data(contentsOf: archive).prefix(2)), [0x50, 0x4b])
        let relaunched = CompetitionDebugStore(defaults: defaults, root: root)
        XCTAssertEqual(relaunched.captures.count, 1)
        XCTAssertFalse(relaunched.filterRecording)
        store.clear(.filter)
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }
    func testFilterSettingsCompetitionNavigationAndImmediateObserverDetach() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let anchor = CompetitionFilterInputAnchor(frame: CGRect(x: 300, y: 50, width: 44, height: 44), recordingEnabled: false)
        window.addSubview(anchor)
        func count() -> Int { window.gestureRecognizers?.filter { $0 is CompetitionFilterTouchObserver }.count ?? 0 }
        XCTAssertEqual(count(), 0)
        let store = CompetitionDebugStore.shared
        store.setEnabled(true); store.start(.filter)
        XCTAssertEqual(count(), 1)
        CompetitionFilterTrace.event("toolbar-action")
        anchor.removeFromSuperview() // Navigate to Settings: mounted Browser can be destroyed.
        XCTAssertEqual(count(), 0)
        XCTAssertTrue(store.filterRecording)
        window.addSubview(anchor) // Return to Competitions, including fresh hosting ownership.
        XCTAssertEqual(count(), 1)
        CompetitionFilterTrace.event("open-request")
        store.stop(.filter)
        XCTAssertEqual(count(), 0)
        let events = try XCTUnwrap(try store.metadata(XCTUnwrap(store.captures.first))["events"] as? [[String: Any]])
        XCTAssertTrue(events.contains { $0["event"] as? String == "toolbar-action" })
        XCTAssertTrue(events.contains { $0["event"] as? String == "open-request" })
        store.start(.filter); XCTAssertEqual(count(), 1)
        store.setEnabled(false); XCTAssertEqual(count(), 0)
    }
    func testFixedCapacityNeverEvictsSavedEvidenceOnNewStartOrModeOff() throws {
        let store = CompetitionDebugStore.shared
        for _ in 0..<4 { _ = try store.save(kind: .filter, metadata: ["events": []]) }
        let ids = store.captures.map(\.id)
        store.setEnabled(true); store.start(.filter)
        XCTAssertFalse(store.filterRecording)
        store.setEnabled(false)
        XCTAssertEqual(store.captures.map(\.id), ids)
    }
    func testSeparatorActualSnapshotAssociationIdentitySelectionAndScreenshotImport() async throws {
        let store = CompetitionDebugStore.shared
        store.setEnabled(true); store.start(.separator)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let rows = VStack(spacing: 0) {
            ForEach(1..<5) { index in
                CompetitionResultRoundRow(showsBoundary: index > 1) { Text("Result \(index)").frame(width: 300, height: 36) }
                    .competitionSeparatorIdentity(event: "333", beforeID: "r\(index - 1)", before: "Round \(index - 1)", afterID: "r\(index)", after: "Round \(index)")
            }
        }.frame(width: 300)
        window.rootViewController = UIHostingController(rootView: rows)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<12 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 30_000_000) }
        let viewport = CompetitionSeparatorCardAnchor(frame: window.bounds)
        window.addSubview(viewport)
        let capture = try viewport.capture()
        var metadata = try store.metadata(capture)
        let lines = try JSONDecoder().decode([CompetitionSeparatorLine].self,
            from: JSONSerialization.data(withJSONObject: metadata["lines"] ?? []))
        XCTAssertEqual(lines.count, 3)
        let line = try XCTUnwrap(lines.first { $0.label == "Round 2 → Round 3" })
        let size = window.bounds.size
        XCTAssertEqual(CompetitionSeparatorLine.nearest(to: CGPoint(x: (line.x0 + line.x1) / 2 * size.width, y: line.y * size.height), size: size, lines: lines), line)
        XCTAssertNil(CompetitionSeparatorLine.nearest(to: .zero, size: size, lines: lines))
        var selection = CompetitionSeparatorSelection()
        selection.toggle(line.id); selection.toggle(lines[0].id)
        XCTAssertEqual(selection.ids.count, 2)
        selection.toggle(line.id); XCTAssertEqual(selection.ids.count, 1)
        selection.undo(); XCTAssertEqual(selection.ids.count, 2)
        selection.clear(); XCTAssertTrue(selection.ids.isEmpty)
        selection.undo(); XCTAssertEqual(selection.ids.count, 2)
        metadata["selectedSeparatorIDs"] = selection.ids
        try store.update(capture, metadata: metadata)
        XCTAssertEqual(try store.metadata(capture)["selectedSeparatorIDs"] as? [String], selection.ids)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.directory.appendingPathComponent("snapshot.png").path))
        XCTAssertNotNil(metadata["wallTime"])
        XCTAssertEqual((metadata["boundaries"] as? [[String: Any]])?.count, 3)
        let screen = window.screen.bounds.size
        let systemImage = UIGraphicsImageRenderer(size: screen).image { context in UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: screen)) }
        let imported = try CompetitionSeparatorScreenshotImport.cropped(XCTUnwrap(systemImage.pngData()), metadata: metadata)
        XCTAssertNotNil(UIImage(data: imported))
        XCTAssertThrowsError(try CompetitionSeparatorScreenshotImport.cropped(Data(), metadata: metadata))
        metadata["authoritativeImage"] = "system-screenshot.png"
        try store.update(capture, metadata: metadata, image: imported)
        let zip = try store.export(capture)
        XCTAssertGreaterThan(try Data(contentsOf: zip).count, 100)
        let evidence = XCTAttachment(data: try Data(contentsOf: zip), uniformTypeIdentifier: "public.zip-archive")
        evidence.name = "separator-coherent-bundle"; evidence.lifetime = .keepAlways; add(evidence)
        store.setEnabled(false)
        XCTAssertEqual(store.captures.count, 1)
        XCTAssertThrowsError(try viewport.capture())
        store.clear(.separator)
        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.directory.path))
    }
    func testMasterOffImmediatelyFinalizesActualCollectionScrollWithoutLosingOwners() async throws {
        let store = CompetitionDebugStore.shared
        store.setEnabled(true)
        let key = CompetitionScrollOwnerDiagnostics.enabledKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        CompetitionScrollCaptureStore.shared.clear()
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            CompetitionScrollCaptureStore.shared.clear()
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let layout = UICollectionViewFlowLayout(); layout.itemSize = CGSize(width: 300, height: 150)
        let list = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        window.rootViewController?.view.addSubview(list)
        list.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "row")
        let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: list) { collection, index, _ in
            collection.dequeueReusableCell(withReuseIdentifier: "row", for: index)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0]); snapshot.appendItems(["competition:fixture:1"])
        await source.apply(snapshot, animatingDifferences: false)
        window.layoutIfNeeded(); list.layoutIfNeeded()
        let trace = CompetitionLongScrollTrace()
        trace.begin(list); trace.sample(list, capturesOwners: true)
        store.setEnabled(false)
        let capture = try XCTUnwrap(CompetitionScrollCaptureStore.shared.captures.first)
        XCTAssertEqual(capture["finalizationReason"] as? String, "recording-disabled")
        XCTAssertFalse((capture["owners"] as? [[String: Any]] ?? []).isEmpty)
        trace.sample(list, capturesOwners: true)
        XCTAssertEqual(CompetitionScrollCaptureStore.shared.captures.count, 1)
    }

    func testNativeResultCardReceivesCompetitionAndRealRoundContextWithoutNavigationChanges() async throws {
        let store = CompetitionDebugStore.shared
        store.setEnabled(true); store.start(.separator)
        let results = (1...3).map { (number: Int) -> CompetitionWCALiveCompetitorResult in
            CompetitionWCALiveCompetitorResult(id: "result-\(number)", ranking: 1, isAdvancing: true, isAdvancingQuestionable: false,
                attempts: [852, 913, 876, 941, 893], best: 852, average: 893, singleRecordTag: nil, averageRecordTag: nil,
                roundID: "333-r\(number)", roundName: "Round \(number)", roundNumber: number, eventID: "333", eventName: "3x3x3 Cube",
                eventRank: 0, formatID: "a", numberOfAttempts: 5, sortBy: "average")
        }
        let card = CompetitionResultCardState()
        let content = CompetitionWCALiveCompetitorContent(id: "fixture-person", name: "Fixture Cuber", wcaID: nil, countryISO2: nil, results: results)
        let root = Color.white.competitionResultsPresentation(state: card, language: "en").competitionDebugCompetition("fixture-competition")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.rootViewController = UIHostingController(rootView: root); window.makeKeyAndVisible()
        defer { card.close(); window.isHidden = true; window.rootViewController = nil }
        card.presentCompetition(id: content.id, name: content.name, content: content)
        func children(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(children) }
        for _ in 0..<30 {
            window.layoutIfNeeded()
            if children(window).contains(where: { $0 is CompetitionSeparatorCardAnchor }) { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        for _ in 0..<12 { window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 30_000_000) }
        let viewport = try XCTUnwrap(children(window).compactMap { $0 as? CompetitionSeparatorCardAnchor }.first)
        let capture = try viewport.capture()
        let metadata = try store.metadata(capture)
        XCTAssertEqual(metadata["competitionID"] as? String, "fixture-competition")
        let boundaries = try XCTUnwrap(metadata["boundaries"] as? [[String: Any]])
        XCTAssertTrue(boundaries.contains {
            let identity = $0["identity"] as? [String: String]
            return identity?["beforeRoundID"] == "333-r2" && identity?["afterRoundID"] == "333-r3"
                && identity?["competitionID"] == "fixture-competition" && identity?["eventID"] == "333"
        }, String(describing: boundaries.compactMap { $0["identity"] }))
        XCTAssertEqual(card.selection?.entry, .competition)
    }

    func testClippedRowOwnerCannotCreateAVisibleSeparatorOutsideItsClip() {
        let boundary: [String: Any] = ["visibleFrameInWindow": [0.0, 80.0, 300.0, 20.0], "windowPaintY": 50.0,
            "identity": ["eventID": "333", "beforeRound": "Round 1", "afterRound": "Round 2", "boundaryID": "333-r1-r2"]]
        let crop = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertTrue(CompetitionSeparatorLine.mapped([boundary], crop: crop).isEmpty)
        var visible = boundary; visible["windowPaintY"] = 90.0
        XCTAssertEqual(CompetitionSeparatorLine.mapped([visible], crop: crop).count, 1)
    }

}
