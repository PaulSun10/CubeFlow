#if os(iOS)
import Foundation
import Testing
@testable import CubeFlow

@MainActor
struct GANHistoryRecoveryTests {
    private func live(_ serial: Int, _ kind: SmartCubeProtocolKind) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 20)
        let offset = kind == .ganGen3 ? 1 : 0
        if offset == 1 { bytes[0] = 0x55 }
        bytes[offset] = 1
        bytes[6 + offset] = UInt8(serial & 255)
        bytes[7 + offset] = UInt8((serial >> 8) & 255)
        bytes[8 + offset] = 2 // U clockwise
        return bytes
    }

    private func history(_ start: Int, valid: [Bool], _ kind: SmartCubeProtocolKind) -> [UInt8] {
        precondition(valid.count.isMultiple(of: 2))
        var bytes = [UInt8](repeating: 0, count: 20)
        let offset = kind == .ganGen3 ? 1 : 0
        if offset == 1 { bytes[0] = 0x55 }
        bytes[offset] = offset == 1 ? 6 : 0xD1
        bytes[offset + 1] = UInt8(1 + valid.count / 2)
        bytes[offset + 2] = UInt8(start & 255)
        for index in valid.indices {
            let nibble: UInt8 = valid[index] ? 2 : 15 // U, or invalid axis
            bytes[offset + 3 + index / 2] |= nibble << (index.isMultiple(of: 2) ? 4 : 0)
        }
        return bytes
    }

    private func state(_ serial: Int, _ kind: SmartCubeProtocolKind) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 20)
        let offset = kind == .ganGen3 ? 1 : 0
        if offset == 1 { bytes[0] = 0x55 }
        bytes[offset] = offset == 1 ? 2 : 0xED
        bytes[offset + 2] = UInt8(serial & 255)
        return bytes
    }

    private func serials(_ events: [SmartCubeParsedEvent]) -> [Int] {
        events.compactMap { if case .move(let move) = $0 { move.serial.map { $0 & 255 } } else { nil } }
    }

    private func requests(_ events: [SmartCubeParsedEvent]) -> Int {
        events.filter { if case .requestMoveHistory = $0 { true } else { false } }.count
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func stateOnlyGapContinuesAfterPartialResponse(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(1, kind))
        #expect(requests(parser.handleStateEvent(state(7, kind))) == 1)
        let partial = parser.handleStateEvent(history(3, valid: [true, true], kind))
        #expect(serials(partial) == [2, 3])
        #expect(requests(partial) == 1)
        #expect(serials(parser.handleStateEvent(history(7, valid: [true, true, true, true], kind))) == [4, 5, 6, 7])
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func oldStateCounterCannotShrinkLiveRecoveryRange(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(1, kind))
        _ = parser.handleStateEvent(live(7, kind))
        _ = parser.handleStateEvent(state(3, kind))
        let response = parser.handleStateEvent(history(7, valid: Array(repeating: true, count: 6), kind))
        #expect(serials(response) == [2, 3, 4, 5, 6, 7])
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func backfillDrainsFutureLiveMovesAndDeduplicates(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        #expect(serials(parser.handleStateEvent(live(1, kind))) == [1])
        #expect(requests(parser.handleStateEvent(live(4, kind))) == 1)
        #expect(serials(parser.handleStateEvent(live(5, kind))).isEmpty)
        let result = parser.handleStateEvent(history(3, valid: [true, true], kind))
        #expect(serials(result) == [2, 3, 4, 5])
        let sources = result.compactMap { event -> SmartCubeMoveTimestampSource? in
            if case .move(let move) = event { return move.timestampSource }
            return nil
        }
        #expect(sources == [.reconstructed, .reconstructed, .deviceClock, .deviceClock])
        #expect(!result.contains { if case .continuityLost = $0 { true } else { false } })
        #expect(serials(parser.handleStateEvent(history(3, valid: [true, true], kind))).isEmpty)
        #expect(serials(parser.handleStateEvent(live(4, kind))).isEmpty)
        #expect(requests(parser.retryPendingGANHistory()) == 0)
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func partialResponseImmediatelyRequestsNextGap(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(1, kind))
        _ = parser.handleStateEvent(live(5, kind))
        // Counter 4 is absent, but 3 and 2 must still be accepted, not thrown away.
        let partial = parser.handleStateEvent(history(5, valid: [true, false, true, true], kind))
        #expect(serials(partial) == [2, 3])
        #expect(requests(partial) == 1)
        #expect(!partial.contains { if case .holdPendingMove = $0 { true } else { false } })
        #expect(serials(parser.handleStateEvent(history(5, valid: [true, true], kind))) == [4, 5])
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func wraparoundRecoversBothSidesWithoutAnotherLivePacket(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(254, kind))
        #expect(requests(parser.handleStateEvent(live(258, kind))) == 1)
        let first = parser.handleStateEvent(history(1, valid: [true, true], kind))
        #expect(serials(first).isEmpty)
        #expect(requests(first) == 1)
        #expect(serials(parser.handleStateEvent(history(255, valid: [true, true], kind))) == [255, 0, 1, 2])
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func resetAndUnrequestedHistoryCannotBackfill(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(1, kind))
        _ = parser.handleStateEvent(live(3, kind))
        parser.resetMoveTracking()
        #expect(serials(parser.handleStateEvent(history(3, valid: [true, true], kind))).isEmpty)
        #expect(requests(parser.retryPendingGANHistory()) == 0)
        #expect(!parser.hasRetryableGANHistory)
        #expect(serials(parser.handleStateEvent(live(10, kind))) == [10])
        #expect(serials(parser.handleStateEvent(history(3, valid: [true, true], kind))).isEmpty)
        #expect(serials(parser.handleStateEvent(live(11, kind))) == [11])
    }

    @Test(arguments: [SmartCubeProtocolKind.ganGen3, .ganGen4])
    func rapidRepeatedGapsRecoverWithoutFixedWait(kind: SmartCubeProtocolKind) {
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(1, kind))
        for serial in stride(from: 3, through: 61, by: 2) {
            #expect(requests(parser.handleStateEvent(live(serial, kind))) == 1)
            #expect(serials(parser.handleStateEvent(history(serial, valid: [true, true], kind))) == [serial - 1, serial])
        }
    }

    @Test func retriesAreThrottledAndBounded() async throws {
        let kind = SmartCubeProtocolKind.ganGen4
        let parser = GANCubeProtocolParser(kind: kind)
        _ = parser.handleStateEvent(live(1, kind))
        #expect(requests(parser.handleStateEvent(live(3, kind))) == 1)
        #expect(requests(parser.retryPendingGANHistory()) == 0)
        #expect(parser.hasRetryableGANHistory)
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(240))
            #expect(requests(parser.retryPendingGANHistory()) == 1)
        }
        try await Task.sleep(for: .milliseconds(240))
        #expect(requests(parser.retryPendingGANHistory()) == 0)
        #expect(!parser.hasRetryableGANHistory)
        // Exhaustion cannot discard the path; a late valid response still repairs it.
        #expect(serials(parser.handleStateEvent(history(3, valid: [true, true], kind))) == [2, 3])
    }
}
#endif
