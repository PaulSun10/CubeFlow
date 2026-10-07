import Testing
@testable import CubeFlow

@Suite("2x2 state and WeiPo native presentation")
struct CubeStateEquivalenceTests {
    @Test func centerlessRotationEquivalenceDoesNotChangeThreeByThreeRules() throws {
        let two = CubeSurface.solved(size: 2)
        let rotatedTwo = try rotateWholeCube(two, size: 2)
        #expect(rotatedTwo != two)
        #expect(CubeStateEquivalence.matches(two, rotatedTwo, puzzleSize: 2))
        #expect(CubeStateEquivalence.isSolved(rotatedTwo, puzzleSize: 2))

        let three = CubeSurface.solved(size: 3)
        let rotatedThree = try rotateWholeCube(three, size: 3)
        #expect(rotatedThree != three)
        #expect(!CubeStateEquivalence.matches(three, rotatedThree, puzzleSize: 3))
        #expect(!CubeStateEquivalence.isSolved(rotatedThree, puzzleSize: 3))

        let nativeF = try #require(CubeLayerTurn("F")?.applying(to: two, size: 2))
        let printedR = try #require(CubeLayerTurn("R")?.applying(to: two, size: 2))
        #expect(CubeStateEquivalence.matches(nativeF, printedR, puzzleSize: 2))
        #expect(!CubeStateEquivalence.matches(nativeF, printedR, puzzleSize: 3))
    }

    @Test func twoByTwoScrambleRequiresExactStateUpToRigidRotation() throws {
        var progress = try #require(SmartCubeScrambleProgress(scramble: "R U F", puzzleSize: 2))
        let rotatedTarget = try rotateWholeCube(progress.targetFacelets, size: 2)
        #expect(progress.update(with: rotatedTarget) == .completed)
        #expect(progress.isComplete)
        #expect(progress.currentMoveTokenIndex == nil)

        let different = try #require(CubeLayerTurn("R")?.applying(to: rotatedTarget, size: 2))
        _ = progress.update(with: different)
        #expect(!progress.isComplete)
        #expect(!CubeStateEquivalence.matches(different, progress.targetFacelets, puzzleSize: 2))
        #expect(!progress.isDeviated)
        #expect(CombinedPhysicalResultClassifier.result(facelets: rotatedTarget, isStateTrusted: true) == .dnf)
        let rotatedSolved = try rotateWholeCube(CubeSurface.solved(size: 2), size: 2)
        #expect(CombinedPhysicalResultClassifier.result(facelets: rotatedSolved, isStateTrusted: true) == .solved)
    }

    @Test func weiPoA3CertifiesNativeTurnChainBeforeAnimation() throws {
        let baseline = nativeState("0002494926DB924B6D", counter: 10)
        let first = nativeState("0002494A4B5B8E3555", counter: 11)
        let solved = CubeSurface.solved(size: 2)
        let expectedF = try #require(CubeLayerTurn("F")?.applying(to: solved, size: 2))
        let expectedFU = try #require(CubeLayerTurn("U")?.applying(to: expectedF, size: 2))

        for payload in ["5408C98A2B5B023255", "5408C94A4AEB023255"] {
            var adapter = WeiPo2NativeVisualAdapter()
            #expect(adapter.accept(baseline) == solved)
            adapter.note(.init(code: 0, turnCounter: 11, missedTurnCount: 0))
            #expect(adapter.accept(first) == expectedF)
            #expect(adapter.validatedTurns.map(\.notation) == ["F"])
            adapter.note(.init(code: 2, turnCounter: 12, missedTurnCount: 0))
            #expect(adapter.accept(nativeState(payload, counter: 12)) == expectedFU)
            #expect(adapter.validatedTurns.map(\.notation) == ["U"])
            #expect(adapter.possibleLayoutCount == 1)
            #expect(adapter.accept(first) == expectedFU) // Late old A3 cannot replay the turn.
            #expect(adapter.validatedTurns.isEmpty)
        }
    }

    @Test func inverseBurstAndInvalidCorrectionDoNotDoubleApply() {
        let baseline = nativeState("0002494926DB924B6D", counter: 10)
        var adapter = WeiPo2NativeVisualAdapter()
        _ = adapter.accept(baseline)
        adapter.note(.init(code: 0, turnCounter: 11, missedTurnCount: 0))
        adapter.note(.init(code: 1, turnCounter: 12, missedTurnCount: 0))
        #expect(adapter.accept(nativeState("0002494926DB924B6D", counter: 12)) == CubeSurface.solved(size: 2))
        #expect(adapter.validatedTurns.map(\.notation) == ["F", "F'"])
        #expect(adapter.validatedTurns.last?.facelets == CubeSurface.solved(size: 2))

        adapter.note(.init(code: 0, turnCounter: 13, missedTurnCount: 0))
        #expect(adapter.accept(nativeState("0C3451410659924B6D", counter: 13)) == nil)
        #expect(adapter.rejectedNewSnapshot)
        #expect(adapter.validatedTurns.isEmpty)
    }

    @Test func twoByTwoReconstructionStartsBeforeItsFirstCertifiedTurn() throws {
        let solved = CubeSurface.solved(size: 2)
        let moved = try #require(CubeLayerTurn("F")?.applying(to: solved, size: 2))
        let update = SmartCubeCanonicalUpdate(
            sequence: 1,
            move: SmartCubeMoveEvent(
                move: "F", serial: 1, face: nil, direction: nil,
                localTimestamp: .now, cubeTimestampMilliseconds: nil
            ),
            facelets: moved
        )
        let initial = try #require(update.previousTwoByTwoFacelets)
        #expect(initial == solved)
        let reconstruction = SolveReconstruction(
            puzzleSize: 2, initialFacelets: initial,
            moves: [.init(
                canonicalMove: "F", relativeTimestamp: 0,
                timestampSource: "hostReceipt", deviceTimestampMilliseconds: nil,
                canonicalSequence: 1
            )], completeness: .complete
        )
        #expect(reconstruction.facelets(afterMoveCount: 1) == moved)
    }

    private func nativeState(_ hex: String, counter: UInt8) -> WeiPo2NativeState {
        let bytes = stride(from: 0, to: hex.count, by: 2).map { index -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        let values = (0..<24).map { sticker -> UInt8 in
            (0..<3).reduce(0) { value, bit in
                let offset = sticker * 3 + bit
                return (value << 1) | ((bytes[offset / 8] >> (7 - offset % 8)) & 1)
            }
        }
        return WeiPo2NativeState(stickerValues: values, turnCounter: counter)
    }

    private func rotateWholeCube(_ facelets: String, size: Int) throws -> String {
        let surfaces = CubeSurface.all(size: size)
        let indices = Dictionary(uniqueKeysWithValues: surfaces.enumerated().map { ($0.element, $0.offset) })
        var result = Array(facelets)
        for (index, sticker) in surfaces.enumerated() {
            let position = sticker.position
            let normal = sticker.normal
            let target = CubeSurface(
                position: .init(position.z, position.y, -position.x),
                normal: .init(normal.z, normal.y, -normal.x)
            )
            result[try #require(indices[target])] = Array(facelets)[index]
        }
        return String(result)
    }
}
