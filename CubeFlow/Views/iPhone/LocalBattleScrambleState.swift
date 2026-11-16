#if os(iOS)
import Foundation

/// One shared assignment per round. Preparation may be one round ahead;
/// eligibility and scoring never advance until both current solves finish.
struct LocalBattleScrambleState {
    struct Request: Equatable {
        let id = UUID()
        let round: Int
        let event: PuzzleEvent
    }
    struct Assignment: Equatable {
        let request: Request
        let text: String
    }
    private(set) var round = 0
    private(set) var roundOpenedAt = Date.now
    private var requests: [Int: Request] = [:]
    private var assignments: [Int: Assignment] = [:]
    private var errors: [Int: String] = [:]
    private(set) var active: [LocalBattlePlayer: Assignment] = [:]
    private(set) var completed: [LocalBattlePlayer: Assignment] = [:]

    var displayed: [LocalBattlePlayer: Assignment] {
        Dictionary(uniqueKeysWithValues: LocalBattlePlayer.allCases.compactMap { player in
            assignments[preparationRound(player)].map { (player, $0) }
        })
    }

    var hasRoundActivity: Bool {
        !active.isEmpty || LocalBattlePlayer.allCases.contains { waitingForOpponent($0) }
    }

    func waitingForOpponent(_ player: LocalBattlePlayer) -> Bool {
        completed[player]?.request.round == round
    }

    private func preparationRound(_ player: LocalBattlePlayer) -> Int {
        waitingForOpponent(player) ? round + 1 : round
    }

    func failure(for player: LocalBattlePlayer) -> String? { errors[preparationRound(player)] }

    mutating func request(event: PuzzleEvent, ahead: Bool = false) -> Request? {
        let index = ahead ? round + 1 : round
        guard assignments[index] == nil, requests[index] == nil,
              !ahead || assignments[round]?.request.event == event else { return nil }
        let request = Request(round: index, event: event)
        requests[index] = request
        errors[index] = nil
        return request
    }

    @discardableResult mutating func receive(_ text: String, for request: Request) -> Bool {
        guard requests[request.round] == request else { return false }
        requests[request.round] = nil
        assignments[request.round] = Assignment(request: request, text: text)
        return true
    }

    mutating func fail(_ message: String, for request: Request) {
        guard requests[request.round] == request else { return }
        requests[request.round] = nil
        errors[request.round] = message
    }

    func canBegin(_ player: LocalBattlePlayer, event: PuzzleEvent) -> Bool {
        active[player] == nil && !waitingForOpponent(player) && assignments[round]?.request.event == event
    }

    mutating func begin(_ player: LocalBattlePlayer, event: PuzzleEvent, startedAt: Date = .now) -> Bool {
        guard startedAt >= roundOpenedAt, canBegin(player, event: event) else { return false }
        active[player] = assignments[round]
        return true
    }

    @discardableResult mutating func finish(_ player: LocalBattlePlayer) -> Assignment? {
        guard let assignment = active.removeValue(forKey: player) else { return nil }
        completed[player] = assignment
        if LocalBattlePlayer.allCases.allSatisfy({ waitingForOpponent($0) }) {
            assignments[round] = nil
            errors[round] = nil
            round += 1
            roundOpenedAt = .now
        }
        return assignment
    }

    mutating func cancel(_ player: LocalBattlePlayer) { active[player] = nil }
}
#endif
