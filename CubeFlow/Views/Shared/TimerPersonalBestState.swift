import Foundation

/// Current-window PBs, using the same penalized/trimmed metrics as My Results.
nonisolated struct TimerPersonalBestState: Equatable {
    let solveID: UUID?
    let metrics: Set<String>
    static let empty = Self(solveID: nil, metrics: [])

    static func current(from samples: [SessionSolveSample]) -> Self {
        let ordered = samples.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let newest = ordered.first else { return .empty }
        var records = Set<String>()
        let previousBest = ordered.dropFirst().lazy.compactMap(\.adjustedTime).min()
        if let value = newest.adjustedTime, value.isFinite,
           previousBest == nil || value < previousBest! {
            records.insert("best")
        }
        let metrics = AverageListType.allCases.filter { ordered.count >= $0.solveCount }.map {
            RecordAverageMetric(title: $0.rawValue, solveCount: $0.solveCount, kind: $0.recordMetricKind)
        }
        for (metric, evaluation) in zip(metrics, DataTabComputation.evaluateRecordSummaries(metrics: metrics, solves: ordered))
            where evaluation.currentIsStrictlyBest {
            records.insert(metric.title)
        }
        return Self(solveID: newest.id, metrics: records)
    }
}

nonisolated struct TimerPBCelebrationGate {
    private(set) var lastCelebratedID: UUID?

    mutating func accept(completedSolveID: UUID, state: TimerPersonalBestState) -> Bool {
        guard state.solveID == completedSolveID, !state.metrics.isEmpty,
              lastCelebratedID != completedSolveID else { return false }
        lastCelebratedID = completedSolveID
        return true
    }
}

nonisolated struct TimerCurrentResultPBState {
    private(set) var solveID: UUID?
    var isVisible: Bool { solveID != nil }

    mutating func completed(_ id: UUID, records: TimerPersonalBestState) {
        solveID = records.solveID == id && !records.metrics.isEmpty ? id : nil
    }

    mutating func reconcile(records: TimerPersonalBestState) {
        if solveID != records.solveID || records.metrics.isEmpty { solveID = nil }
    }

    mutating func timingDidBegin() { solveID = nil }
}
