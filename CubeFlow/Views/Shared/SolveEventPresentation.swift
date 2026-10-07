import Foundation

extension PuzzleEvent {
    nonisolated static func fromSolveEvent(_ raw: String) -> PuzzleEvent? {
        PuzzleEvent(rawValue: raw) ?? allCases.first { $0.cubingEventID == raw.lowercased() }
    }
    nonisolated var cubingEventID: String {
        switch self {
        case .twoByTwo: "222"
        case .threeByThree: "333"
        case .fourByFour, .fourByFourFast: "444"
        case .fiveByFive: "555"
        case .sixBySix: "666"
        case .sevenBySeven: "777"
        case .megaminx: "minx"
        case .pyraminx: "pyram"
        case .square1: "sq1"
        case .clock: "clock"
        case .skewb: "skewb"
        case .fto: "fto"
        case .threeByThreeOH: "333oh"
        case .threeByThreeFM: "333fm"
        case .threeByThreeBLD: "333bf"
        case .fourByFourBLD: "444bf"
        case .fiveByFiveBLD: "555bf"
        case .threeByThreeMBLD: "333mbf"
        }
    }
}
