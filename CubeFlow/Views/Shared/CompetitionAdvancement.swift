import Foundation
import SwiftUI

nonisolated enum CompetitionAdvancement: Sendable, Equatable {
    case confirmed, possible
    var questionable: Bool { self == .possible }
}

enum CompetitionAdvancementStyle {
    static func background(advancing: Bool?, questionable: Bool?) -> Color {
        if questionable == true { return Color(red: 1, green: 245 / 255, blue: 157 / 255) }
        if advancing == true { return Color(red: 0, green: 230 / 255, blue: 118 / 255) }
        return .clear
    }
    static func foreground(advancing: Bool?, questionable: Bool?) -> Color {
        advancing == true || questionable == true ? .black : .primary
    }
}

/// WCA Live semantics: current qualification, then qualification with every missing
/// attempt optimistically completed. Only complete results can be confirmed.
/// Reference: thewca/wca-live, scoretaking/advancing.ex (algorithm semantics, not copied code).
nonisolated enum CompetitionAdvancementCalculation {
    private struct Score: Equatable, Comparable {
        let primary: Int
        let best: Int
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.primary != rhs.primary ? lhs.primary < rhs.primary : lhs.best < rhs.best
        }
    }

    static func states(_ snapshot: CubingChinaLiveSnapshot, isFinal: Bool) -> [String: CompetitionAdvancement] {
        let round = snapshot.round
        guard ["open", "live", "finished"].contains(round.status),
              !round.eventId.hasPrefix("333mb"),
              ["a", "m", "1", "2", "3", "5"].contains(round.round.format),
              (try? snapshot.validated()) != nil,
              Set(snapshot.results.map(\.userId)).count == snapshot.results.count else { return [:] }
        let rule = round.round.advancementCondition
        guard isFinal || (rule.map { ["ranking", "percent", "attemptResult", "attempt-result"].contains($0.type) && $0.level > 0 } == true) else { return [:] }
        if rule?.type == "percent", let level = rule?.level, level > 100 { return [:] }
        let average = ["a", "m"].contains(round.round.format)
        let optimistic = snapshot.results.compactMap { value -> (CubingChinaLiveResult, Score, Bool)? in
            guard let completed = completion(value.attempts, round: round) else { return nil }
            let best = completed.attempts.filter { $0 > 0 }.min() ?? -1
            guard let primary = average ? mean(completed.attempts, trimmed: round.round.format == "a", multiplier: round.eventId == "333fm" ? 100 : 1) : best else { return nil }
            return (value, Score(primary: primary > 0 ? primary : Int.max,
                                 best: average ? (best > 0 ? best : Int.max) : 0), completed.isComplete)
        }
        // An unsupported/holey result must not disappear from the hypothetical field.
        guard optimistic.count == snapshot.results.count else { return [:] }
        let ordered = optimistic.sorted { $0.1 < $1.1 }
        var hypotheticalRanks: [String: Int] = [:]
        var previous: Score?
        var ranking = 0
        for (index, item) in ordered.enumerated() {
            if previous != item.1 { ranking = index + 1; previous = item.1 }
            hypotheticalRanks[String(item.0.id.rawValue)] = ranking
        }
        let currentBoundary = exclusionBoundary(snapshot.results.compactMap(\.position), total: snapshot.results.count)
        let futureBoundary = exclusionBoundary(Array(hypotheticalRanks.values), total: snapshot.results.count)
        func qualifies(rank: Int?, primary: Int, best: Int, boundary: Int) -> Bool {
            guard let rank, best > 0 else { return false }
            if isFinal { return rank <= 3 }
            guard rank < boundary, let rule else { return false }
            switch rule.type {
            case "ranking": return rank <= rule.level
            case "percent": return rank <= snapshot.results.count * min(rule.level, 100) / 100
            case "attemptResult", "attempt-result": return primary > 0 && primary < rule.level
            default: return false
            }
        }
        var states: [String: CompetitionAdvancement] = [:]
        for (value, score, complete) in optimistic {
            let primary = average ? value.average : value.best
            guard qualifies(rank: value.position, primary: primary, best: value.best, boundary: currentBoundary) else { continue }
            let id = String(value.id.rawValue)
            let clinched = complete && qualifies(rank: hypotheticalRanks[id],
                primary: score.primary == Int.max ? -1 : score.primary, best: score.best == Int.max ? -1 : (average ? score.best : value.best),
                boundary: futureBoundary)
            states["ccc-result:\(id)"] = clinched ? .confirmed : .possible
        }
        return states
    }

    private static func exclusionBoundary(_ ranks: [Int], total: Int) -> Int {
        let ranks = ranks.sorted(), capacity = total * 3 / 4
        return ranks.count > capacity ? ranks[capacity] : (ranks.last ?? 0) + 1
    }

    private static func completion(_ values: [Int], round: CubingChinaLiveRound) -> (attempts: [Int], isComplete: Bool)? {
        let entered = Array(values.prefix { $0 != 0 })
        guard values.dropFirst(entered.count).allSatisfy({ $0 == 0 }), entered.allSatisfy({ $0 >= -2 }),
              entered.count <= round.attemptCount else { return nil }
        var count = round.attemptCount
        if let cutoff = round.round.cutoff {
            guard cutoff.numberOfAttempts > 0, cutoff.numberOfAttempts <= count, cutoff.attemptResult > 0 else { return nil }
            if entered.count >= cutoff.numberOfAttempts,
               !entered.prefix(cutoff.numberOfAttempts).contains(where: { $0 > 0 && $0 < cutoff.attemptResult }) {
                count = cutoff.numberOfAttempts
            }
        }
        guard entered.count <= count else { return nil }
        return (entered + Array(repeating: 1, count: count - entered.count), entered.count == count)
    }

    private static func mean(_ values: [Int], trimmed: Bool, multiplier: Int) -> Int? {
        // Cutoff failures cannot acquire an average from their short attempt list.
        guard values.count == (trimmed ? 5 : 3) else { return 0 }
        var sorted = values.sorted { ($0 > 0 ? $0 : Int.max) < ($1 > 0 ? $1 : Int.max) }
        if trimmed { sorted.removeFirst(); sorted.removeLast() }
        guard sorted.allSatisfy({ $0 > 0 }) else { return -1 }
        var sum: Int64 = 0
        for value in sorted {
            let added = sum.addingReportingOverflow(Int64(value))
            guard !added.overflow else { return nil }
            sum = added.partialValue
        }
        let scaled = sum.multipliedReportingOverflow(by: Int64(multiplier))
        guard !scaled.overflow else { return nil }
        let divisor = Int64(sorted.count)
        let average = Int(scaled.partialValue / divisor + (scaled.partialValue % divisor * 2 >= divisor ? 1 : 0))
        // WCA 9f2 rounds time averages above ten minutes to whole seconds, not FMC points.
        if multiplier == 1, average > 60000 {
            return (average / 100 + (average % 100 >= 50 ? 1 : 0)) * 100
        }
        return average
    }
}
