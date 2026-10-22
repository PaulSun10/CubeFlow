import XCTest
@testable import CubeFlow

private actor DelayedTargetSolver {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var started = false
    func solve() async -> String {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(returning: "B' D' L' F' U' R'"); continuation = nil }
}

@MainActor final class SmartCubeCurrentStateGuidanceTests: XCTestCase {
    private func state(_ algorithm: String, size: Int = 3) throws -> String {
        try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: algorithm, puzzleSize: size))
    }
    private func apply(_ moves: [String], to source: String) throws -> String {
        try moves.reduce(source) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }
    }
    func testExactHTMShortPathsForBothCanonicalPuzzleSizes() async throws {
        for size in [2, 3] {
            let target = CubeSurface.solved(size: size)
            for (algorithm, distance) in [("R", 1), ("R2", 1), ("R R", 1), ("R U U'", 1), ("R U", 2), ("R U F", 3)] {
                let source = try state(algorithm, size: size)
                let solution = await SmartCubeTargetPath.shortestWithinThree(from: source, to: target)
                let path = try XCTUnwrap(solution)
                XCTAssertEqual(path.count, distance, "\(size)x\(size) \(algorithm)")
                XCTAssertEqual(try apply(path, to: source), target)
            }
        }
    }
    func testShortPathComparesActualScrambledTargetNotHistoryCheckpoint() async throws {
        let target = try state("R U F L D B"), source = try apply(["L2", "U", "R'"], to: target)
        let solution = await SmartCubeTargetPath.shortestWithinThree(from: source, to: target)
        let path = try XCTUnwrap(solution)
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(try apply(path, to: source), target)
        // Independent exhaustive shallower search confirms the metric bound.
        XCTAssertNotEqual(source, target)
        for a in SmartCubeTargetPath.moves {
            let one = try apply([a], to: source); XCTAssertNotEqual(one, target)
            for b in SmartCubeTargetPath.moves { XCTAssertNotEqual(try apply([b], to: one), target) }
        }
    }
    func testOneMoveDeviationDoesNotWaitForThreeMoveThresholdAndAdoptsShortenedFullRoute() async throws {
        var progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U U' F"))
        let source = try state("U")
        _ = progress.update(with: source, canonicalMove: "U")
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
        let recovery = try XCTUnwrap(progress.guaranteedRecoveryPlan(identity: identity, sourceFacelets: source))
        XCTAssertEqual(recovery.totalCost, 1)
        let decision = await SmartCubeReplacementPlanner.decision(recovery: recovery,
            targetFacelets: progress.targetFacelets, currentGeneration: 0, lastDeviationMove: "U", originalTokens: progress.tokens)
        let replacement = try XCTUnwrap(decision.replacement)
        XCTAssertEqual(replacement.tokens.count, 3)
        XCTAssertEqual(replacement.targetFacelets, progress.targetFacelets)
        var next = SmartCubeScrambleProgress(replacement: replacement), current = source
        for move in replacement.tokens { current = try apply([move], to: current); _ = next.update(with: current, canonicalMove: move) }
        XCTAssertTrue(next.isComplete)
    }
    func testArbitraryTurnsNearCompletionReplanFromEachLatestState() async throws {
        var progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U F"))
        var current = try state("R")
        _ = progress.update(with: current, canonicalMove: "R")
        current = try apply(["U"], to: current); _ = progress.update(with: current, canonicalMove: "U")
        XCTAssertEqual(progress.currentMoveTokenIndex, 2)
        let target = progress.targetFacelets
        for (index, move) in ["B", "B'", "R", "R'", "L2"].enumerated() {
            current = try apply([move], to: current); _ = progress.update(with: current, canonicalMove: move)
            let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: UInt64(index))
            let decision = await SmartCubeReplacementPlanner.restorationDecision(identity: identity,
                sourceFacelets: current, targetFacelets: target, currentGeneration: 0)
            let replacement = try XCTUnwrap(decision.replacement)
            XCTAssertEqual(replacement.sourceFacelets, current)
            XCTAssertEqual(replacement.targetFacelets, target)
            XCTAssertEqual(try apply(replacement.tokens, to: current), target)
        }
    }
    func testTargetReachedUnknownAndBeyondShortBoundAreNotInvented() async throws {
        let target = try state("R U F")
        let complete = await SmartCubeTargetPath.shortestWithinThree(from: target, to: target)
        XCTAssertEqual(complete, [])
        let invalid = await SmartCubeTargetPath.shortestWithinThree(from: "not a cube", to: target)
        XCTAssertNil(invalid)
        let wrongSize = await SmartCubeTargetPath.shortestWithinThree(from: CubeSurface.solved(size: 2), to: target)
        XCTAssertNil(wrongSize)
        let far = try state("R U F L D B")
        let noShort = await SmartCubeTargetPath.shortestWithinThree(from: far, to: CubeSurface.solved(size: 3))
        XCTAssertNil(noShort)
    }

    func testFirstVerifiedTargetSnapshotIsCompleteWithoutASecondObservationOrZeroMoveSearch() throws {
        var progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U F L D B"))
        let target = progress.targetFacelets
        XCTAssertEqual(progress.update(with: target), .completed)
        XCTAssertTrue(progress.isComplete)
        XCTAssertFalse(progress.isDeviated)
        XCTAssertFalse(progress.needsGuidanceSearch)
        XCTAssertTrue(progress.remainingGuidanceMoves.isEmpty)
    }
    func testDelayedOldResponseCannotAdoptAfterLatestStateOrTargetChanges() async throws {
        let epoch = UUID(), target = CubeSurface.solved(size: 3), oldSource = try state("R U F L D B")
        let gate = DelayedTargetSolver()
        let oldTask = Task {
            await SmartCubeReplacementPlanner.restorationDecision(identity: .init(scrambleEpochID: epoch, stateVersion: 1),
                sourceFacelets: oldSource, targetFacelets: target, currentGeneration: 0, solver: { _, _ in await gate.solve() })
        }
        for _ in 0..<200 { if await gate.started { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let started = await gate.started; XCTAssertTrue(started)
        let latestSource = try state("R U"), identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: epoch, stateVersion: 2)
        let fresh = await SmartCubeReplacementPlanner.restorationDecision(identity: identity,
            sourceFacelets: latestSource, targetFacelets: target, currentGeneration: 0)
        let candidate = try XCTUnwrap(fresh.replacement)
        await gate.release()
        let old = await oldTask.value, stale = try XCTUnwrap(old.replacement)
        XCTAssertTrue(candidate.canAdopt(identity: identity, facelets: latestSource, targetFacelets: target,
            trusted: true, deviated: true, currentGeneration: 0))
        XCTAssertFalse(stale.canAdopt(identity: identity, facelets: latestSource, targetFacelets: target,
            trusted: true, deviated: true, currentGeneration: 0))
        XCTAssertFalse(candidate.canAdopt(identity: identity, facelets: latestSource, targetFacelets: target,
            trusted: false, deviated: true, currentGeneration: 0))
        XCTAssertFalse(candidate.canAdopt(identity: identity, facelets: latestSource, targetFacelets: oldSource,
            trusted: true, deviated: true, currentGeneration: 0))
    }
    func testCancellingInFlightSolverRejectsItsLaterResponse() async throws {
        let gate = DelayedTargetSolver(), source = try state("R U F L D B")
        let task = Task {
            await SmartCubeReplacementPlanner.restorationDecision(identity: .init(scrambleEpochID: UUID(), stateVersion: 1),
                sourceFacelets: source, targetFacelets: CubeSurface.solved(size: 3), currentGeneration: 0,
                solver: { _, _ in await gate.solve() })
        }
        for _ in 0..<200 { if await gate.started { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let started = await gate.started; XCTAssertTrue(started)
        task.cancel(); await gate.release()
        let decision = await task.value
        XCTAssertNil(decision.replacement); XCTAssertEqual(decision.reason, .cancelled)
    }
    func testNativeTwoByTwoKeepsStateOnlyGuidanceWithoutGuessingPhysicalMoveFrame() throws {
        var progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U F", puzzleSize: 2))
        let source = try state("L D", size: 2)
        _ = progress.update(with: source, canonicalMove: "L")
        XCTAssertFalse(progress.isDeviated)
        XCTAssertNil(progress.currentMoveTokenIndex)
        XCTAssertFalse(progress.isComplete)
        _ = progress.update(with: progress.targetFacelets)
        XCTAssertTrue(progress.isComplete)
    }
}
