#if os(iOS)
import Foundation

nonisolated struct SmartCubeRecoveryPlanIdentity: Equatable, Hashable, Sendable {
    let scrambleEpochID: UUID
    let stateVersion: UInt64
}

nonisolated struct SmartCubeRecoveryCheckpoint: Equatable, Sendable {
    let facelets: String
    let completedTokenIndices: Set<Int>
    let partialCompletionMoves: [Int: String]
    let totalTokenCount: Int

    var progressScore: Int {
        completedTokenIndices.count * 2 + partialCompletionMoves.count
    }

    var remainingOriginalWorkload: Int {
        max(totalTokenCount - completedTokenIndices.count, 0)
    }
}

nonisolated struct SmartCubeRecoveryRequest: Equatable, Sendable {
    let identity: SmartCubeRecoveryPlanIdentity
    let sourceFacelets: String
    let checkpoints: [SmartCubeRecoveryCheckpoint]
    let maximumCost: Int
}

nonisolated struct SmartCubeRecoveryPlan: Equatable, Sendable {
    let identity: SmartCubeRecoveryPlanIdentity
    let sourceFacelets: String
    let checkpoint: SmartCubeRecoveryCheckpoint
    let correctionMoves: [String]
    let totalCost: Int

    var remainingOriginalWorkload: Int {
        checkpoint.remainingOriginalWorkload
    }
}

nonisolated enum SmartCubeRecoveryPresentationState: Equatable, Sendable {
    case inactive
    case searching(identity: SmartCubeRecoveryPlanIdentity, sourceFacelets: String)
    case recovery(SmartCubeRecoveryPlan)
    case unavailable(identity: SmartCubeRecoveryPlanIdentity, sourceFacelets: String)

    var plan: SmartCubeRecoveryPlan? {
        guard case .recovery(let plan) = self else { return nil }
        return plan
    }

    var identity: SmartCubeRecoveryPlanIdentity? {
        switch self {
        case .inactive:
            return nil
        case .searching(let identity, _), .unavailable(let identity, _):
            return identity
        case .recovery(let plan):
            return plan.identity
        }
    }

    var sourceFacelets: String? {
        switch self {
        case .inactive:
            return nil
        case .searching(_, let sourceFacelets), .unavailable(_, let sourceFacelets):
            return sourceFacelets
        case .recovery(let plan):
            return plan.sourceFacelets
        }
    }

    var showsMismatch: Bool {
        false
    }
}

nonisolated enum SmartCubeRecoveryEngine {
    static let defaultMaximumCost = 3

    private static let moveOrder = [
        "U", "U'", "U2",
        "R", "R'", "R2",
        "F", "F'", "F2",
        "D", "D'", "D2",
        "L", "L'", "L2",
        "B", "B'", "B2"
    ]

    private struct SearchNode: Sendable {
        let facelets: String
        let moves: [String]
    }

    static func guaranteedTrailPlan(
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String,
        deviationMoves: [String],
        checkpoint: SmartCubeRecoveryCheckpoint
    ) -> SmartCubeRecoveryPlan? {
        guard !deviationMoves.isEmpty,
              deviationMoves.allSatisfy(moveOrder.contains),
              applying(deviationMoves, to: checkpoint.facelets) == sourceFacelets
        else { return nil }

        let correctionMoves = simplified(
            deviationMoves.reversed().map(inverse(of:))
        )
        guard !correctionMoves.isEmpty,
              applying(correctionMoves, to: sourceFacelets) == checkpoint.facelets
        else { return nil }

        return SmartCubeRecoveryPlan(
            identity: identity,
            sourceFacelets: sourceFacelets,
            checkpoint: checkpoint,
            correctionMoves: correctionMoves,
            totalCost: correctionMoves.count
        )
    }

    static func simplified<S: Sequence>(_ moves: S) -> [String] where S.Element == String {
        let moves = Array(moves)
        // Only opposite faces commute. A cancelled run can expose an earlier
        // run on the same axis, but a nonempty intervening axis is a barrier.
        let axes: [[Character]] = [["U", "D"], ["R", "L"], ["F", "B"]]
        var runs: [(axis: Int, turns: [Int])] = []
        for move in moves {
            guard let parsed = parsedMove(move) else { return moves }
            guard let axis = axes.firstIndex(where: { $0.contains(parsed.face) }),
                  let face = axes[axis].firstIndex(of: parsed.face) else { return moves }
            if runs.last?.axis != axis {
                runs.append((axis, [0, 0]))
            }
            let index = runs.count - 1
            runs[index].turns[face] = (runs[index].turns[face] + parsed.turns) % 4
            if runs[index].turns.allSatisfy({ $0 == 0 }) {
                runs.removeLast()
            }
        }
        return runs.flatMap { run in
            axes[run.axis].indices.compactMap { index in
                run.turns[index] == 0 ? nil
                    : formattedMove(face: axes[run.axis][index], turns: run.turns[index])
            }
        }
    }

    static func shouldSearchForShortcut(to plan: SmartCubeRecoveryPlan) -> Bool {
        plan.totalCost > defaultMaximumCost
    }

    static func advancedPlan(
        from plan: SmartCubeRecoveryPlan,
        by canonicalMove: String,
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String
    ) -> SmartCubeRecoveryPlan? {
        guard plan.correctionMoves.first == canonicalMove,
              SmartCubeBluetoothManager.facelets(
                plan.sourceFacelets,
                applying: canonicalMove
              ) == sourceFacelets
        else { return nil }

        let remainingMoves = Array(plan.correctionMoves.dropFirst())
        guard !remainingMoves.isEmpty,
              applying(remainingMoves, to: sourceFacelets) == plan.checkpoint.facelets
        else { return nil }
        return SmartCubeRecoveryPlan(
            identity: identity,
            sourceFacelets: sourceFacelets,
            checkpoint: plan.checkpoint,
            correctionMoves: remainingMoves,
            totalCost: remainingMoves.count
        )
    }

    @concurrent
    static func plan(for request: SmartCubeRecoveryRequest) async -> SmartCubeRecoveryPlan? {
        assert(!Thread.isMainThread, "Recovery shortcut search must not occupy the UI thread")
        guard request.maximumCost > 0 else { return nil }

        let targets = preferredCheckpointsByFacelets(request.checkpoints)
        guard targets[request.sourceFacelets] == nil else { return nil }

        var visited: Set<String> = [request.sourceFacelets]
        var frontier = [SearchNode(
            facelets: request.sourceFacelets,
            moves: []
        )]
        var expandedNodeCount = 0

        for _ in 1...request.maximumCost {
            guard !Task.isCancelled else { return nil }

            var nextFrontier: [SearchNode] = []
            var candidates: [SmartCubeRecoveryPlan] = []

            for node in frontier {
                guard !Task.isCancelled else { return nil }
                expandedNodeCount += 1
                if expandedNodeCount.isMultiple(of: 256) {
                    await Task.yield()
                    guard !Task.isCancelled else { return nil }
                }
                for move in moveOrder {
                    guard let nextFacelets = SmartCubeBluetoothManager.facelets(
                            node.facelets,
                            applying: move
                          ),
                          visited.insert(nextFacelets).inserted
                    else { continue }

                    let moves = node.moves + [move]
                    if let checkpoint = targets[nextFacelets] {
                        candidates.append(SmartCubeRecoveryPlan(
                            identity: request.identity,
                            sourceFacelets: request.sourceFacelets,
                            checkpoint: checkpoint,
                            correctionMoves: moves,
                            totalCost: moves.count
                        ))
                    }
                    nextFrontier.append(SearchNode(
                        facelets: nextFacelets,
                        moves: moves
                    ))
                }
            }

            if let best = candidates.sorted(by: planPrecedes).first {
                return best
            }
            frontier = nextFrontier
        }

        return nil
    }

    static func prefers(
        _ candidate: SmartCubeRecoveryPlan,
        over current: SmartCubeRecoveryPlan
    ) -> Bool {
        candidate.identity == current.identity
            && candidate.sourceFacelets == current.sourceFacelets
            && candidate.totalCost < current.totalCost
    }

    static func resultIsCurrent(
        _ plan: SmartCubeRecoveryPlan,
        identity: SmartCubeRecoveryPlanIdentity,
        facelets: String,
        isDeviated: Bool
    ) -> Bool {
        isDeviated
            && plan.identity == identity
            && plan.sourceFacelets == facelets
    }

    private static func preferredCheckpointsByFacelets(
        _ checkpoints: [SmartCubeRecoveryCheckpoint]
    ) -> [String: SmartCubeRecoveryCheckpoint] {
        checkpoints.reduce(into: [:]) { result, checkpoint in
            if let current = result[checkpoint.facelets],
               !checkpointPrecedes(checkpoint, current) {
                return
            }
            result[checkpoint.facelets] = checkpoint
        }
    }

    private static func planPrecedes(
        _ lhs: SmartCubeRecoveryPlan,
        _ rhs: SmartCubeRecoveryPlan
    ) -> Bool {
        if lhs.totalCost != rhs.totalCost { return lhs.totalCost < rhs.totalCost }
        if lhs.checkpoint.progressScore != rhs.checkpoint.progressScore {
            return lhs.checkpoint.progressScore > rhs.checkpoint.progressScore
        }
        let lhsMoves = lhs.correctionMoves.joined(separator: " ")
        let rhsMoves = rhs.correctionMoves.joined(separator: " ")
        if lhsMoves != rhsMoves { return lhsMoves < rhsMoves }
        return lhs.checkpoint.facelets < rhs.checkpoint.facelets
    }

    private static func checkpointPrecedes(
        _ lhs: SmartCubeRecoveryCheckpoint,
        _ rhs: SmartCubeRecoveryCheckpoint
    ) -> Bool {
        if lhs.progressScore != rhs.progressScore {
            return lhs.progressScore > rhs.progressScore
        }
        return lhs.remainingOriginalWorkload < rhs.remainingOriginalWorkload
    }

    private static func inverse(of move: String) -> String {
        if move.hasSuffix("2") { return move }
        if move.hasSuffix("'") { return String(move.dropLast()) }
        return move + "'"
    }

    private static func parsedMove(_ move: String) -> (face: Character, turns: Int)? {
        guard moveOrder.contains(move), let face = move.first else { return nil }
        if move.hasSuffix("2") { return (face, 2) }
        if move.hasSuffix("'") { return (face, 3) }
        return (face, 1)
    }

    private static func formattedMove(face: Character, turns: Int) -> String {
        switch turns {
        case 1: String(face)
        case 2: String(face) + "2"
        case 3: String(face) + "'"
        default: ""
        }
    }

    private static func applying<S: Sequence>(
        _ moves: S,
        to facelets: String
    ) -> String? where S.Element == String {
        moves.reduce(Optional(facelets)) { state, move in
            state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
        }
    }
}
#endif
