#if os(iOS)
import Foundation

/// Scrambles belong to a player/request, never to the shared event cache.
struct LocalBattleScrambleState {
    struct Request: Equatable {
        let id = UUID()
        let player: LocalBattlePlayer
        let event: PuzzleEvent
    }
    struct Assignment: Equatable {
        let request: Request
        let text: String
    }
    private(set) var requests: [LocalBattlePlayer: Request] = [:]
    private(set) var displayed: [LocalBattlePlayer: Assignment] = [:]
    private(set) var active: [LocalBattlePlayer: Assignment] = [:]
    private(set) var completed: [LocalBattlePlayer: Assignment] = [:]
    private(set) var failures: [LocalBattlePlayer: String] = [:]

    mutating func request(_ player: LocalBattlePlayer, event: PuzzleEvent) -> Request {
        let request = Request(player: player, event: event)
        requests[player] = request
        failures[player] = nil
        if displayed[player]?.request.event != event { displayed[player] = nil }
        active[player] = nil
        return request
    }
    @discardableResult mutating func receive(_ text: String, for request: Request) -> Bool {
        guard requests[request.player] == request, active[request.player] == nil else { return false }
        requests[request.player] = nil
        displayed[request.player] = Assignment(request: request, text: text)
        return true
    }
    mutating func fail(_ message: String, for request: Request) {
        guard requests[request.player] == request else { return }
        requests[request.player] = nil
        displayed[request.player] = nil
        failures[request.player] = message
    }
    mutating func begin(_ player: LocalBattlePlayer, event: PuzzleEvent) -> Bool {
        guard requests[player] == nil, active[player] == nil,
              let assignment = displayed[player], assignment.request.event == event,
              completed[player] != assignment else { return false }
        active[player] = assignment
        return true
    }
    @discardableResult mutating func finish(_ player: LocalBattlePlayer) -> Assignment? {
        guard let assignment = active.removeValue(forKey: player) else { return nil }
        completed[player] = assignment
        return assignment
    }
    mutating func cancel(_ player: LocalBattlePlayer) { active[player] = nil }
}
#endif
