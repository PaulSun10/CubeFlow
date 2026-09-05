import Foundation
import Combine
import Testing
@testable import CubeFlow

@MainActor
struct SmartCubeHardeningTests {
    private func move(_ text: String = "R", index: Int = 0) -> SmartCubeMoveEvent {
        SmartCubeMoveEvent(move: text, serial: index, face: nil, direction: nil,
                           localTimestamp: Date(timeIntervalSince1970: 100 + Double(index)),
                           cubeTimestampMilliseconds: index * 1000, timestampSource: .deviceClock)
    }

    @Test(arguments: [SmartCubeContinuityReason.reset, .resync, .disconnected, .historyGap])
    func boundaryIsNotASolveCompletion(reason: SmartCubeContinuityReason) throws {
        let feed = SmartCubeCanonicalFeed()
        var epoch = SmartCubeScrambleEpoch()
        epoch.establish(at: .distantPast, latestMoveID: nil)
        feed.send(move: move(), facelets: try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R")))
        _ = epoch.consumeEvent(try #require(feed.eventHistory.last))
        let oldIdentity = epoch.currentRecoveryIdentity
        feed.breakContinuity(reason, facelets: SmartCubeBluetoothManager.solvedFacelets)
        let event = try #require(feed.eventHistory.last)
        #expect(event.solveCompletingMove == nil)
        guard case .boundary(let actualReason, _) = epoch.consumeEvent(event) else {
            Issue.record("Boundary was consumed as a physical move")
            return
        }
        #expect(actualReason == reason)
        #expect(epoch.currentRecoveryIdentity != oldIdentity)
        #expect(!epoch.hasAcceptedPhysicalMove)
        var lifecycle = SmartCubeSolveLifecycle()
        let action = epoch.completionAction(inspectionEnabled: false, completingMoveID: nil, lifecycle: &lifecycle)
        #expect(action == .none)
    }

    @Test func unknownGapCannotFinishFromPredictedSolvedState() throws {
        let feed = SmartCubeCanonicalFeed()
        var epoch = SmartCubeScrambleEpoch()
        epoch.establish(at: .distantPast, latestMoveID: nil)
        feed.breakContinuity(.historyGap, facelets: nil)
        _ = epoch.consumeEvent(try #require(feed.eventHistory.last))
        feed.send(move: move("R'"), facelets: SmartCubeBluetoothManager.solvedFacelets)
        let predicted = try #require(feed.eventHistory.last)
        #expect(predicted.solveCompletingMove == nil)
        guard case .boundary(.historyGap, nil) = epoch.consumeEvent(predicted) else {
            Issue.record("Untrusted predicted state was treated as continuous")
            return
        }
        feed.breakContinuity(.resync, facelets: SmartCubeBluetoothManager.solvedFacelets)
        _ = epoch.consumeEvent(try #require(feed.eventHistory.last))
        feed.send(move: move("R", index: 1), facelets: try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R")))
        guard case .move = epoch.consumeEvent(try #require(feed.eventHistory.last)) else {
            Issue.record("Trusted resync did not establish a fresh continuous segment")
            return
        }
    }

    @Test func truncatedReplayDoesNotPretendToBeContinuous() throws {
        let feed = SmartCubeCanonicalFeed()
        var epoch = SmartCubeScrambleEpoch()
        epoch.establish(at: .distantPast, latestMoveID: nil)
        for index in 0..<130 { feed.send(move: move(index: index), facelets: SmartCubeBluetoothManager.solvedFacelets) }
        #expect(feed.eventHistory.count == 120)
        let first = try #require(feed.eventHistory.first)
        guard case .boundary(.truncatedHistory, _) = epoch.consumeEvent(first) else {
            Issue.record("Missing prefix was not detected")
            return
        }
        #expect(!epoch.hasAcceptedPhysicalMove)
        guard case .ignored = epoch.consumeEvent(first) else {
            Issue.record("Replay duplicate was not ignored")
            return
        }
    }

    @Test func resyncDropsOldTrailButRetainsKnownCheckpoints() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "U2 F2"))
        let wrong = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R U"))
        let first = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R"))
        _ = progress.update(with: first, canonicalMove: "R")
        _ = progress.update(with: wrong, canonicalMove: "U")
        #expect(progress.deviationMoves.count == 2)
        progress.breakContinuity(at: wrong)
        #expect(progress.deviationMoves.isEmpty)
        let identity = SmartCubeRecoveryPlanIdentity(scrambleEpochID: UUID(), stateVersion: 1)
        #expect(progress.guaranteedRecoveryPlan(identity: identity, sourceFacelets: wrong) == nil)
        progress.breakContinuity(at: SmartCubeBluetoothManager.solvedFacelets)
        #expect(!progress.isDeviated)
        _ = progress.update(with: first, canonicalMove: "R")
        #expect(progress.guaranteedRecoveryPlan(identity: identity, sourceFacelets: first)?.correctionMoves == ["R'"])
    }

    @Test(arguments: [7, 10, 100])
    func orderedEventConsumerRetainsFullRecovery(count: Int) throws {
        let feed = SmartCubeCanonicalFeed()
        var epoch = SmartCubeScrambleEpoch()
        epoch.establish(at: .distantPast, latestMoveID: nil)
        var progress = try #require(SmartCubeScrambleProgress(scramble: "U2 F2"))
        var consumed = 0
        var breaks = 0
        let subscription = feed.events.sink { event in
            switch epoch.consumeEvent(event) {
            case .move(let update):
                _ = progress.update(with: update.facelets, canonicalMove: update.move.move)
                consumed += 1
                if progress.isDeviated {
                    #expect(progress.guaranteedRecoveryPlan(
                        identity: epoch.advanceRecoveryStateVersion(), sourceFacelets: update.facelets
                    ) != nil)
                }
            case .boundary: breaks += 1
            case .ignored: break
            }
        }
        defer { subscription.cancel() }
        let turns = ["R", "U", "F", "L", "D", "B", "R'", "F2", "U'", "L2"]
        var facelets = SmartCubeBluetoothManager.solvedFacelets
        for index in 0..<count {
            facelets = try #require(SmartCubeBluetoothManager.facelets(facelets, applying: turns[index % turns.count]))
            feed.send(move: move(turns[index % turns.count], index: index), facelets: facelets)
        }
        #expect(consumed == count)
        #expect(breaks == 0)
        let plan = try #require(progress.guaranteedRecoveryPlan(identity: epoch.currentRecoveryIdentity, sourceFacelets: facelets))
        var restored = facelets
        for correction in plan.correctionMoves {
            restored = try #require(SmartCubeBluetoothManager.facelets(restored, applying: correction))
        }
        #expect(restored == plan.checkpoint.facelets)
        if count == 100 { #expect(plan.totalCost > 50) }
    }

    @Test func frameLengthsAndRemovedFocusPreferenceAreSafe() {
        for value: CGFloat in [-100, 0, 5, .infinity, -.infinity, .nan] {
            let width = SmartCubeLayoutDimensions.statusWidth(containerWidth: value, inset: 20, cubeSize: 100)
            #expect(width.isFinite && width >= 0)
        }
        #expect(SmartCubeLayoutDimensions.statusWidth(containerWidth: 390, inset: 20, cubeSize: 160) == 240)
        #expect(SmartCubeRecoveryDisplay.resolved("focus") == .inline)
        #expect(SmartCubeRecoveryDisplay.resolved("invalid") == .separate)
        #expect(SmartCubeRecoveryDisplay.allCases == [.separate, .inline])
    }

    @Test(arguments: [5, 6, 7, 8])
    func packetHistoryCapacityOnlyBreaksWhenMovesAreMissing(count: Int) {
        func setBits(_ bytes: inout [UInt8], start: Int, length: Int, value: Int) {
            for index in 0..<length {
                let offset = start + index
                let bit = (value >> (length - 1 - index)) & 1
                bytes[offset / 8] |= UInt8(bit << (7 - offset % 8))
            }
        }
        func hasBreak(_ events: [SmartCubeParsedEvent]) -> Bool {
            events.contains { if case .continuityLost = $0 { true } else { false } }
        }
        func moves(_ events: [SmartCubeParsedEvent]) -> Int {
            events.filter { if case .move = $0 { true } else { false } }.count
        }
        let gan = GANCubeProtocolParser(kind: .ganGen2)
        gan.resetMoveTracking()
        var ganPacket = [UInt8](repeating: 0, count: 20)
        setBits(&ganPacket, start: 0, length: 4, value: 2)
        setBits(&ganPacket, start: 4, length: 8, value: count)
        let ganEvents = gan.handleStateEvent(ganPacket)
        #expect(hasBreak(ganEvents) == (count > 7))
        #expect(moves(ganEvents) == min(count, 7))

        let moyu = GANCubeProtocolParser(kind: .moyu)
        var moyuPacket = [UInt8](repeating: 0, count: 20)
        moyuPacket[0] = 0xA5
        _ = moyu.handleStateEvent(moyuPacket)
        setBits(&moyuPacket, start: 88, length: 8, value: count)
        let moyuEvents = moyu.handleStateEvent(moyuPacket)
        #expect(hasBreak(moyuEvents) == (count > 5))
        #expect(moves(moyuEvents) == min(count, 5))
    }

    @Test func ganWaitingIsNotBrokenUntilBufferedHistoryIsLost() {
        func packet(_ serial: Int) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 20)
            bytes[0] = 0x55
            bytes[1] = 0x01
            bytes[7] = UInt8(serial)
            bytes[9] = 2 // Valid U face mask, clockwise direction.
            return bytes
        }
        let parser = GANCubeProtocolParser(kind: .ganGen3)
        _ = parser.handleStateEvent(packet(1))
        let waiting = parser.handleStateEvent(packet(3))
        #expect(waiting.contains { if case .requestMoveHistory = $0 { true } else { false } })
        #expect(!waiting.contains { if case .continuityLost = $0 { true } else { false } })
        var lost = false
        for serial in 4...20 {
            let events = parser.handleStateEvent(packet(serial))
            lost = lost || events.contains { if case .continuityLost = $0 { true } else { false } }
        }
        #expect(lost)
        parser.resetMoveTracking()
        let fresh = parser.handleStateEvent(packet(1))
        #expect(!fresh.contains { if case .continuityLost = $0 { true } else { false } })
    }

    #if DEBUG
    @Test func diagnosticsSeparateRecognitionLatencyFromStoredTime() {
        let first = move(index: 0)
        let last = move("R'", index: 10)
        let summary = SmartCubeTimingDiagnosticSummary(
            start: first, end: last, recognizedAt: Date(timeIntervalSince1970: 112), storedSeconds: 10
        )
        #expect(summary.deviceInterval == 10)
        #expect(summary.storedMinusMove == 0)
        #expect(summary.recognitionLatency == 2)
        #expect(summary.selectedSource == "deviceClock")
        let estimated = SmartCubeMoveEvent(move: "R'", serial: nil, face: nil, direction: nil,
            localTimestamp: last.localTimestamp, cubeTimestampMilliseconds: nil, timestampSource: .reconstructed)
        let fallback = SmartCubeTimingDiagnosticSummary(start: first, end: estimated,
            recognizedAt: Date(timeIntervalSince1970: 112), storedSeconds: 10)
        #expect(fallback.deviceInterval == nil)
        #expect(fallback.selectedSource == "canonicalLocalTimestamp")
        #expect(fallback.storedMinusMove == 0)
    }
    #endif
}
