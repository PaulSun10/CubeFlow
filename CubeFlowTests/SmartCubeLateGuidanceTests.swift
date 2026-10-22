import XCTest
@testable import CubeFlow

@MainActor final class SmartCubeLateGuidanceTests: XCTestCase {
    private let scramble = "R2 U F' D2 L B2 U' R F2 D L2 B' U2 R' F D' B U L' R2"
    @concurrent private static func native(_ source: String, _ target: String, depth: Int, probes: Int) async -> String {
        Min2PhaseBridge.search(from: source, to: target, maximumDepth: depth, probeLimit: probes, minimumProbes: 0, optimal: false)
    }
    private func apply(_ moves: [String], to state: String) throws -> String {
        try moves.reduce(state) { try XCTUnwrap(SmartCubeBluetoothManager.facelets($0, applying: $1)) }
    }
    private func inverse(_ moves: [String]) -> [String] {
        moves.reversed().map { $0.hasSuffix("2") ? $0 : $0.hasSuffix("'") ? String($0.dropLast()) : $0 + "'" }
    }
    func testBaselineProductionStagesEarlyAndFiveRemaining() async throws {
        let tokens = scramble.split(separator: " ").map(String.init), solved = CubeSurface.solved(size: 3)
        let target = try apply(tokens, to: solved)
        for (name, prefix, tail) in [("early", 2, "L"), ("late-one", 15, "R"), ("late-three", 15, "R U F"), ("late-six", 15, "R U F L D B")] {
            let deviation = tail.split(separator: " ").map(String.init)
            let current = try apply(Array(tokens.prefix(prefix)) + deviation, to: solved)
            let known = inverse(deviation) + tokens.dropFirst(prefix)
            XCTAssertEqual(try apply(known, to: current), target)
            let begin = ProcessInfo.processInfo.systemUptime
            let initial = await Self.native(current, target, depth: min(21, known.count), probes: 1_000_000)
            let middle = ProcessInfo.processInfo.systemUptime
            let candidate = initial.split(whereSeparator: \.isWhitespace).map(String.init)
            let valid = !candidate.isEmpty && candidate.allSatisfy(SmartCubeTargetPath.moves.contains)
            var improved: [String] = []
            if valid {
                XCTAssertEqual(try apply(candidate, to: current), target)
                let result = await Self.native(current, target, depth: candidate.count - 1, probes: 10_000)
                improved = result.split(whereSeparator: \.isWhitespace).map(String.init)
                if !improved.isEmpty && improved.allSatisfy(SmartCubeTargetPath.moves.contains) {
                    XCTAssertEqual(try apply(improved, to: current), target)
                }
            }
            let end = ProcessInfo.processInfo.systemUptime
            print("[LateBaseline] name=\(name) remaining=\(tokens.count-prefix) known=\(known.count) initial=\(candidate.count) valid=\(valid) improved=\(improved) primaryMS=\((middle-begin)*1000) improvementMS=\((end-middle)*1000) totalMS=\((end-begin)*1000)")
        }
    }
}

extension SmartCubeLateGuidanceTests {
    @concurrent private static func legacyPolicy(_ source: String, _ target: String, known: [String]) async -> String {
        let initial = await native(source, target, depth: min(21, known.count), probes: 1_000_000)
        let candidate = initial.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !candidate.isEmpty, candidate.allSatisfy(SmartCubeTargetPath.moves.contains) else { return known.joined(separator: " ") }
        let tighter = await native(source, target, depth: candidate.count - 1, probes: 10_000)
        let improved = tighter.split(whereSeparator: \.isWhitespace).map(String.init)
        let best = !improved.isEmpty && improved.count < candidate.count && improved.allSatisfy(SmartCubeTargetPath.moves.contains) ? improved : candidate
        return (known.count <= best.count ? known : best).joined(separator: " ")
    }
    func testWarmPairedPlannerReferenceAndCurrentPolicyUseSameExactTargetAndVerifier() async throws {
        let tokens = scramble.split(separator: " ").map(String.init), solved = CubeSurface.solved(size: 3)
        let target = try apply(tokens, to: solved)
        _ = await Self.native(target, target, depth: 0, probes: 1)
        for (name, prefix, tail) in [("early", 2, "L"), ("late-one", 15, "R"), ("late-three", 15, "R U F"), ("late-six", 15, "R U F L D B")] {
            let deviation = tail.split(separator: " ").map(String.init)
            let source = try apply(Array(tokens.prefix(prefix)) + deviation, to: solved)
            let known = inverse(deviation) + tokens.dropFirst(prefix)
            var legacy: [Double] = [], current: [Double] = []
            for _ in 0..<5 {
                let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
                let start = ProcessInfo.processInfo.systemUptime
                // Same production exact-short search and replay verifier; only
                // the injected native policy is the pre-deadline two-pass policy.
                let before = await SmartCubeReplacementPlanner.restorationDecision(identity: identity,
                    sourceFacelets: source, targetFacelets: target, currentGeneration: 0,
                    solver: { source, target in await Self.legacyPolicy(source, target, known: known) })
                let middle = ProcessInfo.processInfo.systemUptime
                let after = await SmartCubeReplacementPlanner.currentStateDecision(identity: identity,
                    sourceFacelets: source, targetFacelets: target, currentGeneration: 0, knownPath: known)
                let end = ProcessInfo.processInfo.systemUptime
                for decision in [before, after] {
                    let path = try XCTUnwrap(decision.replacement).tokens
                    XCTAssertEqual(try apply(path, to: source), target)
                    XCTAssertLessThanOrEqual(path.count, known.count)
                }
                legacy.append((middle - start) * 1000); current.append((end - middle) * 1000)
            }
            print("[PairedGuidance] name=\(name) legacyReferenceMS=\(legacy) currentMS=\(current)")
        }
    }
    func testProductionBoundedPolicyDistributionsAgainstSameLegacySearch() async throws {
        let tokens = scramble.split(separator: " ").map(String.init), solved = CubeSurface.solved(size: 3)
        let target = try apply(tokens, to: solved)
        for (name, prefix, tail) in [("early", 2, "L"), ("late-one", 15, "R"), ("late-three", 15, "R U F"), ("late-six", 15, "R U F L D B")] {
            let deviation = tail.split(separator: " ").map(String.init)
            let current = try apply(Array(tokens.prefix(prefix)) + deviation, to: solved)
            let known = inverse(deviation) + tokens.dropFirst(prefix)
            var measurements: [Double] = []
            for _ in 0..<5 {
                let begin = ProcessInfo.processInfo.systemUptime
                let decision = await SmartCubeReplacementPlanner.currentStateDecision(identity: .init(scrambleEpochID: UUID(), stateVersion: 1),
                    sourceFacelets: current, targetFacelets: target, currentGeneration: 0, knownPath: known)
                let answer = try XCTUnwrap(decision.replacement)
                XCTAssertEqual(try apply(answer.tokens, to: current), target)
                XCTAssertLessThanOrEqual(answer.tokens.count, known.count)
                measurements.append((ProcessInfo.processInfo.systemUptime - begin) * 1000)
            }
            print("[LateAfter] name=\(name) samplesMS=\(measurements) sortedMS=\(measurements.sorted())")
        }
    }
}
