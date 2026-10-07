import Foundation
import CoreData
import Testing
@testable import CubeFlow

@Suite("Timer polish")
struct TimerPolishTests {
    @Test func inspectionBoundariesAndSavedResultPrecedence() {
        for (elapsed, penalty) in [(14.999, nil), (15.0, SolveResult.plusTwo), (16.999, .plusTwo), (17.0, .dnf), (30.0, .dnf)] {
            #expect(InspectionPenaltyPolicy.penalty(for: elapsed) == penalty)
        }
        #expect(InspectionPenaltyPolicy.result(.solved, inspectionPenalty: .plusTwo) == .plusTwo)
        #expect(InspectionPenaltyPolicy.result(.dnf, inspectionPenalty: .plusTwo) == .dnf)
        #expect(InspectionPenaltyPolicy.result(.solved, inspectionPenalty: .dnf) == .dnf)
        #expect(sample(10, penalty: .plusTwo).adjustedTime == 12)
        #expect(sample(10, penalty: .dnf).adjustedTime == nil)
    }

    @Test func onlyLiveMatchingConnectionAttemptCanExpire() {
        let attempt = UUID()
        #expect(SmartCubeConnectionAttemptPolicy.shouldExpire(expected: attempt, current: attempt, state: .connecting))
        for state: SmartCubeConnectionState in [.disconnected, .connected, .failed("failure"), .bluetoothUnavailable] {
            #expect(!SmartCubeConnectionAttemptPolicy.shouldExpire(expected: attempt, current: attempt, state: state))
        }
        #expect(!SmartCubeConnectionAttemptPolicy.shouldExpire(expected: attempt, current: nil, state: .connecting))
        #expect(!SmartCubeConnectionAttemptPolicy.shouldExpire(expected: attempt, current: UUID(), state: .connecting))
    }

    @Test func rollingRecordsUseActualPenaltiesAndDoNotColorHistoricalOrTiedPBs() {
        let old = (0..<12).map { sample(20, age: $0 + 1) }
        let new = sample(10)
        let state = TimerPersonalBestState.current(from: [new] + old)
        #expect(state.solveID == new.id)
        #expect(state.metrics == ["best", "mo3"])
        // Trimmed averages discard the new best single, so they tie the old windows.
        #expect(!state.metrics.contains("ao5"))
        let worse = sample(25)
        #expect(TimerPersonalBestState.current(from: [worse] + old).metrics.isEmpty)
        #expect(TimerPersonalBestState.current(from: [sample(20)] + old).metrics.isEmpty)
        #expect(TimerPersonalBestState.current(from: [sample(19, penalty: .plusTwo)] + old).metrics.isEmpty)
        #expect(TimerPersonalBestState.current(from: [sample(1, penalty: .dnf)] + old).metrics.isEmpty)
    }

    @Test @MainActor func inspectionPenaltiesSurvivePersistenceForBothInputSources() throws {
        let storage = PersistenceController(inMemory: true)
        let context = storage.container.viewContext
        let session = Session(name: "Inspection", context: context)
        let sessionID = session.id
        for input: SolveInputSource in [.appTimer, .smartCube] {
            for elapsed in [15.0, 17.0] {
                _ = Solve(time: 10, scramble: "R U", event: "3x3",
                          result: InspectionPenaltyPolicy.result(.solved, inspectionPenalty: InspectionPenaltyPolicy.penalty(for: elapsed)),
                          inputSource: input, session: session, context: context)
            }
        }
        try context.save()
        context.reset()
        let restored = try context.fetchSolves(forSessionID: sessionID)
        #expect(restored.count == 4)
        #expect(restored.filter { $0.result == .plusTwo }.count == 2)
        #expect(restored.filter { $0.result == .dnf }.count == 2)
    }

    @Test func allSupportedRollingMetricsCanBeCurrentPBs() {
        let improving = (0..<101).map { sample(Double(10 + $0), age: $0) }
        let state = TimerPersonalBestState.current(from: improving)
        #expect(state.metrics == ["best", "mo3", "ao5", "ao12", "ao50", "ao100"])
        #expect(!state.metrics.contains("mean") && !state.metrics.contains("solveCount"))
    }

    @Test func multipleRecordsCelebrateOnlyOnceForTheSavedSolve() {
        let new = sample(10)
        let state = TimerPersonalBestState.current(from: [new] + (1..<13).map { sample(Double(20 + $0), age: $0) })
        var gate = TimerPBCelebrationGate()
        let first = gate.accept(completedSolveID: new.id, state: state)
        let repeated = gate.accept(completedSolveID: new.id, state: state)
        let unrelated = gate.accept(completedSolveID: UUID(), state: state)
        #expect(state.metrics.count > 1 && first && !repeated && !unrelated)
        let noRecord = gate.accept(completedSolveID: UUID(), state: .empty)
        #expect(!noRecord)
    }

    private func sample(_ time: Double, age: Int = 0, penalty: SolveResult = .solved) -> SessionSolveSample {
        SessionSolveSample(id: UUID(), date: Date(timeIntervalSince1970: Double(1000 - age)), time: time,
                           resultRaw: penalty.rawValue, scramble: "R U", comment: "", eventRawValue: "333")
    }
}
