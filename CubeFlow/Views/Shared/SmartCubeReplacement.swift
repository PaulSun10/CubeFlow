#if os(iOS)
import Foundation

private actor SmartCubeReplacementSolver {
    static let shared = SmartCubeReplacementSolver()

    func moves(from sourceFacelets: String, to targetFacelets: String) -> String {
        guard !Task.isCancelled else { return "" }
        return Min2PhaseBridge.moves(fromFacelets: sourceFacelets, toFacelets: targetFacelets)
    }

    func boundedMoves(from source: String, to target: String, maximumDepth: Int,
                      identity: SmartCubeRecoveryPlanIdentity, queuedAt: TimeInterval) -> String {
        guard !Task.isCancelled else { return "" }
        #if DEBUG
        SmartCubeGuidanceTrace.record("native-enter", identity: identity, source: source, target: target,
            detail: "waitMS=\((ProcessInfo.processInfo.systemUptime - queuedAt) * 1000)")
        #endif
        let initial = Min2PhaseBridge.search(from: source, to: target, maximumDepth: maximumDepth,
            probeLimit: 1_000_000, minimumProbes: 0, optimal: false,
            maximumMilliseconds: 350, cancelled: { Task.isCancelled })
        #if DEBUG
        SmartCubeGuidanceTrace.native("native-primary", identity: identity, source: source, target: target)
        #endif
        let moves = initial.split(whereSeparator: \.isWhitespace)
        guard !Task.isCancelled, !moves.isEmpty,
              moves.allSatisfy({ SmartCubeTargetPath.moves.contains(String($0)) }) else { return initial }
        // A second, strictly tighter bounded search can improve the first
        // two-phase answer. Exhaustion is not a proof of global optimality.
        let improved = Min2PhaseBridge.search(from: source, to: target, maximumDepth: moves.count - 1,
            probeLimit: 10_000, minimumProbes: 0, optimal: false,
            maximumMilliseconds: 100, cancelled: { Task.isCancelled })
        #if DEBUG
        SmartCubeGuidanceTrace.native("native-improvement", identity: identity, source: source, target: target)
        #endif
        let shorter = improved.split(whereSeparator: \.isWhitespace)
        return !shorter.isEmpty && shorter.count < moves.count
            && shorter.allSatisfy({ SmartCubeTargetPath.moves.contains(String($0)) }) ? improved : initial
    }
}

nonisolated struct SmartCubeReplacement: Sendable {
    let identity: SmartCubeRecoveryPlanIdentity
    let sourceFacelets: String
    let targetFacelets: String
    let tokens: [String]
    let expectedFacelets: [String]
    let generation: Int
    var isProvenOptimal = false
    var origin = "verified-candidate"

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
    var verifiedKnownCost: Int? = nil
    var verifiedAt: TimeInterval = 0
}

nonisolated enum SmartCubeReplacementPlanner {
    typealias Solver = @Sendable (String, String) async -> String
    static let maximumCandidateCost = 21

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
        // A compact valid fallback may remain visible while the target search
        // runs. This is presentation only, never a replan/scheduling threshold.
        if recovery.totalCost <= 2 { return .recovery(recovery) }
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
        guard candidateCost > 0, candidateCost <= maximumCandidateCost else { return .candidateOutsideBounds }
        let recoveryCost = correction + remaining
        guard candidateCost < recoveryCost else { return .candidateNotShorter }
        return .adopted
    }

    @concurrent
    static func decision(
        recovery: SmartCubeRecoveryPlan,
        targetFacelets: String,
        currentGeneration: Int,
        lastDeviationMove: String?,
        originalTokens: [String]? = nil
    ) async -> SmartCubeReplacementDecision {
        return await verifiedDecision(
            identity: recovery.identity,
            sourceFacelets: recovery.sourceFacelets,
            targetFacelets: targetFacelets,
            currentGeneration: currentGeneration,
            recoveryCost: recovery.totalCost + recovery.remainingOriginalWorkload,
            correctionCost: recovery.totalCost,
            lastDeviationMove: lastDeviationMove,
            knownPath: originalTokens.flatMap { recovery.executableMoves(originalTokens: $0) }
        )
    }

    @concurrent
    static func restorationDecision(
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String,
        targetFacelets: String,
        currentGeneration: Int,
        solver: Solver? = nil
    ) async -> SmartCubeReplacementDecision {
        await verifiedDecision(
            identity: identity,
            sourceFacelets: sourceFacelets,
            targetFacelets: targetFacelets,
            currentGeneration: currentGeneration,
            recoveryCost: nil,
            correctionCost: nil,
            lastDeviationMove: nil,
            knownPath: nil,
            solver: solver
        )
    }

    /// A fresh current-state answer is publishable even when the best verified
    /// route equals the fallback. Equality must not masquerade as "not solved
    /// yet" until enough physical turns make a two-phase answer win a cost gate.
    @concurrent
    static func currentStateDecision(identity: SmartCubeRecoveryPlanIdentity,
                                     sourceFacelets: String, targetFacelets: String,
                                     currentGeneration: Int, knownPath: [String]?,
                                     shortSearchAlreadyMissed: Bool = false) async -> SmartCubeReplacementDecision {
        #if DEBUG
        let normalizationStart = ProcessInfo.processInfo.systemUptime
        #endif
        let normalized = knownPath.map(SmartCubeRecoveryEngine.simplified)
        let validKnown = normalized.flatMap { path -> [String]? in
            let end = path.reduce(Optional(sourceFacelets)) { state, move in
                state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
            }
            return end == targetFacelets ? path : nil
        }
        let maximumDepth = min(maximumCandidateCost, validKnown?.count ?? maximumCandidateCost)
        #if DEBUG
        SmartCubeGuidanceTrace.record("snapshot-normalized", identity: identity, source: sourceFacelets, target: targetFacelets,
            detail: "ms=\((ProcessInfo.processInfo.systemUptime - normalizationStart) * 1000) knownCost=\(validKnown?.count ?? -1)")
        #endif
        return await verifiedDecision(identity: identity, sourceFacelets: sourceFacelets,
            targetFacelets: targetFacelets, currentGeneration: currentGeneration,
            recoveryCost: nil, correctionCost: nil, lastDeviationMove: nil, knownPath: validKnown,
            solver: { source, target in
                #if DEBUG
                let queued = ProcessInfo.processInfo.systemUptime
                #else
                let queued: TimeInterval = 0
                #endif
                return await SmartCubeReplacementSolver.shared.boundedMoves(from: source, to: target,
                    maximumDepth: maximumDepth, identity: identity, queuedAt: queued)
            }, skipShortSearch: shortSearchAlreadyMissed)
    }

    /// Independent of the serial native actor: a near-target latest request must
    /// not sit behind an obsolete synchronous improvement search.
    @concurrent static func shortStateDecision(_ request: SmartCubeGuidanceController.Request) async -> SmartCubeReplacementDecision {
        #if DEBUG
        let start = ProcessInfo.processInfo.systemUptime
        #endif
        let short = await SmartCubeTargetPath.shortestWithinThree(from: request.sourceFacelets, to: request.targetFacelets)
        #if DEBUG
        SmartCubeGuidanceTrace.record("exact-search", identity: request.identity, source: request.sourceFacelets, target: request.targetFacelets,
            detail: "ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000) count=\(short?.count ?? -1) cancelled=\(Task.isCancelled)")
        #endif
        guard let moves = short,
              !moves.isEmpty, !Task.isCancelled else {
            return rejected(.candidateUnavailable, recoveryCost: nil)
        }
        return await verifiedDecision(identity: request.identity, sourceFacelets: request.sourceFacelets,
            targetFacelets: request.targetFacelets, currentGeneration: request.generation,
            recoveryCost: nil, correctionCost: nil, lastDeviationMove: nil, knownPath: request.knownPath,
            precomputedShort: moves)
    }

    private static func verifiedDecision(
        identity: SmartCubeRecoveryPlanIdentity,
        sourceFacelets: String,
        targetFacelets: String,
        currentGeneration: Int,
        recoveryCost: Int?,
        correctionCost: Int?,
        lastDeviationMove: String?,
        knownPath: [String]?,
        solver: Solver? = nil,
        precomputedShort: [String]? = nil,
        skipShortSearch: Bool = false
    ) async -> SmartCubeReplacementDecision {
        guard !Task.isCancelled else {
            return rejected(.cancelled, recoveryCost: recoveryCost)
        }

        let short: [String]?
        if let precomputedShort { short = precomputedShort }
        else if skipShortSearch { short = nil }
        else { short = await SmartCubeTargetPath.shortestWithinThree(from: sourceFacelets, to: targetFacelets) }
        let solution: String
        if let short { solution = short.joined(separator: " ") }
        else if sourceFacelets.count == 54, targetFacelets.count == 54 {
            if let solver { solution = await solver(sourceFacelets, targetFacelets) }
            else { solution = await SmartCubeReplacementSolver.shared.moves(from: sourceFacelets, to: targetFacelets) }
        } else { solution = "" }
        guard !Task.isCancelled else {
            return rejected(.cancelled, recoveryCost: recoveryCost)
        }
        #if DEBUG
        let verificationStart = ProcessInfo.processInfo.systemUptime
        #endif
        let rawTokens = solution.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens = SmartCubeRecoveryEngine.normalizedAdjacent(rawTokens)
        #if DEBUG
        let calculatedTokens = tokens
        #endif
        let candidateEnd = tokens.reduce(Optional(sourceFacelets)) { state, move in
            state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
        }
        var verifiedKnownCost: Int?
        if let knownPath {
            let normalized = SmartCubeRecoveryEngine.simplified(knownPath)
            let end = normalized.reduce(Optional(sourceFacelets)) { state, move in
                state.flatMap { SmartCubeBluetoothManager.facelets($0, applying: move) }
            }
            if end == targetFacelets {
                verifiedKnownCost = normalized.count
                if candidateEnd != targetFacelets || tokens.isEmpty || normalized.count <= tokens.count { tokens = normalized }
            }
        }
        #if DEBUG
        SmartCubeGuidanceTrace.record("candidate-evaluated", identity: identity, source: sourceFacelets, target: targetFacelets,
            detail: "shown=\(SmartCubeGuidanceTrace.path(knownPath)) raw=\(SmartCubeGuidanceTrace.path(rawTokens)) calculated=\(SmartCubeGuidanceTrace.path(calculatedTokens)) selected=\(SmartCubeGuidanceTrace.path(tokens)) verifiedKnown=\(verifiedKnownCost ?? -1)")
        #endif
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

        let inversePenalty = 0
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
            generation: currentGeneration + 1,
            isProvenOptimal: short != nil && short?.count == tokens.count,
            origin: short != nil ? "exact-htm" : "best-verified"
        )
        var result = SmartCubeReplacementDecision(
            replacement: replacement,
            reason: .adopted,
            recoveryCost: recoveryCost,
            candidateCost: tokens.count,
            inverseMovePenalty: inversePenalty,
            verifiedKnownCost: verifiedKnownCost
        )
        #if DEBUG
        result.verifiedAt = ProcessInfo.processInfo.systemUptime
        SmartCubeGuidanceTrace.record("verified", identity: identity, source: sourceFacelets, target: targetFacelets,
            detail: "ms=\((result.verifiedAt - verificationStart) * 1000) count=\(tokens.count) origin=\(replacement.origin) optimal=\(replacement.isProvenOptimal) improvesKnown=\(tokens.count < (verifiedKnownCost ?? .max))")
        #endif
        return result
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
