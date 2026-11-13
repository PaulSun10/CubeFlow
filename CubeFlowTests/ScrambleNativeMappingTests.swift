#if DEBUG
import XCTest
@testable import CubeFlow

final class ScrambleNativeMappingTests: XCTestCase {
    func testEveryEventUsesPinnedMainArrayABI() {
        let expected: [PuzzleEvent: Int] = [.twoByTwo: 0, .threeByThree: 1, .fourByFour: 2,
            .fourByFourFast: 2, .fiveByFive: 3, .sixBySix: 4, .sevenBySeven: 5,
            .square1: 6, .megaminx: 7, .pyraminx: 8, .clock: 9, .skewb: 10,
            .threeByThreeFM: 11, .threeByThreeBLD: 12, .fourByFourBLD: 13,
            .fiveByFiveBLD: 14, .threeByThreeOH: 1, .threeByThreeMBLD: 12]
        XCTAssertEqual(Set(expected.keys).union([.fto]), Set(PuzzleEvent.allCases))
        for (event, index) in expected {
            XCTAssertEqual(TimerScrambleGenerator.tnoodleRegistry(for: event)?.rawValue, index, event.rawValue)
        }
        XCTAssertNil(TimerScrambleGenerator.tnoodleRegistry(for: .fto))
    }

    func testNativeBoundaryRequestsExactlyOneCorrectSlotAndPreservesNotation() {
        let fixtures: [TNoodlePuzzleRegistry: String] = [.two: "R U2 F'", .three: "R U F2",
            .four: "Rw U2 F'", .five: "3Rw F2 U", .six: "3Rw U2 F", .seven: "3Rw F U2",
            .sq1: "(1,0) / (3,-3) /", .mega: "R++ D-- U'\nR-- D++ U",
            .pyra: "R U' L B r u' l b'", .clock: "UR3+ DR1- DL2+ UL0+ ALL4- y2 U1+",
            .skewb: "R U' L B'", .threeNI: "R U' F2 x y'", .fourNI: "Rw U F2 x'",
            .fiveNI: "3Rw U2 F z"]
        for (registry, fixture) in fixtures {
            var calls: [Int] = []
            XCTAssertEqual(TNoodleScrambler.scramble(for: registry, using: { calls.append($0); return fixture }), fixture)
            XCTAssertEqual(calls, [registry.rawValue])
        }
    }

    func testPyraminxDoesNotRequireTipsButNeverStripsThem() {
        for value in ["R U L' B", "R U' r l' u b'", "R\nU'\tr u'\n"] {
            XCTAssertEqual(TNoodleScrambler.scramble(for: .pyra, using: { _ in value }), value)
        }
    }

    func testFailureDoesNotProbeOtherPuzzleOrSubstituteScramble() {
        for value in [nil, "", "  \n", "(1,0) / (0,3) /"] as [String?] {
            var calls: [Int] = []
            XCTAssertNil(TNoodleScrambler.scramble(for: .threeNI, using: { calls.append($0); return value }))
            XCTAssertEqual(calls, [12])
        }
        var calls: [Int] = []
        XCTAssertNil(TNoodleScrambler.scramble(for: .threeFM, using: { calls.append($0); return nil }))
        XCTAssertEqual(calls, [1], "FMC samples the real native 3x3, not the mislabeled slot 11")
    }

    func testMultiBlindContextNormalizesOnlyItsOwnCount() {
        for event in PuzzleEvent.allCases {
            let context = TimerScrambleGenerationContext(sessionID: UUID(), event: event,
                multiBlindCount: 7, unavailableMessage: "Unavailable")
            XCTAssertEqual(context.multiBlindCount, event == .threeByThreeMBLD ? 7 : 1)
        }
    }

    func testMultiBlindUsesNoInspectionRandomOrientationButOneHandedDoesNot() {
        XCTAssertEqual(TimerScrambleGenerator.tnoodleRegistry(for: .threeByThreeMBLD), .threeNI)
        XCTAssertEqual(TimerScrambleGenerator.tnoodleRegistry(for: .threeByThreeOH), .three)
        let oriented = "R U F2 Rw Uw'"
        XCTAssertEqual(TNoodleScrambler.scramble(for: .threeNI, using: { index in
            XCTAssertEqual(index, 12); return oriented
        }), oriented)
    }
}
#endif
