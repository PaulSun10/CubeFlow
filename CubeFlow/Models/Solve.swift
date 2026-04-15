import Foundation
import SwiftData

enum SolveResult: String, CaseIterable {
    case solved
    case plusTwo
    case dnf
}

@Model
final class Solve {
    var id: UUID = UUID()
    var time: Double = 0
    var date: Date = Date.now
    var scramble: String = ""
    var event: String = ""
    var resultRaw: String = SolveResult.solved.rawValue
    var session: Session? = nil

    var result: SolveResult {
        get { SolveResult(rawValue: resultRaw) ?? .solved }
        set { resultRaw = newValue.rawValue }
    }

    init(
        time: Double,
        date: Date = .now,
        scramble: String = "",
        event: String,
        result: SolveResult = .solved,
        session: Session?
    ) {
        self.time = time
        self.date = date
        self.scramble = scramble
        self.event = event
        self.resultRaw = result.rawValue
        self.session = session
    }
}
