#if os(iOS)
import XCTest
@testable import CubeFlow

@MainActor final class TimerLaunchReservationTests: XCTestCase {
    private func context(_ event: PuzzleEvent = .threeByThree, session: UUID = UUID()) -> TimerScrambleGenerationContext {
        .init(sessionID: session, event: event, multiBlindCount: 1, unavailableMessage: "Unavailable")
    }
    func testVisibleDemandJoinsSinglePreparationAndNextDoesNotReuseIt() {
        let slot = TimerLaunchScrambleReservation(), request = context()
        var pending: (@MainActor (TimerScrambleGenerationPayload) -> Void)?, calls = 0
        slot.prepare(request) { _, complete in calls += 1; pending = complete }
        slot.prepare(request) { _, _ in XCTFail("Duplicate preparation") }
        var received: [String] = []
        XCTAssertTrue(slot.consume(for: request) { received.append($0.primaryScramble) })
        XCTAssertTrue(received.isEmpty)
        pending?(.init(context: request, scrambles: ["R U"]))
        XCTAssertEqual(received, ["R U"]); XCTAssertEqual(calls, 1)
        XCTAssertFalse(slot.consume(for: request) { _ in XCTFail("Must not reuse a scramble") })
    }
    func testCompletedReservationIsAvailableWithoutAnotherGeneration() {
        let slot = TimerLaunchScrambleReservation(), request = context()
        slot.prepare(request) { context, complete in complete(.init(context: context, scrambles: ["F R"])) }
        var value: String?
        XCTAssertTrue(slot.consume(for: request) { value = $0.primaryScramble })
        XCTAssertEqual(value, "F R")
    }
    func testSessionEventAndLocalizationMismatchRejectLateWork() {
        let request = context()
        for different in [context(.pyraminx, session: request.sessionID!), context(),
                          TimerScrambleGenerationContext(sessionID: request.sessionID, event: request.event, multiBlindCount: 1, unavailableMessage: "Other language")] {
            let slot = TimerLaunchScrambleReservation()
            var pending: (@MainActor (TimerScrambleGenerationPayload) -> Void)?
            slot.prepare(request) { _, complete in pending = complete }
            XCTAssertFalse(slot.consume(for: different) { _ in XCTFail("Mismatched reservation") })
            pending?(.init(context: request, scrambles: ["R U"]))
            XCTAssertFalse(slot.consume(for: request) { _ in XCTFail("Late work must not resurrect reservation") })
        }
    }
    func testIncorrectGeneratorContextCannotSatisfyConsumer() {
        let slot = TimerLaunchScrambleReservation(), request = context()
        var pending: (@MainActor (TimerScrambleGenerationPayload) -> Void)?
        slot.prepare(request) { _, complete in pending = complete }
        XCTAssertTrue(slot.consume(for: request) { _ in XCTFail("Wrong context") })
        pending?(.init(context: context(.pyraminx), scrambles: ["R U"]))
    }
}
#endif
