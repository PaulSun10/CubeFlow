import Foundation

nonisolated struct CombinedSolveReadiness: Equatable, Sendable {
    let smartCubeConnected: Bool
    let smartCubeObservationReady: Bool
    let scrambleVerified: Bool
    let smartCubeReady: Bool
    let smartTimerConnected: Bool
    let smartTimerReady: Bool

    var isReady: Bool {
        smartCubeConnected && smartCubeObservationReady && scrambleVerified
            && smartCubeReady && smartTimerConnected && smartTimerReady
    }
}

nonisolated struct CombinedSolveLifecycle: Equatable {
    enum Completion: Equatable {
        case none
        case save(seconds: Double)
        case timerInterrupted
    }

    private(set) var isActive = false
    private(set) var didProduceResult = false

    @discardableResult
    mutating func timerDidStart(readiness: CombinedSolveReadiness) -> Bool {
        guard readiness.isReady, !isActive, !didProduceResult else { return false }
        self = Self(isActive: true)
        return true
    }

    mutating func timerDidStop(seconds: Double) -> Completion {
        guard isActive, !didProduceResult, seconds > 0 else { return .none }
        didProduceResult = true
        isActive = false
        return .save(seconds: seconds)
    }

    mutating func timerDidDisconnect() -> Completion {
        guard isActive, !didProduceResult else { return .none }
        isActive = false
        didProduceResult = true
        return .timerInterrupted
    }

    mutating func reset() {
        self = Self()
    }
}

nonisolated enum CombinedPhysicalResultClassifier {
    static func result(facelets: String?, isStateTrusted: Bool) -> SolveResult {
        // Canonical facelets contain completed turns, not physical layer angles.
        // An aligned unsolved state is DNF; +2 remains manual until hardware can
        // provide trustworthy misalignment data for the WCA alignment rule.
        guard isStateTrusted,
              let facelets,
              let puzzleSize = [2, 3].first(where: { facelets.count == 6 * $0 * $0 }),
              CubeStateEquivalence.isSolved(facelets, puzzleSize: puzzleSize) else { return .dnf }
        return .solved
    }
}
