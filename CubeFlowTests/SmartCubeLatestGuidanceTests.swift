import XCTest
import Combine
import SwiftUI
@testable import CubeFlow

private actor LatestNativeGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    func hold() async { count += 1; await withCheckedContinuation { waiters.append($0) } }
    func release() { let values = waiters; waiters = []; values.forEach { $0.resume() } }
}

@MainActor final class SmartCubeLatestGuidanceTests: XCTestCase {
    private func apply(_ moves: [String], to state: String) throws -> String {
        try moves.reduce(state) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }
    }
    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<250 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Latest state did not publish independently of the obsolete worker")
    }
    private func request(_ source: String, target: String, version: UInt64 = 1, path: [String]? = nil) -> SmartCubeGuidanceController.Request {
        .init(identity: .init(scrambleEpochID: UUID(), stateVersion: version), sourceFacelets: source,
            targetFacelets: target, generation: 0, knownPath: path)
    }
    func testExactLatestStateDoesNotWaitForNativeTrailingSettle() async throws {
        let gate = LatestNativeGate()
        let owner = SmartCubeGuidanceController(settle: { await gate.hold() })
        defer { owner.cancel(); Task { await gate.release() } }
        let target = try apply(["R", "U", "F", "L"], to: CubeSurface.solved(size: 3))
        let source = try apply(["R"], to: target)
        owner.submit(request(source, target: target))
        try await wait { await gate.count == 1 }
        // No new move, release or timer may be needed for the independent exact lane.
        try await wait { owner.publication != nil }
        let replacement = try XCTUnwrap(owner.publication?.decision.replacement)
        XCTAssertEqual(try apply(replacement.tokens, to: source), target)
        XCTAssertTrue(replacement.isProvenOptimal)
        await gate.release()
    }
    func testRepeatedShortPhysicalTransitionsPublishWhileNativeSettleRemainsPending() async throws {
        let owner = SmartCubeGuidanceController(settle: { try await Task.sleep(nanoseconds: 10_000_000_000) })
        defer { owner.cancel() }
        let target = try apply(["R2", "U", "F", "D2", "L", "B'"], to: CubeSurface.solved(size: 3))
        var source = target
        let epoch = UUID()
        let device = UUID()
        for (index, turn) in Array(repeating: ["R", "U", "U'", "R'"], count: 5).flatMap({ $0 }).enumerated() {
            source = try apply([turn], to: source)
            if source == target { owner.cancel(); continue }
            let value = SmartCubeGuidanceController.Request(identity: .init(scrambleEpochID: epoch, stateVersion: UInt64(index + 1)),
                sourceFacelets: source, targetFacelets: target, generation: 0, knownPath: nil,
                deviceID: device, canonicalSequence: UInt64(index + 1))
            owner.submit(value)
            try await wait { owner.publication?.request == value }
            let replacement = try XCTUnwrap(owner.publication?.decision.replacement)
            XCTAssertEqual(try apply(replacement.tokens, to: source), target)
            XCTAssertTrue(replacement.isProvenOptimal)
        }
    }
    func testLatestExactShortStatePublishesWhileUninterruptibleOldWorkerStillOwnsSlot() async throws {
        let target = try apply(["R", "U", "F", "L", "D", "B"], to: CubeSurface.solved(size: 3))
        let gate = LatestNativeGate()
        let owner = SmartCubeGuidanceController(settle: {}, search: { request in
            await gate.hold()
            return await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets, currentGeneration: 0, knownPath: request.knownPath)
        }, fastSearch: { await SmartCubeReplacementPlanner.shortStateDecision($0) })
        owner.submit(request(try apply(["R", "U", "F", "L", "D", "B"], to: target), target: target))
        try await wait { await gate.count == 1 }
        let current = try apply(["R"], to: target)
        owner.submit(request(current, target: target, version: 2))
        try await wait { owner.publication != nil }
        let publication = try XCTUnwrap(owner.publication)
        let path = try XCTUnwrap(publication.decision.replacement)
        XCTAssertEqual(try apply(path.tokens, to: current), target)
        XCTAssertEqual(path.tokens.count, 1)
        XCTAssertTrue(path.isProvenOptimal)
        let entered = await gate.count
        XCTAssertEqual(entered, 1)
        await gate.release()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(owner.publication?.request.identity, publication.request.identity)
        owner.cancel()
    }
    func testOptimalInverseContinuationIsVerifiedAndKeptWithoutEqualLengthChurn() async throws {
        let target = CubeSurface.solved(size: 3), source = try apply(["R'"], to: CubeSurface.solved(size: 3))
        var value = request(source, target: target, path: ["R"])
        value.keepsEqualPath = true
        let decision = await SmartCubeReplacementPlanner.shortStateDecision(value)
        XCTAssertTrue(try XCTUnwrap(decision.replacement).isProvenOptimal)
        XCTAssertEqual(decision.replacement?.tokens, ["R"])
        let owner = SmartCubeGuidanceController(settle: {})
        owner.submit(value)
        try await wait { !owner.isUpdating }
        XCTAssertNil(owner.publication, "Keep an already displayed equally short verified path")
        owner.cancel()
    }
    func testShortenedKnownPathMustPublishWhenDisplayedContinuationIsLonger() async throws {
        let source = CubeSurface.solved(size: 3)
        let displayed = ["R", "L", "R'", "U"]
        let target = try apply(displayed, to: source)
        let owner = SmartCubeGuidanceController(settle: {})
        var value = request(source, target: target, path: displayed)
        value.continuationOnly = true; value.keepsEqualPath = true
        owner.submit(value)
        try await wait { !owner.isUpdating }
        let replacement = try XCTUnwrap(owner.publication?.decision.replacement,
            "A candidate equal to the internally simplified path still improves the four displayed moves")
        XCTAssertEqual(replacement.tokens.count, 2)
        XCTAssertEqual(try apply(replacement.tokens, to: source), target)
        owner.cancel()
    }
    func testRealLegalOneMoveImprovementIsPublishedEvenForValidContinuation() async throws {
        // A 25-edge identity cycle obtained by splitting one R in six sexy-move
        // cycles. Cutting across that split gives equivalent irreducible paths
        // of 13 and 12 HTM, without relying on a numeric cost-only fixture.
        let loop = ["R2", "R'", "U", "R'", "U'"] + Array(repeating: ["R", "U", "R'", "U'"], count: 5).flatMap { $0 }
        let rotated = Array(loop.dropFirst()) + [loop[0]]
        let source = try apply(["F", "D2", "L", "B'"], to: CubeSurface.solved(size: 3))
        XCTAssertEqual(try apply(rotated, to: source), source)
        let known = Array(rotated.prefix(13))
        let shorter = rotated.dropFirst(13).reversed().map { $0.hasSuffix("2") ? $0 : $0.hasSuffix("'") ? String($0.dropLast()) : $0 + "'" }
        let target = try apply(known, to: source)
        XCTAssertEqual(try apply(shorter, to: source), target)
        XCTAssertEqual(SmartCubeRecoveryEngine.simplified(known).count, 13)
        XCTAssertEqual(shorter.count, 12)
        var states = [source]
        for move in shorter { states.append(try apply([move], to: states.last!)) }
        let expectedStates = states
        let owner = SmartCubeGuidanceController(settle: {}, search: { request in
            .init(replacement: .init(identity: request.identity, sourceFacelets: source, targetFacelets: target,
                tokens: shorter, expectedFacelets: expectedStates, generation: 1), reason: .adopted,
                recoveryCost: nil, candidateCost: 12, inverseMovePenalty: 0, verifiedKnownCost: 13)
        })
        var value = request(source, target: target, path: known)
        value.continuationOnly = true; value.keepsEqualPath = true
        owner.submit(value)
        try await wait { owner.publication != nil }
        let result = try XCTUnwrap(owner.publication?.decision.replacement)
        XCTAssertEqual(try apply(result.tokens, to: source), target)
        XCTAssertEqual(result.tokens.count, known.count - 1)
        XCTAssertFalse(result.isProvenOptimal)
        owner.cancel()
    }
    func testTargetCompletionAndNewScrambleClearOldWorkWithoutWaitingForNativeReturn() async throws {
        let gate = LatestNativeGate(), target = CubeSurface.solved(size: 3)
        let owner = SmartCubeGuidanceController(settle: {}, search: { request in
            await gate.hold()
            return await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets, currentGeneration: 0, knownPath: nil)
        }, fastSearch: { await SmartCubeReplacementPlanner.shortStateDecision($0) })
        owner.submit(request(try apply(["R", "U", "F", "L", "D", "B"], to: target), target: target))
        try await wait { await gate.count == 1 }
        // The authoritative exact-target branch cancels synchronously, before
        // any search worker returns; model completion uses the same snapshot.
        var progress = try XCTUnwrap(SmartCubeScrambleProgress(scramble: "R U F"))
        _ = progress.update(with: progress.targetFacelets)
        XCTAssertTrue(progress.isComplete)
        owner.cancel()
        XCTAssertFalse(owner.isUpdating); XCTAssertNil(owner.publication)
        let nextTarget = try apply(["D", "L"], to: target)
        owner.submit(request(try apply(["B"], to: nextTarget), target: nextTarget))
        try await wait { owner.publication != nil }
        XCTAssertEqual(owner.publication?.request.targetFacelets, nextTarget)
        await gate.release()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(owner.publication?.request.targetFacelets, nextTarget)
        owner.cancel()
    }
    @concurrent private static func interruptedNative(source: String, target: String) async -> (Int, String) {
        var calls = 0
        let result = Min2PhaseBridge.search(from: source, to: target, maximumDepth: 17,
            probeLimit: 1_000_000, minimumProbes: 0, optimal: false, maximumMilliseconds: 1000,
            cancelled: { calls += 1; return calls >= 2 })
        return (calls, result)
    }
    func testNativeCancellationChecksPhaseOneAndLegacyCallsRemainValid() async throws {
        let source = CubeSurface.solved(size: 3)
        let target = try apply("R2 U F' D2 L B2 U' R F2 D L2 B' U2 R' F D' B U L' R2".split(separator: " ").map(String.init), to: source)
        let (checks, answer) = await Self.interruptedNative(source: source, target: target)
        XCTAssertGreaterThanOrEqual(checks, 2)
        if !answer.isEmpty { XCTAssertEqual(try apply(answer.split(separator: " ").map(String.init), to: source), target) }
    }
    func testSameStateAndEpochCannotAuthorizeAnotherActiveDevicesCandidate() async throws {
        let device = UUID(), other = UUID(), target = CubeSurface.solved(size: 3)
        let source = try apply(["R"], to: target)
        var value = request(source, target: target)
        value.deviceID = device
        let decision = await SmartCubeReplacementPlanner.shortStateDecision(value)
        let publication = SmartCubeGuidanceController.Publication(request: value, decision: decision)
        XCTAssertNotNil(publication.progress(identity: value.identity, facelets: source, target: target,
            generation: 0, trusted: true, eligible: true, deviceID: device))
        XCTAssertNil(publication.progress(identity: value.identity, facelets: source, target: target,
            generation: 0, trusted: true, eligible: true, deviceID: other))
        XCTAssertNil(publication.progress(identity: value.identity, facelets: source, target: target,
            generation: 0, trusted: true, eligible: true, deviceID: nil))
    }
}
