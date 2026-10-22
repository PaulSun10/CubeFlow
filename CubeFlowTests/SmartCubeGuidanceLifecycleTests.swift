import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

private actor GuidanceGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var entered = 0
    func pause() async {
        entered += 1
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { let current = waiters; waiters = []; current.forEach { $0.resume() } }
}

/// Uses the production progress matcher, scheduler, solver, adoption gate and
/// renderer. Only the verified physical input is supplied by the fixture.
@MainActor private final class GuidanceHarness: ObservableObject {
    @Published var progress: SmartCubeScrambleProgress
    let controller: SmartCubeGuidanceController
    var facelets: String
    private var epoch = SmartCubeScrambleEpoch()
    var identity: SmartCubeRecoveryPlanIdentity { epoch.currentRecoveryIdentity }
    private let feed = SmartCubeCanonicalFeed()
    private var latestMoveID: UUID?
    private(set) var publications: [SmartCubeGuidanceController.Publication] = []
    private var observation: AnyCancellable?
    private var eventObservation: AnyCancellable?

    init(controller suppliedController: SmartCubeGuidanceController? = nil) throws {
        let controller = suppliedController ?? SmartCubeGuidanceController()
        self.controller = controller
        progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U F L D B R2 U2 F2"))
        facelets = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R U F L D B R2 U2"))
        _ = progress.update(with: facelets)
        // Initial replay below represents the verified original scramble, not
        // a skipped physical prefix or a separate target redefinition.
        progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U F L D B R2 U2 F2"))
        var current = CubeSurface.solved(size: 3)
        for move in ["R", "U", "F", "L", "D", "B", "R2", "U2"] {
            current = try XCTUnwrap(SmartCubeBluetoothManager.facelets(current, applying: move))
            _ = progress.update(with: current, canonicalMove: move)
        }
        epoch.establish(at: .distantPast, latestMoveID: nil)
        eventObservation = feed.events.sink { [weak self] event in
            guard let self, case .move(let update) = epoch.consumeEvent(event),
                  epoch.observePhysicalMove(update.move) else { return }
            _ = progress.update(with: update.facelets, canonicalMove: update.move.move)
            schedule()
        }
        observation = controller.$publication.compactMap { $0 }.sink { [weak self] publication in
            guard let self,
                  let updated = publication.progress(identity: identity, facelets: facelets,
                    target: progress.targetFacelets, generation: progress.replanGeneration, trusted: true,
                    eligible: progress.isDeviated || progress.needsGuidanceSearch) else { return }
            publications.append(publication)
            epoch.rebaseGuidance(latestMoveID: latestMoveID, canonicalSequence: feed.sequence)
            progress = updated
        }
    }

    func turn(_ move: String, receivedAt: Date = .now) throws {
        facelets = try XCTUnwrap(SmartCubeBluetoothManager.facelets(facelets, applying: move))
        let event = SmartCubeMoveEvent(move: move, serial: Int(feed.sequence), face: nil, direction: nil,
            localTimestamp: receivedAt, cubeTimestampMilliseconds: nil)
        latestMoveID = event.id
        feed.send(move: event, facelets: facelets)
    }

    func beginNewEpoch() { epoch.establish(at: .distantPast, latestMoveID: latestMoveID, canonicalSequence: feed.sequence) }

    func schedule() {
        let identity = epoch.advanceRecoveryStateVersion()
        guard !progress.isComplete, progress.needsGuidanceSearch || progress.isDeviated else {
            controller.cancel(); return
        }
        let recovery = progress.guaranteedRecoveryPlan(identity: identity, sourceFacelets: facelets)
        controller.submit(.init(identity: identity, sourceFacelets: facelets,
            targetFacelets: progress.targetFacelets, generation: progress.replanGeneration,
            knownPath: recovery?.executableMoves(originalTokens: progress.tokens)
                ?? (progress.isDeviated ? nil : progress.remainingGuidanceMoves)))
    }
}

@MainActor private struct MountedGuidance: View {
    @ObservedObject var harness: GuidanceHarness
    @ObservedObject var controller: SmartCubeGuidanceController
    let rendered: (Int) -> Void
    var body: some View {
        let progress = harness.progress
        SmartCubeScrambleProgressView(scramble: "R U F L D B R2 U2 F2", tokens: progress.tokens,
            completedTokenIndices: progress.completedTokenIndices,
            highlightedTokenIndex: progress.currentMoveTokenIndex, recoveryPlan: nil,
            recoveryDisplay: .separate, highlightAnimation: .instant, behavior: .collapse,
            transition: .instant, fontDesign: .default, fontStyle: .system(weight: .regular, isItalic: false), fontSize: 20,
            foregroundStyle: AnyShapeStyle(Color.primary), highlightBackgroundStyle: AnyShapeStyle(Color.blue),
            highlightForegroundStyle: AnyShapeStyle(Color.white), showsLiveProgress: true,
            isUpdatingGuidance: controller.isUpdating)
            .padding(20)
            .onChange(of: progress.replanGeneration) { rendered($0) }
    }
}

@MainActor final class SmartCubeGuidanceLifecycleTests: XCTestCase {
    private func wait(_ predicate: @escaping @MainActor () async -> Bool,
                      file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<500 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Latest stopped state did not finish without another move", file: file, line: line)
    }

    private func assertCurrent(_ harness: GuidanceHarness, target: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let publication = try XCTUnwrap(harness.publications.last, file: file, line: line)
        let replacement = try XCTUnwrap(publication.decision.replacement, file: file, line: line)
        XCTAssertEqual(replacement.sourceFacelets, harness.facelets, file: file, line: line)
        XCTAssertEqual(replacement.targetFacelets, target, file: file, line: line)
        let end = replacement.tokens.reduce(Optional(harness.facelets)) { state, move in
            state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
        }
        XCTAssertEqual(end, target, file: file, line: line)
        XCTAssertFalse(harness.controller.isUpdating, file: file, line: line)
        XCTAssertFalse(harness.progress.needsGuidanceSearch, file: file, line: line)
        XCTAssertNil(publication.progress(identity: publication.request.identity, facelets: harness.facelets,
            target: target, generation: publication.request.generation, trusted: false, eligible: true))
    }

    func testOneMoveRemainingWrongTurnAndRepeatedWrongTurnsPublishAfterCompleteStop() async throws {
        for sequence in [["R"], ["R", "R"], ["R", "R'"], ["R", "U", "U'", "R'"]] {
            let harness = try GuidanceHarness(), target = harness.progress.targetFacelets
            XCTAssertEqual(harness.progress.remainingGuidanceMoves, ["F2"])
            for move in sequence { try harness.turn(move) }
            XCTAssertTrue(harness.progress.needsGuidanceSearch)
            try await wait { !harness.publications.isEmpty }
            try assertCurrent(harness, target: target)
            XCTAssertEqual(harness.publications.count, 1, "Rapid input must coalesce")
            XCTAssertLessThanOrEqual(harness.progress.tokens.count, sequence.count + 1)
        }
    }

    func testNineteenRapidArbitraryTurnsPublishNewestStateWithoutTwentiethTurn() async throws {
        let harness = try GuidanceHarness(), target = harness.progress.targetFacelets
        let moves = "R U F L D B R2 U F' D L2 B' R U' F2 D' B L' U".split(separator: " ").map(String.init)
        XCTAssertEqual(moves.count, 19)
        for move in moves { try harness.turn(move) }
        let stoppedState = harness.facelets
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        try await wait { !harness.publications.isEmpty }
        print("[GuidanceBenchmark] rapidTurns=19 publications=\(harness.publications.count) finalIdleToPublicationMs=\((ProcessInfo.processInfo.systemUptime-stoppedAt)*1000)")
        try assertCurrent(harness, target: target)
        XCTAssertEqual(harness.facelets, stoppedState)
        XCTAssertEqual(harness.publications.count, 1)
    }

    func testHistoricalCheckpointReturnInvalidatesDisplayedRouteQuality() async throws {
        let harness = try GuidanceHarness(), target = harness.progress.targetFacelets
        try harness.turn("U2") // Returns to an earlier original checkpoint.
        XCTAssertFalse(harness.progress.isDeviated)
        XCTAssertTrue(harness.progress.needsGuidanceSearch)
        try await wait { !harness.publications.isEmpty }
        try assertCurrent(harness, target: target)
    }

    func testEqualVerifiedFallbackPublishesRatherThanWaitingForCostThreshold() async throws {
        let harness = try GuidanceHarness(), target = harness.progress.targetFacelets
        try harness.turn("R")
        try await wait { !harness.publications.isEmpty }
        try assertCurrent(harness, target: target)
        XCTAssertEqual(harness.progress.tokens.count, 2)
        XCTAssertEqual(harness.publications.last?.decision.reason, .adopted)
    }

    func testInFlightOldWorkerDrainsLatestSettledStateWithoutAnotherNotification() async throws {
        let gate = GuidanceGate()
        let controller = SmartCubeGuidanceController(search: { request in
            await gate.pause()
            return await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets,
                currentGeneration: request.generation, knownPath: request.knownPath)
        })
        let harness = try GuidanceHarness(controller: controller), target = harness.progress.targetFacelets
        try harness.turn("R")
        try await wait { await gate.entered == 1 }
        for move in ["U", "F", "L", "B", "D", "R2"] { try harness.turn(move) }
        try await wait { controller.phase == .settling }
        try await Task.sleep(nanoseconds: 160_000_000)
        let beforeRelease = await gate.entered
        XCTAssertEqual(beforeRelease, 1, "Only one worker may be in flight")
        await gate.release()
        try await wait { await gate.entered == 2 }
        XCTAssertTrue(harness.publications.isEmpty)
        await gate.release()
        try await wait { harness.publications.count == 1 }
        try assertCurrent(harness, target: target)
    }

    func testCancellationRemountAndLateCompletionCannotRestoreOldEpoch() async throws {
        let gate = GuidanceGate()
        let controller = SmartCubeGuidanceController(search: { request in
            await gate.pause()
            return await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets,
                currentGeneration: request.generation, knownPath: request.knownPath)
        })
        let harness = try GuidanceHarness(controller: controller), target = harness.progress.targetFacelets
        try harness.turn("R")
        try await wait { await gate.entered == 1 }
        controller.cancel()
        harness.beginNewEpoch()
        harness.schedule() // Remount with the same final verified state, no move.
        await gate.release()
        try await wait { await gate.entered == 2 }
        XCTAssertTrue(harness.publications.isEmpty)
        await gate.release()
        try await wait { harness.publications.count == 1 }
        try assertCurrent(harness, target: target)
    }

    func testLastTurnAtSettleBoundaryCannotBeLost() async throws {
        for yieldBeforeLastMove in [false, true] {
            let settle = GuidanceGate()
            let controller = SmartCubeGuidanceController(settle: { await settle.pause() })
            let harness = try GuidanceHarness(controller: controller), target = harness.progress.targetFacelets
            try harness.turn("R")
            try await wait { await settle.entered == 1 }
            await settle.release()
            if yieldBeforeLastMove { await Task.yield() }
            try harness.turn("U")
            try await wait { await settle.entered == 2 }
            await settle.release()
            try await wait { harness.publications.last?.request.sourceFacelets == harness.facelets }
            try assertCurrent(harness, target: target)
        }
    }

    func testNewTargetDuringInFlightSearchRejectsOldTargetWithoutAnotherMove() async throws {
        let gate = GuidanceGate()
        let controller = SmartCubeGuidanceController(search: { request in
            await gate.pause()
            return await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets,
                currentGeneration: request.generation, knownPath: request.knownPath)
        })
        let harness = try GuidanceHarness(controller: controller)
        try harness.turn("R")
        try await wait { await gate.entered == 1 }
        controller.cancel()
        var newProgress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "B L D"))
        _ = newProgress.update(with: harness.facelets)
        harness.progress = newProgress
        harness.beginNewEpoch()
        harness.schedule()
        await gate.release()
        try await wait { await gate.entered == 2 }
        XCTAssertTrue(harness.publications.isEmpty)
        await gate.release()
        try await wait { harness.publications.count == 1 }
        try assertCurrent(harness, target: newProgress.targetFacelets)
    }

    func testMountedProductionRendererUpdatesAfterStopWithoutAnotherPhysicalMove() async throws {
        let harness = try GuidanceHarness()
        let rendered = expectation(description: "SwiftUI renders rebased tokens")
        let host = UIHostingController(rootView: MountedGuidance(harness: harness,
            controller: harness.controller) { generation in if generation > 0 { rendered.fulfill() } })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 420)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; harness.controller.cancel() }
        try harness.turn("R")
        await fulfillment(of: [rendered], timeout: 5)
        try assertCurrent(harness, target: harness.progress.targetFacelets)
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Current-state guidance after complete stop"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCanonicalTurnReceivedBeforePublicationButDeliveredAfterItIsNotDropped() async throws {
        let harness = try GuidanceHarness(), target = harness.progress.targetFacelets
        try harness.turn("R")
        let receivedWhilePlanning = Date.now
        try await wait { harness.publications.count == 1 }
        // Host receipt timestamps survive parser/coalescing latency. Sequence
        // advances only when this pending move is committed to canonical feed.
        try harness.turn("U", receivedAt: receivedWhilePlanning)
        let stopped = harness.facelets
        try await wait { harness.publications.count == 2 }
        XCTAssertEqual(harness.publications.last?.request.sourceFacelets, stopped)
        try assertCurrent(harness, target: target)
    }
}
