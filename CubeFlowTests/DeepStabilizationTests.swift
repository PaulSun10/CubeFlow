import XCTest
import SwiftUI
import SceneKit
import Combine
import CoreBluetooth
import WebKit
@testable import CubeFlow

@MainActor final class DeepStabilizationTests: XCTestCase {
    func testMeasureMountedIdleRendererCallbacks() async throws {
        let owner = SmartCube3DView.Coordinator(), view = owner.makeView()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController(); window.rootViewController = host
        host.view.addSubview(view); view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        window.makeKeyAndVisible()
        defer { owner.stop(); window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 150_000_000)
        let before = owner.debugDisplayLinkTicks
        try await Task.sleep(nanoseconds: 500_000_000)
        print("[DeepPerf] mounted_idle_ms=500 callbacks=\(owner.debugDisplayLinkTicks - before) continuous=\(view.rendersContinuously) clock=\(owner.debugClockIsActive)")
        XCTAssertEqual(owner.debugDisplayLinkTicks, before)
        XCTAssertTrue(owner.debugClockIsPaused)
        XCTAssertFalse(view.rendersContinuously)
    }

    func testMeasureLongReportSynchronousRender() throws {
        let rows = (0..<128).map { index in
            CompetitionShareRow(id: "\(index)", eventID: "333", eventName: "3x3x3 Cube", round: "Round \(index + 1)",
                rank: "1", average: "10.01", single: "9.00", attempts: ["9.00", "10.00", "11.00", "10.01", "10.02"],
                averageBadge: "NR", singleBadge: "PR", isMean: false)
        }
        let request = CompetitionShareRequest(mode: .report, context: .init(name: "Benchmark"), name: "Fixture", rows: rows)
        let start = ProcessInfo.processInfo.systemUptime
        let image = try XCTUnwrap(CompetitionShareRenderer.render(request, metric: .average, artwork: nil, language: "en"))
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let cg = try XCTUnwrap(image.cgImage)
        print("[DeepPerf] report_rows=128 synchronous_main_ms=\(elapsed) bitmap_bytes=\(cg.bytesPerRow * cg.height) pixels=\(cg.width)x\(cg.height)")
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        XCTFail("Lifecycle did not reach expected state"); throw CancellationError()
    }

    func testRendererWakesForTurnsAndSleepsAfterSettlingAndBackgroundsWithoutBacklog() async throws {
        let owner = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed(), view = owner.makeView()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view); view.frame = CGRect(x: 0, y: 0, width: 220, height: 220)
        window.makeKeyAndVisible()
        defer {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            owner.stop(); window.isHidden = true; window.rootViewController = nil
        }
        var state = CubeSurface.solved(size: 3)
        owner.update(facelets: state, stateRevision: 0, fixedView: .urf, size: 3, events: feed.events,
            attemptID: UUID(), trusted: true, tps: 10, appearance: .classic, plastic: .black,
            reflections: false, customColor: .purple, canonicalSequence: 0)
        func turn(_ notation: String) throws {
            state = try XCTUnwrap(CubeLayerTurn(notation)?.applying(to: state, size: 3))
            feed.send(move: .init(move: notation, serial: nil, face: nil, direction: nil,
                localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: state)
        }
        XCTAssertTrue(owner.debugClockIsPaused)
        try turn("R")
        XCTAssertFalse(owner.debugClockIsPaused)
        try await wait { owner.debugPresentation.current == nil }
        XCTAssertEqual(owner.debugPresentation.settled, state); XCTAssertTrue(owner.debugClockIsPaused)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(owner.debugClockIsActive)
        for move in ["U", "F", "R2", "B"] { try turn(move) }
        XCTAssertEqual(owner.debugPresentation.settled, state); XCTAssertNil(owner.debugPresentation.current)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(owner.debugClockIsActive); XCTAssertTrue(owner.debugClockIsPaused)
        try turn("L2"); XCTAssertFalse(owner.debugClockIsPaused)
        try await wait { owner.debugPresentation.current == nil }
        XCTAssertEqual(owner.debugPresentation.settled, state)
    }

    private func pair() -> (LocalBattleDevices, [SmartCubePeripheralSession], [UUID]) {
        let manager = SmartCubeBluetoothManager(testSavedDevices: SavedSmartCubeDevices(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let ids = [UUID(), UUID()]
        let sessions = ids.map { id -> SmartCubePeripheralSession in
            let session = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
            session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
            manager.debugInstallSession(session, for: id); return session
        }
        let owner = LocalBattleDevices(manager: manager); owner.setEnabled(true)
        for (index, player) in LocalBattlePlayer.allCases.enumerated() {
            owner.setConfiguration(.init(input: .smartCube, deviceID: ids[index]), for: player)
            owner.setTarget(index == 0 ? "R" : "U", event: .threeByThree, assignment: UUID(), for: player)
        }
        return (owner, sessions, ids)
    }

    func testNoOpBattleUpdatesDoNotPublishOrResetReadyPlayers() {
        let (owner, sessions, ids) = pair(); defer { owner.setEnabled(false) }
        sessions[0].debugEmitPhysicalMove("R"); sessions[1].debugEmitPhysicalMove("U")
        let assignment = UUID(); owner.setTarget("R", event: .threeByThree, assignment: assignment, for: .first)
        var publications = 0
        let token = owner.$ready.dropFirst().sink { _ in publications += 1 }
        defer { token.cancel() }
        for _ in 0..<100 {
            owner.setEnabled(true)
            owner.setConfiguration(.init(input: .smartCube, deviceID: ids[0]), for: .first)
            owner.setTarget("R", event: .threeByThree, assignment: assignment, for: .first)
        }
        XCTAssertEqual(owner.ready.count, 2); XCTAssertEqual(publications, 0)
    }

    func testPartialRoundRestorationAllowsOpponentButNextRoundRestoresBothReadyGate() {
        let (owner, sessions, _) = pair(); defer { owner.setEnabled(false) }
        sessions[0].debugEmitPhysicalMove("R"); sessions[1].debugEmitPhysicalMove("U")
        owner.start = { _, _ in true }; sessions[0].debugEmitPhysicalMove("R'")
        owner.setEnabled(false); owner.setEnabled(true)
        owner.setTarget("F", event: .threeByThree, assignment: UUID(), for: .first)
        owner.setTarget("U", event: .threeByThree, assignment: UUID(), for: .second)
        owner.complete(.first)
        var starts: [LocalBattlePlayer] = []
        owner.start = { player, _ in starts.append(player); return true }
        sessions[1].debugEmitPhysicalMove("U'")
        XCTAssertEqual(starts, [.second])
        owner.nextRound()
        sessions[0].debugEmitPhysicalMove("F"); sessions[0].debugEmitPhysicalMove("F'")
        XCTAssertEqual(starts, [.second], "A new round must not inherit the prior round's joint readiness")
    }

    func testQueuedBriefDisconnectIsNotLostByReadingNewerConnectedState() async throws {
        let (owner, sessions, ids) = pair(); defer { owner.setEnabled(false) }
        sessions[0].debugEmitPhysicalMove("R"); sessions[1].debugEmitPhysicalMove("U")
        owner.start = { _, _ in true }
        sessions[0].debugEmitPhysicalMove("R"); sessions[1].debugEmitPhysicalMove("U")
        var cancelled: [LocalBattlePlayer] = [], finished: [LocalBattlePlayer] = []
        owner.invalidate = { cancelled.append($0) }; owner.finish = { player, _ in finished.append(player) }
        let attempt = try XCTUnwrap(sessions[0].connectionAttemptID)
        sessions[0].debugSeedConnectionPhase(.disconnected, deviceID: ids[0], attemptID: attempt)
        sessions[0].debugSeedConnectionPhase(.connected, deviceID: ids[0], attemptID: attempt)
        try await wait { cancelled == [.first] }
        sessions[1].debugEmitPhysicalMove("U2")
        XCTAssertEqual(finished, [.second])
    }

    func testCompletedGuidanceDeduplicatesButCancelAndABAStillScheduleLatest() async throws {
        let counter = DeepSearchCounter()
        let owner = SmartCubeGuidanceController(settle: {}, search: { request in
            await counter.hit(); return await SmartCubeReplacementPlanner.shortStateDecision(request)
        })
        defer { owner.cancel() }
        let solved = CubeSurface.solved(size: 3), identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
        let first = SmartCubeGuidanceController.Request(identity: identity,
            sourceFacelets: try XCTUnwrap(CubeLayerTurn("R")?.applying(to: solved, size: 3)), targetFacelets: solved, generation: 0, knownPath: nil)
        let second = SmartCubeGuidanceController.Request(identity: identity,
            sourceFacelets: try XCTUnwrap(CubeLayerTurn("U")?.applying(to: solved, size: 3)), targetFacelets: solved, generation: 0, knownPath: nil)
        for _ in 0..<100 { owner.submit(first) }
        try await wait { owner.publication != nil }
        for _ in 0..<100 { owner.submit(first) }
        let initial = await counter.count; XCTAssertEqual(initial, 1)
        owner.cancel(); owner.submit(first)
        try await wait { owner.publication != nil }
        let retry = await counter.count; XCTAssertEqual(retry, 2)
        owner.submit(second); owner.submit(first)
        XCTAssertEqual(owner.currentRequest, first)
        try await wait { owner.publication?.request == first }
    }

    func testRapidNavigationRejectsOldTargetsAndReleasesCancelledOwner() async throws {
        var model: GuidanceStateTestHarness? = GuidanceStateTestHarness()
        weak var weakModel = model
        let device = UUID(), attempt = UUID()
        model?.setScramble("R U")
        var state = CubeSurface.solved(size: 3)
        for index in 0..<200 {
            state = try XCTUnwrap(CubeLayerTurn(index.isMultiple(of: 2) ? "F" : "F'")?.applying(to: state, size: 3))
            model?.update(facelets: state, trusted: true, deviceID: device, attemptID: attempt, sequence: UInt64(index))
        }
        model?.setScramble("B")
        model?.update(facelets: state, trusted: true, deviceID: device, attemptID: UUID(), sequence: 200)
        try await wait { model?.route != nil }
        XCTAssertEqual(model?.route?.tokens, ["B"])
        model?.cancel(); model = nil
        XCTAssertNil(weakModel)
    }

    func testLongExportsUseBoundedBitmapsAndSerializedBackgroundWork() async throws {
        func request(_ count: Int) -> CompetitionShareRequest {
            let rows = (0..<count).map { CompetitionShareRow(id: "\($0)", eventID: "333", eventName: "3x3x3 Cube", round: "Round \($0 + 1)", rank: "1",
                average: "10.00", single: "9.00", attempts: ["9.00", "10.00", "DNF", "DNS", "10.20"], averageBadge: "NR", singleBadge: "PR", isMean: false) }
            return .init(mode: .report, context: .init(name: "Benchmark"), name: "Fixture", rows: rows)
        }
        let start = ProcessInfo.processInfo.systemUptime
        let rendered = await CompetitionShareRenderer.export(request(128), metric: .average, artwork: nil, language: "en")
        let image = try XCTUnwrap(rendered)
        let cg = try XCTUnwrap(image.cgImage)
        print("[DeepPerf] report_rows=128 prepare_main_ms=\(CompetitionShareRenderer.debugPreparationMilliseconds) total_async_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) bitmap_bytes=\(cg.bytesPerRow * cg.height)")
        let jobs = [32, 128, 256].map { count in Task { await CompetitionShareRenderer.export(request(count), metric: .average, artwork: nil, language: "en") } }
        for job in jobs {
            let output = await job.value
            let bitmap = try XCTUnwrap(output?.cgImage)
            XCTAssertLessThan(bitmap.bytesPerRow * bitmap.height, 50_000_000)
        }
        let metrics = await CompetitionShareRenderer.debugWorkerMetrics()
        XCTAssertEqual(metrics.maximum, 1); XCTAssertFalse(metrics.main)
        let cancelled = Task { await CompetitionShareRenderer.export(request(256), metric: .average, artwork: nil, language: "en") }
        cancelled.cancel()
        let discarded = await cancelled.value; XCTAssertNil(discarded)
    }

    func testFastTwoByTwoSolvedCheckMatchesFullFrameMatcherIncludingAllColorPermutations() throws {
        let solved = CubeSurface.solved(size: 2)
        func permutations(_ values: [Character]) -> [[Character]] {
            if values.isEmpty { return [[]] }
            return values.indices.flatMap { index in
                permutations(Array(values[..<index]) + Array(values[(index + 1)...])).map { [values[index]] + $0 }
            }
        }
        var accepted = 0
        for colors in permutations(Array("URFDLB")) {
            let state = colors.map { String(repeating: String($0), count: 4) }.joined()
            let reference = CubeStateEquivalence.matches(state, solved, puzzleSize: 2)
            XCTAssertEqual(CubeStateEquivalence.isSolved(state, puzzleSize: 2), reference)
            if reference { accepted += 1 }
        }
        XCTAssertEqual(accepted, 24)
        var state = solved
        for index in 0..<128 {
            state = try XCTUnwrap(CubeLayerTurn(SmartCubeTargetPath.moves[(index * 7) % 18])?.applying(to: state, size: 2))
            XCTAssertEqual(CubeStateEquivalence.isSolved(state, puzzleSize: 2), CubeStateEquivalence.matches(state, solved, puzzleSize: 2))
        }
        for invalid in ["", String(repeating: "U", count: 24), "UUUURRRRFFFFDDDDLLLLBBB?", solved + " "] {
            XCTAssertFalse(CubeStateEquivalence.isSolved(invalid, puzzleSize: 2))
        }
        var checksum = 0
        var before: [Double] = [], after: [Double] = []
        for _ in 0..<3 {
            var start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<1000 { if CubeStateEquivalence.matches(state, solved, puzzleSize: 2) { checksum += 1 } }
            before.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<1000 { if CubeStateEquivalence.isSolved(state, puzzleSize: 2) { checksum += 1 } }
            after.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        XCTAssertEqual(checksum % 2, 0)
        print("[DeepPerf] two_by_two_solved_checks=1000 reference_ms=\(before) fast_ms=\(after)")
    }

    func testLongReportIncludesFinalRowBadgeInExportedPixels() async throws {
        let rows = (0..<256).map { index in
            CompetitionShareRow(id: "\(index)", eventID: "333", eventName: "3x3x3 Cube", round: "Round \(index + 1)",
                rank: "1", average: "10.00", single: "9.00", attempts: ["9.00", "10.00", "DNF", "DNS", "10.20"],
                averageBadge: index == 255 ? "WR" : nil, singleBadge: nil, isMean: false)
        }
        let request = CompetitionShareRequest(mode: .report, context: .init(name: "Complete report"), name: "Fixture", rows: rows)
        let output = await CompetitionShareRenderer.export(request, metric: .average, artwork: nil, language: "en")
        let image = try XCTUnwrap(output), cg = try XCTUnwrap(image.cgImage)
        // Only the final row has red WR ink. Inspect the last two rows plus
        // footer, not the full image, to detect accidental bottom clipping.
        let height = min(cg.height, Int(ceil(120 * image.scale)))
        let bottom = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: cg.height - height, width: cg.width, height: height)))
        var pixels = [UInt8](repeating: 0, count: bottom.width * bottom.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: bottom.width, height: bottom.height,
            bitsPerComponent: 8, bytesPerRow: bottom.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(bottom, in: CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height))
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 180 && pixels[$0 + 1] < 140 && pixels[$0 + 2] < 140
        }.count
        XCTAssertGreaterThan(redPixels, 20, "The actual bitmap must include the final round's record badge")
        XCTAssertLessThan(cg.bytesPerRow * cg.height, 50_000_000)
    }
}

private actor DeepSearchCounter { private(set) var count = 0; func hit() { count += 1 } }
