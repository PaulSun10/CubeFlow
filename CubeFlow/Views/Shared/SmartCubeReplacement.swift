#if os(iOS)
import Foundation

private actor SmartCubeReplacementSolver {
    static let shared = SmartCubeReplacementSolver()

    func moves(from sourceFacelets: String, to targetFacelets: String) -> String {
        guard !Task.isCancelled else { return "" }
        return Min2PhaseBridge.moves(fromFacelets: sourceFacelets, toFacelets: targetFacelets)
    }
}

nonisolated struct SmartCubeReplacement: Sendable {
    let identity: SmartCubeRecoveryPlanIdentity
    let sourceFacelets: String
    let targetFacelets: String
    let tokens: [String]
    let expectedFacelets: [String]
    let generation: Int

    func canAdopt(
        identity: SmartCubeRecoveryPlanIdentity,
        facelets: String,
        targetFacelets: String,
        trusted: Bool,
        deviated: Bool,
        currentGeneration: Int
    ) -> Bool {
        self.identity == identity
            && sourceFacelets == facelets
            && self.targetFacelets == targetFacelets
            && trusted
            && deviated
            && generation == currentGeneration + 1
    }
}

nonisolated enum SmartCubeReplacementDecisionReason: String, Sendable {
    case correctionBelowThreshold = "correction-below-threshold"
    case candidateUnavailable = "candidate-unavailable"
    case candidateOutsideBounds = "candidate-outside-bounds"
    case candidateTargetMismatch = "candidate-target-mismatch"
    case candidateNotShorter = "candidate-not-shorter"
    case inverseMoveHysteresis = "inverse-move-hysteresis"
    case cancelled = "cancelled"
    case adopted = "replan-adopted"
}

nonisolated struct SmartCubeReplacementDecision: Sendable {
    let replacement: SmartCubeReplacement?
    let reason: SmartCubeReplacementDecisionReason
    let recoveryCost: Int?
    let candidateCost: Int?
    let inverseMovePenalty: Int
}

nonisolated enum SmartCubeReplacementPlanner {
    static let minimumCorrectionCost = 3
    static let maximumCandidateCost = 21
    static let immediateInversePenalty = 1

    static func initialPresentation(
        recovery: SmartCubeRecoveryPlan?,
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String
    ) -> SmartCubeRecoveryPresentationState {
        guard let recovery else {
            return .searching(
                identity: identity,
                sourceFacelets: sourceFacelets,
                fallbackPlan: nil
            )
        }
        guard recovery.totalCost >= minimumCorrectionCost else {
            return .recovery(recovery)
        }
        return .searching(
            identity: identity,
            sourceFacelets: sourceFacelets,
            fallbackPlan: recovery
        )
    }

    static func fallbackPresentation(
        recovery: SmartCubeRecoveryPlan? = nil,
        from pending: SmartCubeRecoveryPresentationState
    ) -> SmartCubeRecoveryPresentationState {
        if let recovery {
            return .recovery(recovery)
        }
        if let fallbackPlan = pending.fallbackPlan {
            return .recovery(fallbackPlan)
        }
        guard let identity = pending.identity,
              let sourceFacelets = pending.sourceFacelets else {
            return .inactive
        }
        return .unavailable(identity: identity, sourceFacelets: sourceFacelets)
    }

    static func costDecision(
        correction: Int,
        remaining: Int,
        candidateCost: Int,
        lastDeviationMove: String?,
        firstCandidateMove: String?
    ) -> SmartCubeReplacementDecisionReason {
        guard correction >= minimumCorrectionCost else { return .correctionBelowThreshold }
        guard candidateCost > 0, candidateCost <= maximumCandidateCost else { return .candidateOutsideBounds }
        let recoveryCost = correction + remaining
        let isImmediateInverse = lastDeviationMove.map { inverse(of: $0) == firstCandidateMove } ?? false
        guard candidateCost < recoveryCost else { return .candidateNotShorter }
        if isImmediateInverse, candidateCost + immediateInversePenalty >= recoveryCost {
            return .inverseMoveHysteresis
        }
        return .adopted
    }

    @concurrent
    static func decision(
        recovery: SmartCubeRecoveryPlan,
        targetFacelets: String,
        currentGeneration: Int,
        lastDeviationMove: String?
    ) async -> SmartCubeReplacementDecision {
        guard recovery.totalCost >= minimumCorrectionCost else {
            return rejected(
                .correctionBelowThreshold,
                recoveryCost: recovery.totalCost + recovery.remainingOriginalWorkload
            )
        }
        return await verifiedDecision(
            identity: recovery.identity,
            sourceFacelets: recovery.sourceFacelets,
            targetFacelets: targetFacelets,
            currentGeneration: currentGeneration,
            recoveryCost: recovery.totalCost + recovery.remainingOriginalWorkload,
            correctionCost: recovery.totalCost,
            lastDeviationMove: lastDeviationMove
        )
    }

    static func restorationDecision(
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String,
        targetFacelets: String,
        currentGeneration: Int
    ) async -> SmartCubeReplacementDecision {
        await verifiedDecision(
            identity: identity,
            sourceFacelets: sourceFacelets,
            targetFacelets: targetFacelets,
            currentGeneration: currentGeneration,
            recoveryCost: nil,
            correctionCost: nil,
            lastDeviationMove: nil
        )
    }

    private static func verifiedDecision(
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String,
        targetFacelets: String,
        currentGeneration: Int,
        recoveryCost: Int?,
        correctionCost: Int?,
        lastDeviationMove: String?
    ) async -> SmartCubeReplacementDecision {
        guard !Task.isCancelled else {
            return rejected(.cancelled, recoveryCost: recoveryCost)
        }

        let solution = await SmartCubeReplacementSolver.shared.moves(
            from: sourceFacelets,
            to: targetFacelets
        )
        guard !Task.isCancelled else {
            return rejected(.cancelled, recoveryCost: recoveryCost)
        }
        let tokens = SmartCubeRecoveryEngine.normalizedAdjacent(
            solution.split(whereSeparator: \.isWhitespace).map(String.init)
        )
        guard !tokens.isEmpty else {
            return rejected(.candidateUnavailable, recoveryCost: recoveryCost)
        }
        guard tokens.count <= maximumCandidateCost else {
            return rejected(.candidateOutsideBounds, recoveryCost: recoveryCost,
                            candidateCost: tokens.count)
        }

        var states = [sourceFacelets]
        for token in tokens {
            guard !Task.isCancelled else {
                return rejected(.cancelled, recoveryCost: recoveryCost,
                                candidateCost: tokens.count)
            }
            guard let next = SmartCubeBluetoothManager.facelets(states.last!, applying: token) else {
                return rejected(.candidateTargetMismatch, recoveryCost: recoveryCost,
                                candidateCost: tokens.count)
            }
            states.append(next)
        }
        guard states.last == targetFacelets else {
            return rejected(.candidateTargetMismatch, recoveryCost: recoveryCost,
                            candidateCost: tokens.count)
        }

        let isImmediateInverse = lastDeviationMove.map { inverse(of: $0) == tokens.first } ?? false
        let inversePenalty = isImmediateInverse ? immediateInversePenalty : 0
        if let recoveryCost, let correctionCost {
            let costReason = costDecision(
                correction: correctionCost,
                remaining: recoveryCost - correctionCost,
                candidateCost: tokens.count,
                lastDeviationMove: lastDeviationMove,
                firstCandidateMove: tokens.first
            )
            guard costReason == .adopted else {
                return rejected(
                    costReason,
                    recoveryCost: recoveryCost,
                    candidateCost: tokens.count,
                    inverseMovePenalty: inversePenalty
                )
            }
        }

        let replacement = SmartCubeReplacement(
            identity: identity,
            sourceFacelets: sourceFacelets,
            targetFacelets: targetFacelets,
            tokens: tokens,
            expectedFacelets: states,
            generation: currentGeneration + 1
        )
        return SmartCubeReplacementDecision(
            replacement: replacement,
            reason: .adopted,
            recoveryCost: recoveryCost,
            candidateCost: tokens.count,
            inverseMovePenalty: inversePenalty
        )
    }

    private static func rejected(
        _ reason: SmartCubeReplacementDecisionReason,
        recoveryCost: Int?,
        candidateCost: Int? = nil,
        inverseMovePenalty: Int = 0
    ) -> SmartCubeReplacementDecision {
        SmartCubeReplacementDecision(
            replacement: nil,
            reason: reason,
            recoveryCost: recoveryCost,
            candidateCost: candidateCost,
            inverseMovePenalty: inverseMovePenalty
        )
    }

    private static func inverse(of move: String) -> String {
        if move.hasSuffix("2") { return move }
        if move.hasSuffix("'") { return String(move.dropLast()) }
        return move + "'"
    }
}
#endif
