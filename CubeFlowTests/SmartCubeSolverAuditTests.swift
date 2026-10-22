import XCTest
@testable import CubeFlow

@MainActor final class SmartCubeSolverAuditTests: XCTestCase {
    func testHistoricalCheckpointAndCurrentTargetSearchOnSameReducibleHistory() async throws {
        let original = "R U F' D2 L B U' R2 F D' B2 L' U R' F2 D L2 B' U2 F".split(separator: " ").map(String.init)
        let checkpointState = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: original.dropLast(8).joined(separator: " ")))
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: original.joined(separator: " ")))
        let tail = ["R", "U", "L"] + Array(repeating: ["R", "U", "R'", "U'"], count: 6).flatMap { $0 }
        let source = try tail.reduce(checkpointState) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 27)
        let checkpoint = SmartCubeRecoveryCheckpoint(facelets: checkpointState,
            completedTokenIndices: Set(0..<(original.count - 8)), partialCompletionMoves: [:], totalTokenCount: original.count)
        let known = try XCTUnwrap(SmartCubeRecoveryEngine.guaranteedTrailPlan(identity: identity,
            sourceFacelets: source, deviationMoves: tail, checkpoint: checkpoint)?.executableMoves(originalTokens: original))
        let historicalResult = await SmartCubeRecoveryEngine.plan(for: .init(identity: identity,
            sourceFacelets: source, checkpoints: [checkpoint], maximumCost: 3))
        let historical = try XCTUnwrap(historicalResult)
        let historicalPath = try XCTUnwrap(historical.executableMoves(originalTokens: original))
        XCTAssertEqual(historicalPath.count, 11)
        let decision = await SmartCubeReplacementPlanner.currentStateDecision(identity: identity,
            sourceFacelets: source, targetFacelets: target, currentGeneration: 0, knownPath: known)
        let selected = try XCTUnwrap(decision.replacement)
        print("[HistoricalShortcut] known=\(known.count) historical=\(historicalPath.count) current=\(selected.tokens.count)")
        XCTAssertLessThanOrEqual(selected.tokens.count, historicalPath.count,
            "Compare the verified historical checkpoint route against the current target route on this fixture")
    }
    @concurrent private static func comparePenultimate(_ source: String, _ target: String, depth: Int, optimal: Bool) async -> String {
        Min2PhaseBridge.search(from: source, to: target, maximumDepth: depth, probeLimit: 1_000_000,
            minimumProbes: 0, optimal: optimal, maximumMilliseconds: 100, cancelled: { Task.isCancelled })
    }
    func testPenultimateNativePoliciesOnSameStatesAndKnownUpperBound() async throws {
        let original = "R U2 F B R B2 R U2 L B2 R2 D F2 L2 U' B2 U2 L2 D F2".split(separator: " ").map(String.init)
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: original.joined(separator: " ")))
        var source = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: original.dropLast().joined(separator: " ")))
        var inverse: [String] = []
        for (index, move) in Array(repeating: ["R", "U", "R'", "U'"], count: 5).flatMap({ $0 }).enumerated() {
            source = try XCTUnwrap(SmartCubeBluetoothManager.facelets(source, applying: move))
            inverse.insert(move.hasSuffix("'") ? String(move.dropLast()) : move + "'", at: 0)
            guard [5, 7, 10, 12, 15, 17, 19, 20].contains(index + 1) else { continue }
            let known = SmartCubeRecoveryEngine.simplified(inverse + [original.last!])
            for (mode, depth, optimal) in [("current-bound", min(21, known.count), false), ("historical-depth", 21, false), ("bounded-optimal8", min(8, known.count), true)] {
                let began = ProcessInfo.processInfo.systemUptime
                let raw = await Self.comparePenultimate(source, target, depth: depth, optimal: optimal)
                let path = raw.split(whereSeparator: \.isWhitespace).map(String.init)
                let end = path.reduce(Optional(source)) { state, turn in state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: turn) } }
                print("[PenultimateNative] deviations=\(index+1) mode=\(mode) known=\(known.count) candidate=\(path.count) valid=\(end == target) ms=\((ProcessInfo.processInfo.systemUptime-began)*1000)")
                if !path.isEmpty { XCTAssertEqual(end, target) }
            }
        }
    }
    @concurrent private static func boundedComparison(_ source: String, _ target: String, optimal: Bool) async -> String {
        Min2PhaseBridge.search(from: source, to: target, maximumDepth: 21, probeLimit: 1_000_000,
            minimumProbes: 0, optimal: optimal, maximumMilliseconds: 100, cancelled: { Task.isCancelled })
    }
    func testExistingOptimalModeAgainstSevenMoveStateToOriginalTarget() async throws {
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R U F L D B R2 U2 F2"))
        for algorithm in ["R U F L D B R2", "F R U R' U' F' L", "D B2 R U' L F2 R'"] {
            let source = try algorithm.split(separator: " ").reduce(target) {
                try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: String($1)))
            }
            for optimal in [false, true] {
                let start = ProcessInfo.processInfo.systemUptime
                let raw = await Self.boundedComparison(source, target, optimal: optimal)
                let moves = raw.split(whereSeparator: \.isWhitespace).map(String.init)
                let end = moves.reduce(Optional(source)) { state, move in state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) } }
                print("[StationarySolverAudit] input=\(algorithm) optimal=\(optimal) count=\(moves.count) ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) valid=\(end == target)")
                if optimal {
                    XCTAssertEqual(end, target)
                    XCTAssertLessThanOrEqual(moves.count, 7)
                }
            }
        }
    }
    @concurrent private static func search(_ source: String, _ target: String, depth: Int, optimal: Bool) async -> String {
        Min2PhaseBridge.search(from: source, to: target, maximumDepth: depth,
            probeLimit: 10_000, minimumProbes: 0, optimal: optimal)
    }
    func testRepresentativeStateToStateSearchModesAndBenchmarks() async throws {
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R U F L D B R2 U2 F2"))
        let samples = ["R", "R U", "R U F", "R U F L D", "R U F L D B R2 U F' D L2 B' R U' F2 D' B L' U"]
        for algorithm in samples {
            let source = try algorithm.split(separator: " ").map(String.init).reduce(target) {
                try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1))
            }
            for mode in ["first", "bounded"] {
                let depth = mode == "first" ? 21 : min(21, algorithm.split(separator: " ").count)
                let start = ProcessInfo.processInfo.systemUptime
                let solution = await Self.search(source, target, depth: depth, optimal: false)
                let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
                let moves = solution.split(whereSeparator: \.isWhitespace).map(String.init)
                let end = moves.reduce(Optional(source)) { state, move in
                    state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
                }
                print("[SolverAudit] sourceMoves=\(algorithm.split(separator: " ").count) mode=\(mode) ms=\(ms) resultMoves=\(moves.count) valid=\(end == target)")
                XCTAssertEqual(end, target)
                XCTAssertLessThanOrEqual(moves.count, depth)
            }
            if algorithm.split(separator: " ").count <= 5 {
                let start = ProcessInfo.processInfo.systemUptime
                let solution = await Self.search(source, target, depth: 5, optimal: true)
                let moves = solution.split(whereSeparator: \.isWhitespace).map(String.init)
                print("[SolverAudit] sourceMoves=\(algorithm.split(separator: " ").count) mode=optimal5 ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) resultMoves=\(moves.count)")
                let end = moves.reduce(Optional(source)) { state, move in state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) } }
                XCTAssertEqual(end, target)
            }
        }
    }

    func testProductionHybridBenchmarksAndVerifiedKnownUpperBounds() async throws {
        let target = try XCTUnwrap(SmartCubeBluetoothManager.facelets(afterApplying: "R U F L D B R2 U2 F2"))
        for tail in ["R", "R U", "R U F", "R U F L D", "R U F L D B R2 U F' D L2 B' R U' F2 D' B L' U"] {
            let moves = tail.split(separator: " ").map(String.init)
            let source = try moves.reduce(target) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }
            let inverse = moves.reversed().map { $0.hasSuffix("2") ? $0 : $0.hasSuffix("'") ? String($0.dropLast()) : $0 + "'" }
            let start = ProcessInfo.processInfo.systemUptime
            let decision = await SmartCubeReplacementPlanner.currentStateDecision(identity: .init(scrambleEpochID: UUID(), stateVersion: 1),
                sourceFacelets: source, targetFacelets: target, currentGeneration: 0, knownPath: inverse)
            let replacement = try XCTUnwrap(decision.replacement)
            print("[HybridAudit] inputMoves=\(moves.count) resultMoves=\(replacement.tokens.count) ms=\((ProcessInfo.processInfo.systemUptime-start)*1000)")
            XCTAssertLessThanOrEqual(replacement.tokens.count, moves.count)
            let end = replacement.tokens.reduce(Optional(source)) { state, move in state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) } }
            XCTAssertEqual(end, target)
        }
    }
}
