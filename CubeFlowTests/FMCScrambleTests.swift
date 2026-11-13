#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import CoreData
@testable import CubeFlow

@MainActor final class FMCScrambleTests: XCTestCase {
    private let fixture = "R U2 F' L2 D B2 R2 U' F2 D2 L' B U2 R' D F L2 U B'"
    private func assertFMC(_ scramble: String, target: String, file: StaticString = #filePath, line: UInt = #line) {
        let tokens = scramble.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(tokens.prefix(3)), ["R'", "U'", "F"], file: file, line: line)
        XCTAssertEqual(Array(tokens.suffix(3)), ["R'", "U'", "F"], file: file, line: line)
        XCTAssertLessThanOrEqual(tokens.count, 27, file: file, line: line)
        XCTAssertNotNil(SmartCubeBluetoothManager.facelets(afterApplying: scramble), file: file, line: line)
        XCTAssertNotNil(SmartCubeBluetoothManager.facelets(afterApplying: target), file: file, line: line)
        XCTAssertEqual(SmartCubeBluetoothManager.facelets(afterApplying: scramble),
                       SmartCubeBluetoothManager.facelets(afterApplying: target), "The complete padded output must preserve the native sampled target", file: file, line: line)
        let middle = Array(tokens.dropFirst(3).dropLast(3))
        if let first = middle.first?.first { XCTAssertFalse("FB".contains(first), file: file, line: line) }
        if let last = middle.last?.first { XCTAssertFalse("RL".contains(last), file: file, line: line) }
        var axis: Int?, powers: [Character: Int] = [:], count = 0
        func flush() {
            XCTAssertEqual(powers.values.filter { $0 % 4 != 0 }.count, count,
                "No reducible same-axis run in the complete FMC sequence", file: file, line: line)
            powers = [:]; count = 0
        }
        for token in tokens {
            let face = token.first!, current = "UD".contains(face) ? 0 : "RL".contains(face) ? 1 : 2
            if axis != current { flush(); axis = current }
            powers[face, default: 0] += token.hasSuffix("2") ? 2 : token.hasSuffix("'") ? 3 : 1
            count += 1
        }
        flush()
    }

    func testFMCUsesExactlyOneNativeThreeStateAndPreservesItUnderPadding() throws {
        var calls: [Int] = []
        let scramble = try XCTUnwrap(TNoodleScrambler.scramble(for: .threeFM, using: { calls.append($0); return fixture }))
        XCTAssertEqual(calls, [1])
        assertFMC(scramble, target: fixture)
        XCTAssertNotEqual(scramble, "R' U' F \(fixture) R' U' F", "A mechanical wrap changes the sampled target")
        XCTAssertEqual(TNoodleScrambler.scramble(for: .three, using: { _ in fixture }), fixture)
    }

    func testDeterministicSameStateReexpressionAcrossVariedNativeTargets() throws {
        for core in [fixture, "F U2 R2 D' L B2 U F' R D2 L' U2 B R' F2",
            "R2 F B' R B2 R U2 L B2 R U' D' R2 F R' L B2 U2 F2",
            "L' U F2 R2 B D' U2 F' R B2 L2 D2 U' F R2 L D B'"] {
            assertFMC(try XCTUnwrap(Min2PhaseBridge.fmcScramble(from: core)), target: core)
        }
    }

    func testInvalidAndNearSolvedInputsFailWithoutSubstitute() {
        for text in ["", " ", "(1,0) /", "R x", "Rw U", "R R'", "R", "U2", "R3"] {
            XCTAssertNil(Min2PhaseBridge.fmcScramble(from: text), text)
        }
        var calls: [Int] = []
        XCTAssertNil(TNoodleScrambler.scramble(for: .threeFM, using: { calls.append($0); return "(1,0) /" }))
        XCTAssertEqual(calls, [1])
    }

    func testConstrainedSearchHandlesEmptyAndSingleMoveMiddleStates() throws {
        for face in ["", "U", "R", "F", "D", "L", "B"] {
            let target = "R' U' F \(face) R' U' F"
            assertFMC(try XCTUnwrap(Min2PhaseBridge.fmcScramble(from: target)), target: target)
        }
    }

    func testFMCAndThreePrefetchOwnershipAndStaleCompletionAreSeparate() throws {
        let session = UUID()
        let fmc = TimerScrambleGenerationContext(sessionID: session, event: .threeByThreeFM, multiBlindCount: 1, unavailableMessage: "Unavailable")
        let three = TimerScrambleGenerationContext(sessionID: session, event: .threeByThree, multiBlindCount: 1, unavailableMessage: "Unavailable")
        var slot = TimerScramblePrefetchSlot()
        let old = slot.begin(for: fmc), new = slot.begin(for: three)
        XCTAssertFalse(slot.complete(.init(context: fmc, scrambles: [fixture]), for: old))
        XCTAssertTrue(slot.complete(.init(context: three, scrambles: [fixture]), for: new))
        XCTAssertNil(slot.consume(for: fmc)); XCTAssertEqual(slot.consume(for: three)?.primaryScramble, fixture)
    }

    func testMountedFMCEventSwitchAndSavedAssignment() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "FMC fixture", selectedEventRawValue: PuzzleEvent.threeByThreeFM.rawValue, context: context)
        try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "timer", "timerArrangement": "classic",
            "smartCubeReadySound": false, "wcaInspectionEnabled": false, "appLanguage": "en"]
        let previous = settings.map { ($0.key, defaults.object(forKey: $0.key)) }
        settings.forEach { defaults.set($0.value, forKey: $0.key) }
        defer { previous.forEach { defaults.set($0.1, forKey: $0.0) } }
        let probe = SmartCubeTimerGuidanceProbe()
        var pending: [(TimerScrambleGenerationContext, @MainActor (TimerScrambleGenerationPayload) -> Void)] = []
        probe.generate = { context, _, complete in pending.append((context, complete)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView().environment(\.managedObjectContext, context)
            .environment(\.smartCubeTimerGuidanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { probe.reset(); window.isHidden = true; window.rootViewController = nil }
        try await wait { pending.contains { $0.0.event == .threeByThreeFM } && probe.selectEvent != nil }
        let obsolete = try XCTUnwrap(pending.last { $0.0.event == .threeByThreeFM })
        pending.removeAll()
        probe.selectEvent?(.threeByThree)
        try await wait { pending.contains { $0.0.event == .threeByThree } }
        let obsoleteThree = try XCTUnwrap(pending.last)
        pending.removeAll()
        probe.selectEvent?(.threeByThreeFM)
        try await wait { pending.filter { $0.0.event == .threeByThreeFM }.count >= 1 }
        let current = try XCTUnwrap(pending.last { $0.0.event == .threeByThreeFM })
        obsolete.1(.init(context: obsolete.0, scrambles: ["F U"]))
        obsoleteThree.1(.init(context: obsoleteThree.0, scrambles: ["B D"]))
        let scramble = try XCTUnwrap(Min2PhaseBridge.fmcScramble(from: fixture))
        current.1(.init(context: current.0, scrambles: [scramble]))
        try await wait { probe.snapshot?().scramble == scramble }
        probe.start?(); XCTAssertEqual(probe.snapshot?().assignment?.event, .threeByThreeFM)
        probe.next?(); probe.finish?(12)
        try await wait { session.solveList.count == 1 }
        let saved = try XCTUnwrap(session.solveList.first); context.refresh(saved, mergeChanges: false)
        XCTAssertEqual(saved.scramble, scramble); XCTAssertEqual(saved.event, PuzzleEvent.threeByThreeFM.rawValue)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("FMC mounted lifecycle timeout"); throw CancellationError()
    }
}
#endif
