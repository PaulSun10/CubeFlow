import CoreData
import Foundation
import Testing
@testable import CubeFlow

@MainActor
struct SolveReconstructionTests {
    @Test func reconstructionAndSourceSurvivePersistenceRoundTrip() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let session = Session(name: "Smart", context: context)
        let reconstruction = fixture(completeness: .complete)
        let solve = Solve(
            time: 8.42,
            scramble: "R U",
            event: "3x3",
            inputSource: .smartCubeAndBluetoothTimer,
            reconstruction: reconstruction,
            session: session,
            context: context
        )
        let solveID = solve.id
        try context.save()
        context.reset()

        let fetched = try #require(try context.fetchSolve(with: solveID))
        #expect(fetched.inputSource == .smartCubeAndBluetoothTimer)
        #expect(fetched.scramble == "R U")
        #expect(fetched.reconstruction == reconstruction)
        #expect(fetched.reconstruction?.moves.map(\.canonicalMove) == ["R", "U"])
        #expect(fetched.reconstruction?.moves.map(\.relativeTimestamp) == [0, 0.18])
    }

    @Test func legacySolveWithoutReconstructionLoadsNormally() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let session = Session(name: "Legacy", context: context)
        let solve = Solve(time: 10, event: "3x3", session: session, context: context)
        let solveID = solve.id
        try context.save()
        context.reset()

        let fetched = try #require(try context.fetchSolve(with: solveID))
        #expect(fetched.inputSource == nil)
        #expect(fetched.reconstructionData == nil)
        #expect(fetched.reconstruction == nil)
    }

    @Test func incompleteStateAndReasonSurvivePersistence() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let session = Session(name: "Interrupted", context: context)
        let solve = Solve(
            time: 12,
            event: "3x3",
            inputSource: .smartCubeAndBluetoothTimer,
            reconstruction: fixture(completeness: .incomplete, reason: "disconnected"),
            session: session,
            context: context
        )
        try context.save()

        #expect(solve.reconstruction?.completeness == .incomplete)
        #expect(solve.reconstruction?.continuityReason == "disconnected")
    }

    @Test func deterministicSeekingSupportsThreeByThreeAndTwoByTwo() throws {
        let three = fixture(completeness: .complete)
        let afterThreeR = try #require(CubeLayerTurn("R")?.applying(to: three.initialFacelets, size: 3))
        let expectedThree = try #require(CubeLayerTurn("U")?.applying(to: afterThreeR, size: 3))
        #expect(three.facelets(afterMoveCount: 2) == expectedThree)

        let two = SolveReconstruction(
            puzzleSize: 2,
            initialFacelets: CubeSurface.solved(size: 2),
            moves: [move("R", at: 0), move("U", at: 0.2)],
            completeness: .complete
        )
        let afterTwoR = try #require(CubeLayerTurn("R")?.applying(to: two.initialFacelets, size: 2))
        let expectedTwo = try #require(CubeLayerTurn("U")?.applying(to: afterTwoR, size: 2))
        #expect(two.facelets(afterMoveCount: 2) == expectedTwo)
        #expect(two.facelets(afterMoveCount: 0) == CubeSurface.solved(size: 2))
        #expect(two.isReplayable)
        #expect(three.isReplayable)
    }

    @Test func tpsUsesRawSolveDurationAndTrustedStoredMoveCount() {
        let reconstruction = SolveReconstruction(
            puzzleSize: 2,
            initialFacelets: CubeSurface.solved(size: 2),
            moves: (0..<74).map { move($0.isMultiple(of: 2) ? "R" : "R'", at: Double($0) * 0.1) },
            completeness: .complete
        )
        #expect(abs((reconstruction.turnsPerSecond(actualDuration: 9.58) ?? 0) - 74 / 9.58) < 0.000_1)
        #expect(reconstruction.turnsPerSecond(actualDuration: 0) == nil)
        #expect(reconstruction.turnsPerSecond(actualDuration: .nan) == nil)
        let incomplete = SolveReconstruction(
            puzzleSize: 2, initialFacelets: reconstruction.initialFacelets,
            moves: reconstruction.moves, completeness: .incomplete
        )
        #expect(incomplete.turnsPerSecond(actualDuration: 9.58) == nil)
    }

    @Test func invalidHistoricalTwoByTwoDataIsNotPresentedAsReplay() {
        let invalid = SolveReconstruction(
            puzzleSize: 2, initialFacelets: CubeSurface.solved(size: 3),
            moves: [move("R", at: 0.2)], completeness: .complete
        )
        #expect(!invalid.isReplayable)
        #expect(invalid.turnsPerSecond(actualDuration: 9) == nil)
    }

    @Test func canonicalSolvedDetectionIsSizeAwareWithoutClaimingHardwareSupport() {
        let moveEvent = SmartCubeMoveEvent(
            move: "R",
            serial: nil,
            face: nil,
            direction: nil,
            localTimestamp: .now,
            cubeTimestampMilliseconds: nil
        )
        let update = SmartCubeCanonicalUpdate(
            sequence: 1,
            move: moveEvent,
            facelets: CubeSurface.solved(size: 2),
            isStateTrusted: true
        )

        #expect(update.puzzleSize == 2)
        #expect(update.isSolved)
        #expect(SmartCubeCanonicalEvent.move(update).solveCompletingMove == moveEvent)
    }

    @Test func captureKeepsCanonicalOrderRelativeTimingAndTrust() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = canonicalUpdate(sequence: 40, move: "R", date: start, deviceMilliseconds: 120)
        let second = canonicalUpdate(sequence: 41, move: "U", date: start.addingTimeInterval(0.24), deviceMilliseconds: 360)
        var capture = SmartCubeReconstructionCapture()
        capture.start(initialFacelets: CubeSurface.solved(size: 3), with: first)
        capture.append(first)
        capture.append(second)
        capture.markIncomplete(.historyGap)

        let reconstruction = try #require(capture.reconstruction())
        #expect(reconstruction.moves.map(\.canonicalMove) == ["R", "U"])
        #expect(reconstruction.moves.map(\.canonicalSequence) == [40, 41])
        #expect(abs(reconstruction.moves[1].relativeTimestamp - 0.24) < 0.000_1)
        #expect(reconstruction.moves[1].deviceTimestampMilliseconds == 360)
        #expect(reconstruction.completeness == .incomplete)
        #expect(reconstruction.continuityReason == "historyGap")
    }

    @Test func combinedOrderingProducesExactlyOneResult() {
        var lifecycle = CombinedSolveLifecycle()
        let didStart = lifecycle.timerDidStart(readiness: fullyReadyCombinedDevices)
        let firstStop = lifecycle.timerDidStop(seconds: 7.5)
        let duplicateStop = lifecycle.timerDidStop(seconds: 7.5)
        let duplicateStart = lifecycle.timerDidStart(readiness: fullyReadyCombinedDevices)

        #expect(didStart)
        #expect(firstStop == .save(seconds: 7.5))
        #expect(duplicateStop == .none)
        #expect(!duplicateStart)
    }

    @Test func combinedRequiresBothDevicesBeforeTimerStart() {
        var lifecycle = CombinedSolveLifecycle()
        let rejectedStart = lifecycle.timerDidStart(readiness: combinedDevices(timerConnected: false))
        let rejectedStop = lifecycle.timerDidStop(seconds: 8.1)
        let acceptedStart = lifecycle.timerDidStart(readiness: fullyReadyCombinedDevices)

        #expect(!rejectedStart)
        #expect(rejectedStop == .none)
        #expect(acceptedStart)
    }

    @Test func timerDisconnectNeverFallsBackToSmartCubeTiming() {
        var lifecycle = CombinedSolveLifecycle()
        lifecycle.timerDidStart(readiness: fullyReadyCombinedDevices)
        let disconnect = lifecycle.timerDidDisconnect()
        let lateStop = lifecycle.timerDidStop(seconds: 5)

        #expect(disconnect == .timerInterrupted)
        #expect(lateStop == .none)
    }

    @Test func combinedTimingUsesPersistedHostRelativeAnchors() throws {
        let timerStart = Date(timeIntervalSince1970: 2_000)
        var capture = SmartCubeReconstructionCapture()
        capture.start(initialFacelets: CubeSurface.solved(size: 3), at: timerStart)
        capture.append(canonicalUpdate(
            sequence: 1,
            move: "R",
            date: timerStart.addingTimeInterval(0.183),
            deviceMilliseconds: 500
        ))
        capture.append(canonicalUpdate(
            sequence: 2,
            move: "R'",
            date: timerStart.addingTimeInterval(8.319),
            deviceMilliseconds: 8_636
        ))

        let reconstruction = try #require(capture.reconstruction(
            combinedTimerStoppedAt: timerStart.addingTimeInterval(8.507)
        ))
        let metrics = try #require(reconstruction.combinedTimingMetrics)
        #expect(abs(try #require(metrics.startDelay) - 0.183) < 0.000_1)
        #expect(abs(try #require(metrics.stopDelay) - 0.188) < 0.000_1)

        let decoded = try JSONDecoder().decode(
            SolveReconstruction.self,
            from: JSONEncoder().encode(reconstruction)
        )
        #expect(decoded.combinedTimingAnchors == reconstruction.combinedTimingAnchors)
        #expect(decoded.combinedTimingMetrics == metrics)
    }

    @Test func incompleteCaptureKeepsIndependentlyTrustworthyStartMetric() throws {
        let timerStart = Date(timeIntervalSince1970: 3_000)
        var capture = SmartCubeReconstructionCapture()
        capture.start(initialFacelets: CubeSurface.solved(size: 3), at: timerStart)
        capture.append(canonicalUpdate(
            sequence: 1,
            move: "U",
            date: timerStart.addingTimeInterval(0.2),
            deviceMilliseconds: 200
        ))
        capture.markIncomplete(.disconnected)

        let reconstruction = try #require(capture.reconstruction(
            combinedTimerStoppedAt: timerStart.addingTimeInterval(6)
        ))
        let metrics = try #require(reconstruction.combinedTimingMetrics)
        #expect(reconstruction.completeness == .incomplete)
        #expect(abs(try #require(metrics.startDelay) - 0.2) < 0.000_1)
        #expect(metrics.stopDelay == nil)
    }

    @Test func capturePersistsMoreThanDiagnosticHistoryLimit() throws {
        let start = Date(timeIntervalSince1970: 4_000)
        var capture = SmartCubeReconstructionCapture()
        capture.start(initialFacelets: CubeSurface.solved(size: 3), at: start)
        for index in 0..<150 {
            capture.append(canonicalUpdate(
                sequence: UInt64(index + 1),
                move: index.isMultiple(of: 2) ? "R" : "R'",
                date: start.addingTimeInterval(Double(index + 1) * 0.05),
                deviceMilliseconds: (index + 1) * 50
            ))
        }
        let reconstruction = try #require(capture.reconstruction())
        #expect(reconstruction.moves.count == 150)
        #expect(reconstruction.facelets(afterMoveCount: 150) == CubeSurface.solved(size: 3))

        let decoded = try JSONDecoder().decode(
            SolveReconstruction.self,
            from: JSONEncoder().encode(reconstruction)
        )
        #expect(decoded.moves.count == 150)
    }

    @Test func physicalStateClassifierDoesNotConfuseOneMoveAwayWithPlusTwo() throws {
        let solved = CubeSurface.solved(size: 3)
        let oneMoveAway = try #require(CubeLayerTurn("R")?.applying(to: solved, size: 3))
        #expect(CombinedPhysicalResultClassifier.result(facelets: solved, isStateTrusted: true) == .solved)
        #expect(CombinedPhysicalResultClassifier.result(facelets: oneMoveAway, isStateTrusted: true) == .dnf)
        #expect(CombinedPhysicalResultClassifier.result(facelets: solved, isStateTrusted: false) == .dnf)
    }

    @Test func explicitTwoByTwoScrambleProgressUsesTwentyFourFacelets() throws {
        let progress = try #require(SmartCubeScrambleProgress(scramble: "R U F", puzzleSize: 2))
        #expect(progress.expectedFacelets.first == CubeSurface.solved(size: 2))
        #expect(progress.targetFacelets.count == 24)
    }

    @Test func verifiedScrambleBecomesUnreadyAfterAPreStartTurn() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U"))
        _ = progress.update(with: progress.expectedFacelets[1], canonicalMove: "R")
        _ = progress.update(with: progress.expectedFacelets[2], canonicalMove: "U")
        #expect(progress.isComplete)
        #expect(combinedDevices(scrambleVerified: progress.isComplete).isReady)

        let moved = try #require(CubeLayerTurn("F")?.applying(to: progress.targetFacelets, size: 3))
        _ = progress.update(with: moved, canonicalMove: "F")
        #expect(!progress.isComplete)
        #expect(progress.isDeviated)
        var lifecycle = CombinedSolveLifecycle()
        let didStart = lifecycle.timerDidStart(readiness: combinedDevices(scrambleVerified: progress.isComplete))
        #expect(!didStart)
    }

    @Test(arguments: 0..<64)
    func combinedReadinessRequiresEveryDeviceAndReadinessCondition(mask: Int) {
        let readiness = CombinedSolveReadiness(
            smartCubeConnected: mask & 1 != 0,
            smartCubeObservationReady: mask & 2 != 0,
            scrambleVerified: mask & 4 != 0,
            smartCubeReady: mask & 8 != 0,
            smartTimerConnected: mask & 16 != 0,
            smartTimerReady: mask & 32 != 0
        )
        var lifecycle = CombinedSolveLifecycle()
        let expected = mask == 63
        let didStart = lifecycle.timerDidStart(readiness: readiness)
        #expect(readiness.isReady == expected)
        #expect(didStart == expected)
        #expect(lifecycle.isActive == expected)
        let completion = lifecycle.timerDidStop(seconds: 8.1)
        let duplicateCompletion = lifecycle.timerDidStop(seconds: 8.1)
        #expect(completion == (expected ? .save(seconds: 8.1) : .none))
        #expect(duplicateCompletion == .none)
    }

    @Test func gan251ParserDecodesTwoByTwoStateAndDoubleMove() throws {
        let state = gan251State(serial: 13)
        let stateParser = GANCubeProtocolParser(kind: .ganGen4, puzzleSize: 2)
        let stateEvents = stateParser.handleStateEvent(state)
        guard case .facelets(let facelets, _) = try #require(stateEvents.first) else {
            Issue.record("Expected GAN 251 facelets event")
            return
        }
        #expect(facelets == CubeSurface.solved(size: 2))

        var move = [UInt8](repeating: 0, count: 20)
        move[0] = 0x01
        move[6] = 0x01
        move[8] = 0xA0 // direction=double, face mask=R
        let moveParser = GANCubeProtocolParser(kind: .ganGen4, puzzleSize: 2)
        let moveEvents = moveParser.handleStateEvent(move)
        let parsedMove = try #require(moveEvents.compactMap { event -> SmartCubeMoveEvent? in
            if case .move(let value) = event { return value }
            return nil
        }.first)
        #expect(parsedMove.move == "R2")
    }

    @Test func gan251StateDerivesFinalCornerOrientationAndRejectsHistoryGap() throws {
        let parser = GANCubeProtocolParser(kind: .ganGen4, puzzleSize: 2)
        let twistedState = gan251State(serial: 10, orientations: [1, 2, 0, 0, 0, 0, 0])
        let initialEvents = parser.handleStateEvent(twistedState)
        guard case .facelets(let facelets, _) = try #require(initialEvents.first) else {
            Issue.record("Expected authoritative GAN 251 corner state")
            return
        }
        #expect(facelets.count == 24)
        #expect(facelets != CubeSurface.solved(size: 2))
        #expect(Array("URFDLB").allSatisfy { face in facelets.filter { $0 == face }.count == 4 })

        var skippedMove = [UInt8](repeating: 0, count: 20)
        skippedMove[0] = 0x01
        skippedMove[6] = 0x0C // Counter 12 skips counter 11.
        skippedMove[8] = 0x80 // R clockwise.
        let gapEvents = parser.handleStateEvent(skippedMove)
        #expect(gapEvents.contains { event in
            if case .continuityLost = event { return true }
            return false
        })
        #expect(gapEvents.contains { event in
            if case .requestMoveHistory = event { return true }
            return false
        } == false)
        #expect(gapEvents.contains { event in
            if case .move(let move) = event { return move.move == "R" }
            return false
        })
    }

    @Test func smartCubePuzzleIdentityRecognizesSupportedTwoByTwoDevices() throws {
        #expect(SmartCubePuzzleKind.resolve(
            advertisedName: "GAN251Ui_1234",
            protocolModelIdentifier: nil
        ) == .twoByTwo)
        let info = try #require(SmartCubeProtocolIdentityInfo(
            hardwareSummary: "WCU_MY22 HW 2.1 SW 2.1"
        ))
        let identity = SmartCubeIdentity.resolve(
            advertisedName: "WCU_MY22_0FAD",
            protocolFamily: .moyu,
            protocolConfirmed: true,
            protocolInfo: info,
            serviceIdentifiers: []
        )
        #expect(identity.puzzleKind == .twoByTwo)
        #expect(identity.resolvedModel == "MoYu WeiPo V5 AI")
    }

    @Test func combinedModeIsExplicitAndPersistsPerSession() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let session = Session(
            name: "Combined",
            selectedTimingMethodRawValue: SessionTimingMethod.smartCubeAndGAN.rawValue,
            context: context
        )
        try context.save()

        let restored = session.restoreTimerConfiguration(
            legacyTimingMethodRawValue: SessionTimingMethod.timer.rawValue
        )
        #expect(restored.timingMethod == .smartCubeAndGAN)
        #expect(restored.timingMethod.usesSmartCube)
        #expect(restored.timingMethod.usesGANTimer)
        #expect(SessionTimingMethod.smartCube.solveInputSource == .smartCube)
    }

    private var fullyReadyCombinedDevices: CombinedSolveReadiness {
        combinedDevices()
    }

    private func combinedDevices(
        timerConnected: Bool = true,
        scrambleVerified: Bool = true
    ) -> CombinedSolveReadiness {
        CombinedSolveReadiness(
            smartCubeConnected: true,
            smartCubeObservationReady: true,
            scrambleVerified: scrambleVerified,
            smartCubeReady: true,
            smartTimerConnected: timerConnected,
            smartTimerReady: true
        )
    }

    private func fixture(
        completeness: SolveReconstruction.Completeness,
        reason: String? = nil
    ) -> SolveReconstruction {
        SolveReconstruction(
            puzzleSize: 3,
            initialFacelets: CubeSurface.solved(size: 3),
            moves: [move("R", at: 0), move("U", at: 0.18)],
            completeness: completeness,
            continuityReason: reason
        )
    }

    private func move(_ notation: String, at timestamp: TimeInterval) -> SolveReconstruction.Move {
        SolveReconstruction.Move(
            canonicalMove: notation,
            relativeTimestamp: timestamp,
            timestampSource: "deviceClock",
            deviceTimestampMilliseconds: Int(timestamp * 1_000),
            canonicalSequence: nil
        )
    }

    private func canonicalUpdate(
        sequence: UInt64,
        move: String,
        date: Date,
        deviceMilliseconds: Int
    ) -> SmartCubeCanonicalUpdate {
        SmartCubeCanonicalUpdate(
            sequence: sequence,
            move: SmartCubeMoveEvent(
                move: move,
                serial: Int(sequence),
                face: nil,
                direction: nil,
                localTimestamp: date,
                cubeTimestampMilliseconds: deviceMilliseconds,
                timestampSource: .deviceClock
            ),
            facelets: CubeSurface.solved(size: 3),
            isStateTrusted: true
        )
    }


    private func writeBits(
        _ value: Int,
        start: Int,
        length: Int,
        into bytes: inout [UInt8]
    ) {
        for offset in 0..<length {
            let shift = length - offset - 1
            let bit = (value >> shift) & 1
            let bitIndex = start + offset
            let byteIndex = bitIndex / 8
            let mask = UInt8(1 << (7 - bitIndex % 8))
            if bit == 1 { bytes[byteIndex] |= mask }
        }
    }

    private func gan251State(
        serial: Int,
        orientations: [Int] = [0, 0, 0, 0, 0, 0, 0]
    ) -> [UInt8] {
        var state = [UInt8](repeating: 0, count: 20)
        state[0] = 0xED
        state[1] = 0x0D
        state[2] = UInt8(serial & 0xFF)
        state[3] = UInt8((serial >> 8) & 0xFF)
        for index in 0..<7 {
            writeBits(index, start: 32 + index * 3, length: 3, into: &state)
            writeBits(orientations[index], start: 53 + index * 2, length: 2, into: &state)
        }
        return state
    }
}
