#if os(iOS)
import Foundation

nonisolated struct TimerScrambleGenerationContext: Equatable, Sendable {
    let sessionID: UUID?
    let event: PuzzleEvent
    let multiBlindCount: Int
    let unavailableMessage: String

    init(
        sessionID: UUID?,
        event: PuzzleEvent,
        multiBlindCount: Int,
        unavailableMessage: String
    ) {
        self.sessionID = sessionID
        self.event = event
        self.multiBlindCount = event == .threeByThreeMBLD ? max(1, multiBlindCount) : 1
        self.unavailableMessage = unavailableMessage
    }
}

nonisolated struct TimerScrambleGenerationPayload: Equatable, Sendable {
    let context: TimerScrambleGenerationContext
    let scrambles: [String]

    var primaryScramble: String { scrambles.first ?? "" }
}

nonisolated struct TimerScramblePrefetchSlot: Equatable, Sendable {
    struct Request: Equatable, Sendable {
        let id: UUID
        let context: TimerScrambleGenerationContext
    }

    private(set) var request: Request?
    private(set) var payload: TimerScrambleGenerationPayload?

    mutating func begin(for context: TimerScrambleGenerationContext) -> Request {
        let request = Request(id: UUID(), context: context)
        self.request = request
        payload = nil
        return request
    }

    @discardableResult
    mutating func complete(
        _ generated: TimerScrambleGenerationPayload,
        for completedRequest: Request
    ) -> Bool {
        guard request == completedRequest,
              generated.context == completedRequest.context else { return false }
        request = nil
        payload = generated
        return true
    }

    mutating func consume(for context: TimerScrambleGenerationContext) -> TimerScrambleGenerationPayload? {
        guard payload?.context == context else { return nil }
        let result = payload
        payload = nil
        return result
    }

    mutating func invalidate() {
        request = nil
        payload = nil
    }

    func hasPendingRequest(for context: TimerScrambleGenerationContext) -> Bool {
        request?.context == context
    }
}

nonisolated enum TimerScrambleGenerator {
    private static let queue = DispatchQueue(
        label: "CubeFlow.timer-scramble-generation",
        qos: .userInitiated
    )

    static func prewarm() {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        queue.async {
            let startedAt = ProcessInfo.processInfo.systemUptime
            TNoodleNativeBridge.prewarm()
            #if DEBUG
            let finishedAt = ProcessInfo.processInfo.systemUptime
            print(
                String(
                    format: "[ScramblePerf] prewarm queue_ms=%.1f engine_ms=%.1f total_ms=%.1f",
                    (startedAt - requestedAt) * 1_000,
                    (finishedAt - startedAt) * 1_000,
                    (finishedAt - requestedAt) * 1_000
                )
            )
            #endif
        }
    }

    static func generate(
        for context: TimerScrambleGenerationContext,
        reason: String,
        completion: @escaping @MainActor (TimerScrambleGenerationPayload) -> Void
    ) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        queue.async {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let payload = generateSynchronously(for: context)
            let finishedAt = ProcessInfo.processInfo.systemUptime
            #if DEBUG
            print(
                String(
                    format: "[ScramblePerf] generation reason=%@ event=%@ count=%ld queue_ms=%.1f engine_ms=%.1f total_ms=%.1f",
                    reason,
                    context.event.rawValue,
                    payload.scrambles.count,
                    (startedAt - requestedAt) * 1_000,
                    (finishedAt - startedAt) * 1_000,
                    (finishedAt - requestedAt) * 1_000
                )
            )
            #endif
            DispatchQueue.main.async {
                completion(payload)
            }
        }
    }

    static func generateSynchronously(
        for context: TimerScrambleGenerationContext
    ) -> TimerScrambleGenerationPayload {
        let count = context.event == .threeByThreeMBLD ? context.multiBlindCount : 1
        let scrambles = (0..<count).map { _ in
            preferredScramble(
                for: context.event,
                unavailableMessage: context.unavailableMessage
            )
        }
        return TimerScrambleGenerationPayload(context: context, scrambles: scrambles)
    }

    static func preferredScramble(
        for event: PuzzleEvent,
        unavailableMessage: String
    ) -> String {
        if event == .fourByFourFast {
            return fastFourByFourScramble()
        }

        let registry = tnoodleRegistry(for: event)
        if let scramble = TNoodleScrambler.scramble(for: registry), !scramble.isEmpty {
            return scramble
        }
        if let diagnostic = TNoodleScrambler.diagnostic(for: registry) {
            return "\(unavailableMessage)\n\(diagnostic)"
        }
        return unavailableMessage
    }

    private static func fastFourByFourScramble() -> String {
        let moves: [(notation: String, axis: Int)] = [
            ("R", 0), ("L", 0), ("Rw", 0), ("Lw", 0),
            ("U", 1), ("D", 1), ("Uw", 1), ("Dw", 1),
            ("F", 2), ("B", 2), ("Fw", 2), ("Bw", 2)
        ]
        let suffixes = ["", "'", "2"]
        var generator = SystemRandomNumberGenerator()
        var scramble: [String] = []
        var previousAxis: Int?
        while scramble.count < 40 {
            guard let move = moves.randomElement(using: &generator) else { break }
            guard move.axis != previousAxis else { continue }
            scramble.append(move.notation + (suffixes.randomElement(using: &generator) ?? ""))
            previousAxis = move.axis
        }
        return scramble.joined(separator: " ")
    }

    private static func tnoodleRegistry(for event: PuzzleEvent) -> TNoodlePuzzleRegistry {
        switch event {
        case .twoByTwo: .two
        case .threeByThree, .threeByThreeOH, .threeByThreeMBLD: .three
        case .fourByFour, .fourByFourFast: .four
        case .fiveByFive: .five
        case .sixBySix: .six
        case .sevenBySeven: .seven
        case .megaminx: .mega
        case .pyraminx: .pyra
        case .square1: .sq1
        case .clock: .clock
        case .skewb: .skewb
        case .threeByThreeFM: .threeFM
        case .threeByThreeBLD: .threeNI
        case .fourByFourBLD: .fourNI
        case .fiveByFiveBLD: .fiveNI
        }
    }
}
#endif
