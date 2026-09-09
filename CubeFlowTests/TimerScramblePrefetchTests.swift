#if os(iOS)
import Foundation
import Testing
@testable import CubeFlow

struct TimerScramblePrefetchTests {
    private func context(
        sessionID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        event: PuzzleEvent = .threeByThree,
        multiBlindCount: Int = 1
    ) -> TimerScrambleGenerationContext {
        TimerScrambleGenerationContext(
            sessionID: sessionID,
            event: event,
            multiBlindCount: multiBlindCount,
            unavailableMessage: "Unavailable"
        )
    }

    private func payload(
        _ scramble: String,
        context: TimerScrambleGenerationContext
    ) -> TimerScrambleGenerationPayload {
        TimerScrambleGenerationPayload(context: context, scrambles: [scramble])
    }

    @Test func readyPrefetchConsumesExactlyOnce() throws {
        let context = context()
        let generated = payload("R U R'", context: context)
        var slot = TimerScramblePrefetchSlot()
        let request = slot.begin(for: context)

        let completed = slot.complete(generated, for: request)
        let consumed = slot.consume(for: context)
        let consumedAgain = slot.consume(for: context)
        #expect(completed)
        #expect(try #require(consumed).primaryScramble == "R U R'")
        #expect(consumedAgain == nil)
    }

    @Test func prefetchedNextIsDistinctFromCurrentAndRefillsRepeatedly() throws {
        let context = context()
        var slot = TimerScramblePrefetchSlot()

        let firstRequest = slot.begin(for: context)
        let firstCompleted = slot.complete(payload("R U", context: context), for: firstRequest)
        #expect(firstCompleted)
        let firstConsumed = slot.consume(for: context)
        let first = try #require(firstConsumed)

        let secondRequest = slot.begin(for: context)
        let secondCompleted = slot.complete(payload("F D", context: context), for: secondRequest)
        #expect(secondCompleted)
        let secondConsumed = slot.consume(for: context)
        let second = try #require(secondConsumed)

        #expect(first.primaryScramble != second.primaryScramble)
        #expect(slot.payload == nil)
        #expect(slot.request == nil)
    }

    @Test func incompatibleSessionEventOrConfigurationCannotConsume() {
        let source = context(event: .threeByThree)
        var slot = TimerScramblePrefetchSlot()
        let request = slot.begin(for: source)
        let sourceCompleted = slot.complete(payload("R U", context: source), for: request)
        #expect(sourceCompleted)

        let wrongSession = slot.consume(for: context(sessionID: UUID(), event: .threeByThree))
        let wrongEvent = slot.consume(for: context(event: .fourByFour))
        #expect(wrongSession == nil)
        #expect(wrongEvent == nil)

        let multi = context(event: .threeByThreeMBLD, multiBlindCount: 3)
        let multiRequest = slot.begin(for: multi)
        let multiPayload = TimerScrambleGenerationPayload(
            context: multi,
            scrambles: ["A", "B", "C"]
        )
        let multiCompleted = slot.complete(multiPayload, for: multiRequest)
        let wrongCount = slot.consume(for: context(event: .threeByThreeMBLD, multiBlindCount: 4))
        #expect(multiCompleted)
        #expect(wrongCount == nil)
    }

    @Test func staleAsyncCompletionCannotReplaceNewerRequest() {
        let oldContext = context(event: .threeByThree)
        let newContext = context(event: .square1)
        var slot = TimerScramblePrefetchSlot()
        let oldRequest = slot.begin(for: oldContext)
        let newRequest = slot.begin(for: newContext)

        let staleCompleted = slot.complete(payload("R U", context: oldContext), for: oldRequest)
        #expect(slot.hasPendingRequest(for: newContext))
        let currentCompleted = slot.complete(payload("(1,0) /", context: newContext), for: newRequest)
        let consumed = slot.consume(for: newContext)
        #expect(!staleCompleted)
        #expect(currentCompleted)
        #expect(consumed?.primaryScramble == "(1,0) /")
    }

    @Test func earlyNextWaitsForExistingRequestThenConsumesIt() {
        let context = context()
        var slot = TimerScramblePrefetchSlot()
        let request = slot.begin(for: context)

        #expect(slot.hasPendingRequest(for: context))
        let beforeCompletion = slot.consume(for: context)
        let completed = slot.complete(payload("R2 F2", context: context), for: request)
        let consumed = slot.consume(for: context)
        #expect(beforeCompletion == nil)
        #expect(completed)
        #expect(consumed?.primaryScramble == "R2 F2")
    }

    @Test func prefetchCompletionDoesNotActivateUntilExplicitConsumption() {
        let context = context()
        var slot = TimerScramblePrefetchSlot()
        var activatedScramble: String?
        let request = slot.begin(for: context)

        let completed = slot.complete(payload("U F", context: context), for: request)
        #expect(completed)
        #expect(activatedScramble == nil)

        activatedScramble = slot.consume(for: context)?.primaryScramble
        #expect(activatedScramble == "U F")
    }
}
#endif
