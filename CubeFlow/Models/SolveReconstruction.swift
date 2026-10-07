import Foundation

nonisolated struct SolveReconstruction: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum Completeness: String, Codable, Sendable {
        case complete
        case incomplete
    }

    struct Move: Codable, Equatable, Sendable, Identifiable {
        let canonicalMove: String
        let relativeTimestamp: TimeInterval
        let timestampSource: String
        let deviceTimestampMilliseconds: Int?
        let canonicalSequence: UInt64?

        var id: String {
            if let canonicalSequence { return "sequence-\(canonicalSequence)" }
            return "\(relativeTimestamp)-\(canonicalMove)"
        }
    }

    struct CombinedTimingAnchors: Codable, Equatable, Sendable {
        let timerStopRelativeTimestamp: TimeInterval
        let firstMoveBoundaryTrusted: Bool
        let finalMoveBoundaryTrusted: Bool
    }

    struct CombinedTimingMetrics: Equatable, Sendable {
        let startDelay: TimeInterval?
        let stopDelay: TimeInterval?
    }

    let version: Int
    let puzzleSize: Int
    let initialFacelets: String
    let moves: [Move]
    let completeness: Completeness
    let continuityReason: String?
    let combinedTimingAnchors: CombinedTimingAnchors?

    init(
        version: Int = currentVersion,
        puzzleSize: Int,
        initialFacelets: String,
        moves: [Move],
        completeness: Completeness,
        continuityReason: String? = nil,
        combinedTimingAnchors: CombinedTimingAnchors? = nil
    ) {
        self.version = version
        self.puzzleSize = puzzleSize
        self.initialFacelets = initialFacelets
        self.moves = moves
        self.completeness = completeness
        self.continuityReason = continuityReason
        self.combinedTimingAnchors = combinedTimingAnchors
    }

    var combinedTimingMetrics: CombinedTimingMetrics? {
        guard let anchors = combinedTimingAnchors else { return nil }
        let stop = anchors.timerStopRelativeTimestamp
        let first = moves.first?.relativeTimestamp
        let last = moves.last?.relativeTimestamp
        let startDelay = anchors.firstMoveBoundaryTrusted
            ? first.flatMap { $0 >= 0 && $0 <= stop ? $0 : nil }
            : nil
        let stopDelay = anchors.finalMoveBoundaryTrusted
            ? last.flatMap { $0 >= 0 && $0 <= stop ? stop - $0 : nil }
            : nil
        guard startDelay != nil || stopDelay != nil else { return nil }
        return CombinedTimingMetrics(startDelay: startDelay, stopDelay: stopDelay)
    }

    var isReplayable: Bool {
        guard version == Self.currentVersion,
              puzzleSize == 2 || puzzleSize == 3,
              initialFacelets.count == 6 * puzzleSize * puzzleSize else { return false }
        let stickers = Array(initialFacelets)
        guard "URFDLB".allSatisfy({ face in
            stickers.filter { $0 == face }.count == puzzleSize * puzzleSize
        }) else { return false }
        var previousTime: TimeInterval = 0
        for move in moves {
            guard move.relativeTimestamp.isFinite,
                  move.relativeTimestamp >= previousTime else { return false }
            previousTime = move.relativeTimestamp
        }
        return facelets(afterMoveCount: moves.count) != nil
    }

    func turnsPerSecond(actualDuration: TimeInterval) -> Double? {
        guard completeness == .complete, isReplayable,
              !moves.isEmpty, actualDuration.isFinite, actualDuration > 0 else { return nil }
        let rate = Double(moves.count) / actualDuration
        return rate.isFinite ? rate : nil
    }

    func facelets(afterMoveCount requestedCount: Int) -> String? {
        guard version == Self.currentVersion,
              puzzleSize == 2 || puzzleSize == 3,
              initialFacelets.count == 6 * puzzleSize * puzzleSize else { return nil }
        var facelets = initialFacelets
        for move in moves.prefix(min(max(0, requestedCount), moves.count)) {
            guard let turn = CubeLayerTurn(move.canonicalMove),
                  let next = turn.applying(to: facelets, size: puzzleSize) else { return nil }
            facelets = next
        }
        return facelets
    }
}

#if os(iOS)
nonisolated struct SmartCubeReconstructionCapture: Equatable {
    private(set) var initialFacelets: String?
    private(set) var startedAt: Date?
    private(set) var moves: [SolveReconstruction.Move] = []
    private(set) var completeness = SolveReconstruction.Completeness.complete
    private(set) var continuityReason: SmartCubeContinuityReason?
    private var lastSequence: UInt64?
    private var firstMoveBoundaryTrusted = false
    private var finalMoveBoundaryTrusted = false

    var isCapturing: Bool { initialFacelets != nil && startedAt != nil }

    mutating func start(
        initialFacelets: String,
        at startDate: Date? = nil,
        with update: SmartCubeCanonicalUpdate? = nil
    ) {
        self.initialFacelets = initialFacelets
        startedAt = startDate ?? update?.move.localTimestamp ?? .now
        moves.removeAll(keepingCapacity: true)
        completeness = .complete
        continuityReason = nil
        lastSequence = nil
        firstMoveBoundaryTrusted = false
        finalMoveBoundaryTrusted = false
        if let update { append(update) }
    }

    mutating func append(_ update: SmartCubeCanonicalUpdate) {
        guard let startedAt,
              update.sequence != lastSequence,
              update.move.localTimestamp >= startedAt else { return }
        let relativeTimestamp = update.move.localTimestamp.timeIntervalSince(startedAt)
        moves.append(SolveReconstruction.Move(
            canonicalMove: update.move.move,
            relativeTimestamp: relativeTimestamp,
            timestampSource: update.move.timestampSource.persistenceRawValue,
            deviceTimestampMilliseconds: update.move.cubeTimestampMilliseconds,
            canonicalSequence: update.sequence
        ))
        lastSequence = update.sequence
        if moves.count == 1 {
            firstMoveBoundaryTrusted = update.isStateTrusted
        }
        finalMoveBoundaryTrusted = update.isStateTrusted
        if !update.isStateTrusted {
            completeness = .incomplete
            continuityReason = continuityReason ?? .historyGap
        }
    }

    mutating func markIncomplete(_ reason: SmartCubeContinuityReason) {
        completeness = .incomplete
        continuityReason = continuityReason ?? reason
        finalMoveBoundaryTrusted = false
    }

    func reconstruction(
        puzzleSize: Int? = nil,
        combinedTimerStoppedAt: Date? = nil
    ) -> SolveReconstruction? {
        guard let initialFacelets, let startedAt else { return nil }
        let resolvedSize = puzzleSize ?? (initialFacelets.count == 24 ? 2 : 3)
        let anchors = combinedTimerStoppedAt.map {
            SolveReconstruction.CombinedTimingAnchors(
                timerStopRelativeTimestamp: max(0, $0.timeIntervalSince(startedAt)),
                firstMoveBoundaryTrusted: firstMoveBoundaryTrusted,
                finalMoveBoundaryTrusted: finalMoveBoundaryTrusted
            )
        }
        return SolveReconstruction(
            puzzleSize: resolvedSize,
            initialFacelets: initialFacelets,
            moves: moves,
            completeness: completeness,
            continuityReason: continuityReason?.rawValue,
            combinedTimingAnchors: anchors
        )
    }

    mutating func reset() {
        self = Self()
    }
}

nonisolated extension SmartCubeMoveTimestampSource {
    var persistenceRawValue: String {
        switch self {
        case .deviceClock: "deviceClock"
        case .reconstructed: "reconstructed"
        case .hostReceipt: "hostReceipt"
        }
    }
}
#endif
