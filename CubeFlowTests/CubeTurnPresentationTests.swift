#if os(iOS)
import Testing
@testable import CubeFlow

struct CubeTurnPresentationTests {
    private let solved = CubeSurface.solved(size: 3)

    @Test func allTurnsMatchCanonicalMapping() throws {
        let state = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R U F2 L D' B R2"))
        for face in "URFDLB" {
            for suffix in ["", "'", "2"] {
                let move = "\(face)\(suffix)"
                let turn = try #require(CubeLayerTurn(move))
                #expect(turn.applying(to: state, size: 3) == SmartCubeBluetoothManager.facelets(state, applying: move))
            }
        }
    }

    @Test func canonicalDoesNotWaitForPresentation() throws {
        var engine = CubeTurnPresentation(facelets: solved)
        let target = try #require(CubeLayerTurn("R")?.applying(to: solved, size: 3))
        engine.enqueue("R", target: target, timestamp: 0, now: 0)
        #expect(engine.canonical == target)
        #expect(engine.settled == solved)
        engine.advance(at: 0.11)
        #expect(engine.settled == target)
        #expect(engine.current == nil)
    }

    @Test func halfTurnIsOneAnimation() throws {
        var engine = CubeTurnPresentation(facelets: solved)
        let target = try #require(CubeLayerTurn("R2")?.applying(to: solved, size: 3))
        engine.enqueue("R2", target: target, timestamp: 0, now: 0)
        let animation = try #require(engine.current)
        #expect(abs(animation.duration - 0.13) < 0.00001)
        #expect(abs(animation.move.turn.angle) == .pi)
        #expect(engine.pending.isEmpty)
    }

    @Test func newMoveCompressesRemainingTimeWithoutChangingProgress() throws {
        var engine = CubeTurnPresentation(facelets: solved)
        engine.tps = 1
        let first = try #require(CubeLayerTurn("R")?.applying(to: solved, size: 3))
        engine.enqueue("R", target: first, timestamp: 0, now: 0)
        let before = try #require(engine.current).progress(at: 0.2)
        let second = try #require(CubeLayerTurn("U")?.applying(to: first, size: 3))
        engine.enqueue("U", target: second, timestamp: 0.2, now: 0.2)
        let animation = try #require(engine.current)
        #expect(animation.progress(at: 0.2) == before)
        #expect(animation.duration <= CubeTurnPresentation.Policy.interruptedRemaining)
        engine.advance(at: 0.26)
        #expect(engine.settled == first)
        #expect(engine.current?.move.target == second)
    }

    @Test func recoveredBurstSkipsOlderPresentationAndConverges() throws {
        var engine = CubeTurnPresentation(facelets: solved)
        engine.tps = 1
        for (index, move) in ["R", "U", "F", "L", "D", "B", "R2", "U2", "F2", "L2", "D2", "B2"].enumerated() {
            let target = try #require(CubeLayerTurn(move)?.applying(to: engine.canonical, size: 3))
            engine.enqueue(move, target: target, timestamp: 0, now: Double(index) * 0.001)
            #expect(engine.pending.count < CubeTurnPresentation.Policy.severeBacklog)
        }
        #expect(engine.settled != solved)
        for time in 1...8 { engine.advance(at: Double(time)) }
        #expect(engine.settled == engine.canonical)
        #expect(engine.pending.isEmpty)
        #expect(engine.current == nil)
    }

    @Test func unlimitedAndResyncDiscardAnimation() throws {
        var engine = CubeTurnPresentation(facelets: solved)
        let target = try #require(CubeLayerTurn("F")?.applying(to: solved, size: 3))
        engine.enqueue("F", target: target, timestamp: 0, now: 0)
        let generation = engine.generation
        engine.resync(solved, trusted: false)
        #expect(engine.generation > generation)
        #expect(engine.current == nil && engine.pending.isEmpty)
        #expect(!engine.isTrusted)
        engine.resync(solved, trusted: true)
        engine.tps = 0
        engine.enqueue("F", target: target, timestamp: 1, now: 1)
        #expect(engine.settled == target && engine.current == nil)
    }

    @Test func snapshotMismatchDoesNotInventMoves() {
        var engine = CubeTurnPresentation(facelets: solved)
        engine.enqueue("R", target: solved, timestamp: 0, now: 0)
        #expect(engine.current == nil && engine.pending.isEmpty)
        #expect(engine.settled == solved)
    }

    @Test func twoByTwoGeometryAndMoves() throws {
        let surfaces = CubeSurface.all(size: 2)
        #expect(surfaces.count == 24)
        #expect(Set(surfaces.map(\.position)).count == 8)
        let initial = CubeSurface.solved(size: 2)
        for face in "URFDLB" {
            let turn = try #require(CubeLayerTurn(String(face)))
            #expect(Set(surfaces.filter { turn.contains($0.position, size: 2) }.map(\.position)).count == 4)
            var state = initial
            for _ in 0..<4 { state = try #require(turn.applying(to: state, size: 2)) }
            #expect(state == initial)
        }
    }
}
#endif
