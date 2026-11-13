#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import CoreData
import CoreBluetooth
import SceneKit
@testable import CubeFlow

@MainActor final class PhysicalRecoveryPresentationTests: XCTestCase {
    private func sample(_ time: Double, event: String = "square-1") -> SessionSolveSample {
        .init(id: UUID(), date: .now, time: time, resultRaw: "solved", scramble: "", comment: "", eventRawValue: event)
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<400 { if predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Production presentation did not reach expected state"); throw CancellationError()
    }
    func testLargeSquareOneHistogramUsesIntegerSecondBinsWithoutHidingThePeak() {
        let input = (0..<4000).map { sample(8.5 + Double($0 % 450) / 100) }
        let start = ProcessInfo.processInfo.systemUptime
        let chart = SessionSolveTrend(solves: input)
        XCTAssertEqual(chart.bins.reduce(0) { $0 + $1.count }, 4000)
        XCTAssertTrue(chart.bins.allSatisfy { $0.upper - $0.lower == 1 && $0.lower.rounded() == $0.lower })
        XCTAssertLessThan(chart.bins.map(\.count).max() ?? 0, 1200)
        print("[PhysicalRecovery] histogram_4000_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) bins=\(chart.bins.count)")
    }
    func testHistogramHandlesSkewSparseOutliersAndFinalClosedBoundaryWithoutLosingCounts() {
        for values in [[Double](repeating: 10, count: 4000) + [3600], [0.0, 0.1, 0.3, 4], [8, 9, 10, 11, 12],
            (0..<4000).map { Double($0 * $0) / 100 }, [Double](repeating: 10, count: 3000) + (0..<1000).map { Double($0 * $0) }] {
            let chart = SessionSolveTrend(solves: values.map { sample($0) })
            XCTAssertEqual(chart.points.count, values.count)
            XCTAssertEqual(chart.bins.reduce(0) { $0 + $1.count }, values.count)
            XCTAssertLessThanOrEqual(chart.bins.count, 80)
            XCTAssertTrue(chart.bins.allSatisfy { $0.upper.isFinite && $0.upper > $0.lower })
        }
        let chart = SessionSolveTrend(solves: [8, 9, 10].map { sample($0) })
        XCTAssertEqual(chart.bins.last?.upper, 10)
        XCTAssertEqual(chart.bins.reduce(0) { $0 + $1.count }, 3)
        let invalid = SessionSolveTrend(solves: [sample(.nan), sample(.infinity), sample(-3)])
        XCTAssertTrue(invalid.points.isEmpty); XCTAssertTrue(invalid.bins.isEmpty)
    }
    func testSessionMenuCountsDoNotMaterializeSolveRelationshipsAndReadOwnStore() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let sessions = [Session(name: "One", context: context), Session(name: "Two", context: context)]
        for index in 0..<1000 { _ = Solve(time: 10, event: "3x3", session: sessions[index % 2], context: context) }
        try context.save()
        let ids = sessions.map(\.id), objects = sessions.map(\.objectID)
        context.reset()
        let reloaded = try objects.map { try XCTUnwrap(context.existingObject(with: $0) as? Session) }
        let reader = SessionSolveSnapshotReader(viewContext: context)
        let start = ProcessInfo.processInfo.systemUptime
        let counts = try await reader.counts(sessionIDs: ids)
        XCTAssertEqual(counts[ids[0]], 500); XCTAssertEqual(counts[ids[1]], 500)
        XCTAssertTrue(reloaded.allSatisfy { $0.hasFault(forRelationshipNamed: "solves") })
        print("[PhysicalRecovery] session_menu_count_1000_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
    }
    func testMountedDataSelectAllDeselectAllFollowCurrentFilterWithoutReplacingList() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Data recovery", context: context)
        for index in 0..<20 { _ = Solve(time: 10 + Double(index), event: "3x3", result: index.isMultiple(of: 2) ? .dnf : .solved, session: session, context: context) }
        try context.save()
        let defaults = UserDefaults.standard
        let values: [String: Any] = ["selectedSessionID": session.id.uuidString, "dataSolveResultFilter": "all"]
        let previous = values.map { ($0.key, defaults.object(forKey: $0.key)) }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        let probe = AppPerformanceProbe()
        var selectionMode = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: DataTabView(isSelectingSolves: Binding(
            get: { selectionMode }, set: { selectionMode = $0 }))
            .environment(\.managedObjectContext, context).environment(\.appPerformanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer {
            probe.dataSelect = nil; probe.dataToggleAll = nil; probe.dataSelection = nil
            window.isHidden = true; window.rootViewController = nil
            previous.forEach { defaults.set($0.1, forKey: $0.0) }
        }
        try await wait { probe.dataSelection?().visible.count == 20 }
        func lists(_ root: UIView) -> [UIScrollView] {
            (root as? UIScrollView).map { [$0] } ?? root.subviews.flatMap(lists)
        }
        try await wait { window.layoutIfNeeded(); return lists(window).contains { $0.contentSize.height > 500 } }
        let list = try XCTUnwrap(lists(window).first { $0.contentSize.height > 500 })
        probe.dataSelect?(true); probe.dataToggleAll?()
        XCTAssertEqual(probe.dataSelection?().selected.count, 20)
        defaults.set("dnf", forKey: "dataSolveResultFilter")
        try await wait { probe.dataSelection?().visible.count == 10 }
        XCTAssertEqual(probe.dataSelection?().selected.count, 10, "Filtering must prune hidden destructive selections")
        probe.dataToggleAll?()
        XCTAssertEqual(probe.dataSelection?().selected.count, 0, "Deselect all applicable filtered rows")
        XCTAssertTrue(probe.dataSelection?().selected.isDisjoint(with: probe.dataSelection?().visible ?? []) ?? false)
        probe.dataToggleAll?(); XCTAssertEqual(probe.dataSelection?().selected.count, 10)
        probe.dataSelect?(false)
        try await wait { probe.dataSelection?().selected.isEmpty == true }
        XCTAssertTrue(lists(window).contains { $0 === list }, "Selection must retain the list's scrolling owner")
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = appearance
            for selecting in [true, false, true, false] {
                probe.dataSelect?(selecting)
                try await wait { selectionMode == selecting }
                window.layoutIfNeeded()
                XCTAssertTrue(lists(window).contains { $0 === list })
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("build/physical-recovery-nov03/data-\(appearance.rawValue)-select-\(selecting).png")
                try image.pngData()?.write(to: path)
            }
        }
    }
    func testColdLocalizedNamesLoadBeforeDetailAndCoalesceConcurrentRequests() async throws {
        let previous = CompetitionService.localizedCompetitionNamesForTesting
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CompetitionLocalizedNameStore(directory: directory), calls = NameRequestCount()
        CompetitionService.localizedCompetitionNamesForTesting = (store, { _ in
            await calls.increment()
            return ["fixture": .init(slug: nil, name: "測試比賽", regionPrimary: nil, regionSecondary: nil, address: nil,
                registrationStart: nil, pauseRegistrationStart: nil, reopenRegistration: nil, registrationClose: nil)]
        })
        defer { CompetitionService.localizedCompetitionNamesForTesting = previous; try? FileManager.default.removeItem(at: directory) }
        let refs = [CompetitionNameReference(id: "fixture", name: "English", website: nil)]
        async let a = CompetitionService.localizedCompetitionDisplayNames(refs, languageCode: "zh-Hant", cachedOnly: false)
        async let b = CompetitionService.localizedCompetitionDisplayNames(refs, languageCode: "zh-Hans", cachedOnly: false)
        let (first, second) = await (a, b)
        XCTAssertEqual(first["fixture"], "測試比賽"); XCTAssertEqual(second["fixture"], "测试比赛")
        let count = await calls.value; XCTAssertEqual(count, 1)
        let english = await CompetitionService.localizedCompetitionDisplayNames(refs, languageCode: "en", cachedOnly: false)
        XCTAssertTrue(english.isEmpty)
        let afterEnglish = await calls.value; XCTAssertEqual(afterEnglish, 1)
    }
    func testReportHasNoBrandingAndReusesCompactOwnBluePRWithoutRecoloringOtherRecords() throws {
        let own = CompetitionShareRenderer.badgeImages(["PR", "NR", "CR", "WR"], compact: true, isOwn: true)
        let other = CompetitionShareRenderer.badgeImages(["PR", "NR", "CR", "WR"], compact: true, isOwn: false)
        let standard = CompetitionShareRenderer.badgeImages(["PR"])
        XCTAssertLessThan(try XCTUnwrap(own["PR"]).size.height, try XCTUnwrap(standard["PR"]).size.height)
        XCTAssertNotEqual(own["PR"]?.pngData(), other["PR"]?.pngData())
        for tag in ["NR", "CR", "WR"] { XCTAssertEqual(own[tag]?.pngData(), other[tag]?.pngData()) }
        let row = CompetitionShareRow(id: "round", eventID: "333", eventName: "3x3x3 Cube", round: "Final", rank: "1",
            average: "10.00", single: "9.00", attempts: ["9.00", "DNF", "DNS", "10.20+", "10.30"], averageBadge: "PR", singleBadge: "NR", isMean: false)
        let source = CompetitionExportSource(request: .init(mode: .report, context: .init(name: nil), name: "Competitor", rows: [row]),
            artwork: nil, badges: own, headers: ["Round", "Average", "Mean", "Best", "Results"], metricLabel: "", metricValue: "", metricBadge: nil)
        let plan = try CompetitionReportLayout.plan(source)
        let labels = plan.commands.compactMap { command -> String? in
            if case .text(let text, _, _, _, _, _) = command { return text }; return nil
        }
        XCTAssertFalse(labels.contains { $0.contains("CubeFlow") })
        XCTAssertTrue(labels.contains("Competition Report")); XCTAssertTrue(labels.contains("Competitor"))
        XCTAssertTrue(labels.contains { $0.contains("DNS") })
        let image = try XCTUnwrap(plan.draw())
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/native-ui-nov05/report-branding-fixture.png")
        try image.pngData()?.write(to: path)
    }
    func testActualBattlePanelsMountTwoIndependentCorrectSizeLiveModels() async throws {
        let saved = SavedSmartCubeDevices(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = SmartCubeBluetoothManager(testSavedDevices: saved), ids = [UUID(), UUID()]
        let sessions = ids.enumerated().map { index, id -> SmartCubePeripheralSession in
            let session = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
            session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: index == 0 ? 2 : 3), name: "Cube \(index)")
            manager.debugInstallSession(session, for: id); return session
        }
        let devices = LocalBattleDevices(manager: manager); devices.setEnabled(true)
        for (index, player) in LocalBattlePlayer.allCases.enumerated() {
            devices.setConfiguration(.init(input: .smartCube, deviceID: ids[index]), for: player)
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for mode in [LocalBattleMode.headToHead, .sideBySide] {
            let content = LocalBattleContent(mode: mode, firstEvent: .twoByTwo, secondEvent: .threeByThree, firstScramble: "R U", secondScramble: "F L",
                firstElapsed: 0, secondElapsed: 0, isFirstRunning: false, isSecondRunning: false,
                isFirstPressing: false, isSecondPressing: false, firstScore: 2, secondScore: 1, firstHandicapSeconds: 2, secondHandicapSeconds: 0,
                firstFinishedTime: nil, secondFinishedTime: nil, timerTextStyle: AnyShapeStyle(.primary), scrambleTextStyle: AnyShapeStyle(.primary),
                formatDisplayedTime: { String(format: "%.2f", $0) }, canSelectEvent: { _ in true }, onExit: {}, onSelectEvent: { _, _ in },
                onSelectHandicap: { _, _ in }, onPressPlayer: { _ in }, onReleasePlayer: { _ in }, onCancelPlayer: { _ in }, devices: devices)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = UIHostingController(rootView: content.background(Color(uiColor: .systemBackground)))
            window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            func cubes(_ root: UIView) -> [SCNView] { (root as? SCNView).map { [$0] } ?? root.subviews.flatMap(cubes) }
            try await wait { cubes(window).count == 2 }
            let owners = cubes(window).compactMap { SmartCube3DView.debugCoordinator(of: $0) }
            XCTAssertEqual(Set(owners.map { $0.debugPresentation.size }), [2, 3])
            let first = try XCTUnwrap(owners.first { $0.debugPresentation.size == 2 })
            let second = try XCTUnwrap(owners.first { $0.debugPresentation.size == 3 })
            let original = second.debugPresentation.canonical
            sessions[0].debugEmitPhysicalMove("R")
            XCTAssertEqual(first.debugPresentation.canonical, sessions[0].facelets)
            XCTAssertEqual(second.debugPresentation.canonical, original)
            sessions[1].debugEmitPhysicalMove("U")
            XCTAssertEqual(second.debugPresentation.canonical, sessions[1].facelets)
            try await wait { owners.allSatisfy { $0.debugPresentation.current == nil && $0.debugPresentation.pending.isEmpty } }
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("build/physical-recovery-nov03/battle-\(mode.rawValue).png")
            try image.pngData()?.write(to: path)
            for (index, view) in cubes(window).enumerated() {
                XCTAssertGreaterThan(view.bounds.width, 40)
                XCTAssertGreaterThan(view.bounds.height, 40)
                let snapshot = view.snapshot()
                XCTAssertNotNil(snapshot.cgImage)
                try snapshot.pngData()?.write(to: path.deletingLastPathComponent().appendingPathComponent("battle-\(mode.rawValue)-cube-\(index).png"))
            }
        }
        devices.setEnabled(false)
    }
}
private actor NameRequestCount { var value = 0; func increment() { value += 1 } }
#endif
