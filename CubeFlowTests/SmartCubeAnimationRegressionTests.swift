#if DEBUG
import XCTest
import SwiftUI
import SceneKit
import Combine
@testable import CubeFlow

@MainActor final class SmartCubeAnimationRegressionTests: XCTestCase {
    func testEventlessAuthoritativeSnapshotReconcilesAfterDeliveryTurnAndCannotCrossRebinding() async throws {
        let owner = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed()
        let view = owner.makeView(owner: "snapshot-fallback"), attempt = UUID()
        defer { owner.stop(); view.scene = nil }
        let solved = CubeSurface.solved(size: 3)
        func update(_ state: String, sequence: UInt64, attempt: UUID) {
            owner.update(facelets: state, stateRevision: 1, fixedView: .urf, size: 3,
                events: feed.events, attemptID: attempt, trusted: true, tps: 4, appearance: .classic,
                plastic: .black, reflections: false, customColor: .purple, canonicalSequence: sequence)
        }
        update(solved, sequence: 0, attempt: attempt)
        let correction = try XCTUnwrap(CubeLayerTurn("F2")?.applying(to: solved, size: 3))
        update(correction, sequence: 1, attempt: attempt)
        for _ in 0..<50 where owner.debugPresentation.canonical != correction { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(owner.debugPresentation.settled, correction)
        XCTAssertNil(owner.debugPresentation.current, "A genuine eventless correction still snaps, not an invented turn")
        update(solved, sequence: 2, attempt: attempt)
        update(correction, sequence: 0, attempt: UUID())
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(owner.debugPresentation.settled, correction, "The old pending snapshot must not cross binding ownership")
    }
    func testNewSwiftUISnapshotCannotPreemptItsCanonicalMoveDelivery() throws {
        let owner = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed(), attempt = UUID()
        let view = owner.makeView(owner: "snapshot-before-event")
        defer { owner.stop(); view.scene = nil }
        func update(_ state: String, sequence: UInt64) {
            owner.update(facelets: state, stateRevision: 1, fixedView: .urf, size: 3,
                events: feed.events, attemptID: attempt, trusted: true, tps: 4, appearance: .classic,
                plastic: .black, reflections: false, customColor: .purple, canonicalSequence: sequence)
        }
        // Timer's model subscriber can publish SwiftUI state synchronously
        // before the renderer's later subscriber receives the same event.
        let model = feed.events.sink { event in
            if case .move(let move) = event { update(move.facelets, sequence: move.sequence) }
        }
        defer { model.cancel() }
        var state = CubeSurface.solved(size: 3)
        update(state, sequence: 0)
        for move in ["U", "U", "U2", "R", "F'"] {
            state = try XCTUnwrap(CubeLayerTurn(move)?.applying(to: state, size: 3))
            feed.send(move: .init(move: move, serial: nil, face: nil, direction: nil,
                localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: state)
            let animation = try XCTUnwrap(owner.debugPresentation.current,
                "A current/future body snapshot must not consume the event sequence before its executable move")
            owner.debugRender(at: animation.startedAt + animation.duration / 2)
            XCTAssertGreaterThan(abs(owner.debugPivotAngle ?? 0), 0.1)
            owner.debugRender(at: animation.startedAt + animation.duration + 0.001)
        }
        XCTAssertEqual(owner.debugPresentation.settled, state)
    }
    func testMountedRenderersSuspendIndependentlyAndResumeAtAuthoritativeState() async throws {
        let timer = SmartCube3DView.Coordinator(), card = SmartCube3DView.Coordinator()
        let feed = SmartCubeCanonicalFeed(), attempt = UUID()
        let timerView = timer.makeView(owner: "timer-lifecycle"), cardView = card.makeView(owner: "management-lifecycle")
        defer { timer.stop(); card.stop() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIViewController()
        let root = try XCTUnwrap(window.rootViewController?.view)
        timerView.frame = CGRect(x: 0, y: 0, width: 190, height: 190)
        cardView.frame = CGRect(x: 0, y: 200, width: 190, height: 190)
        XCTAssertFalse(timer.debugClockIsActive); XCTAssertFalse(card.debugClockIsActive)
        var state = CubeSurface.solved(size: 3)
        func update(_ coordinator: SmartCube3DView.Coordinator) {
            coordinator.update(facelets: state, stateRevision: Int(feed.sequence), fixedView: .urf, size: 3,
                events: feed.events, attemptID: attempt, trusted: true, tps: 10, appearance: .classic,
                plastic: .black, reflections: false, customColor: .purple, canonicalSequence: feed.sequence)
        }
        update(timer); update(card)
        root.addSubview(timerView); root.addSubview(cardView); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(timer.debugClockIsActive); XCTAssertTrue(card.debugClockIsActive)
        func turn(_ move: String) throws {
            state = try XCTUnwrap(CubeLayerTurn(move)?.applying(to: state, size: 3))
            feed.send(move: .init(move: move, serial: nil, face: nil, direction: nil,
                localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: state)
        }
        try turn("U")
        XCTAssertNotNil(timer.debugPresentation.current); XCTAssertNotNil(card.debugPresentation.current)
        // A management card covers Timer without detaching Timer's UIKit view.
        timer.setRenderingEnabled(false)
        XCTAssertFalse(timer.debugClockIsActive); XCTAssertTrue(card.debugClockIsActive)
        for move in ["R", "U", "F'", "L2", "D"] { try turn(move); update(timer); update(card) }
        XCTAssertEqual(timer.debugPresentation.canonical, state)
        XCTAssertNil(timer.debugPresentation.current)
        XCTAssertEqual(card.debugPresentation.pending.count, 5, "The visible card preserves every live turn")
        cardView.removeFromSuperview()
        XCTAssertFalse(card.debugClockIsActive)
        try turn("B")
        XCTAssertEqual(card.debugPresentation.settled, state)
        root.addSubview(cardView)
        XCTAssertTrue(card.debugClockIsActive)
        XCTAssertEqual(card.debugPresentation.settled, state)
        XCTAssertNil(card.debugPresentation.current, "An invisible backlog is not replayed on remount")
        timer.setRenderingEnabled(true)
        XCTAssertTrue(timer.debugClockIsActive)
        XCTAssertEqual(timer.debugPresentation.settled, state)
        try turn("R2")
        for coordinator in [timer, card] {
            let animation = try XCTUnwrap(coordinator.debugPresentation.current)
            coordinator.debugRender(at: animation.startedAt + animation.duration / 2)
            XCTAssertGreaterThan(abs(coordinator.debugPivotAngle ?? 0), 0.1)
            coordinator.debugRender(at: animation.startedAt + animation.duration + 0.001)
            XCTAssertEqual(coordinator.debugPresentation.settled, state)
        }
        // Tab removal stops the clock; a dismantled owner cannot restart it.
        timerView.removeFromSuperview()
        XCTAssertFalse(timer.debugClockIsActive)
        timer.stop(); root.addSubview(timerView)
        XCTAssertFalse(timer.debugClockIsActive)
    }

    func testHighFrequencyBurstDoesNotSkipAnyIntermediateLiveTurn() throws {
        let coordinator = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed(), attempt = UUID()
        let view = coordinator.makeView(owner: "saturation-regression")
        defer { coordinator.stop(); view.scene = nil }
        let solved = CubeSurface.solved(size: 3)
        coordinator.update(facelets: solved, stateRevision: 1, fixedView: .urf, size: 3,
            events: feed.events, attemptID: attempt, trusted: true, tps: 10,
            appearance: .classic, plastic: .black, reflections: false, customColor: .purple,
            canonicalSequence: 0)
        var state = solved, targets: [String] = []
        for move in Array(repeating: ["R", "U", "F'", "L2", "D", "B'"], count: 4).flatMap({ $0 }) {
            state = try XCTUnwrap(CubeLayerTurn(move)?.applying(to: state, size: 3))
            targets.append(state)
            feed.send(move: .init(move: move, serial: nil, face: nil, direction: nil,
                localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: state)
        }
        XCTAssertEqual(coordinator.debugPresentation.settled, solved,
            "Enqueueing cannot silently commit unrendered turns")
        var rendered: [String] = []
        while let animation = coordinator.debugPresentation.current {
            rendered.append(animation.move.target)
            coordinator.debugRender(at: animation.startedAt + animation.duration / 2)
            XCTAssertGreaterThan(abs(coordinator.debugPivotAngle ?? 0), 0.1)
            coordinator.debugRender(at: animation.startedAt + animation.duration + 0.001)
        }
        XCTAssertEqual(rendered, targets)
        XCTAssertEqual(coordinator.debugPresentation.settled, state)
    }
    func testRapidMixedMovesAndNativeHalfTurnAllRenderBeforeQueueDrains() throws {
        for moves in [["U2"], ["R", "U", "F'", "L2", "D"]] {
            let coordinator = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed(), attempt = UUID()
            let view = coordinator.makeView(owner: "rapid-animation-regression")
            defer { coordinator.stop(); view.scene = nil }
            func update(_ state: String, sequence: UInt64) {
                coordinator.update(facelets: state, stateRevision: 1, fixedView: .urf, size: 3,
                    events: feed.events, attemptID: attempt, trusted: true, tps: 10,
                    appearance: .classic, plastic: .black, reflections: false, customColor: .purple,
                    canonicalSequence: sequence)
            }
            var state = CubeSurface.solved(size: 3)
            update(state, sequence: 0)
            var targets: [String] = []
            for move in moves {
                let previous = state, sequence = feed.sequence
                state = try XCTUnwrap(CubeLayerTurn(move)?.applying(to: state, size: 3))
                targets.append(state)
                feed.send(move: .init(move: move, serial: nil, face: nil, direction: nil,
                    localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: state)
                update(previous, sequence: sequence)
                XCTAssertEqual(coordinator.debugPresentation.canonical, state)
            }
            update(state, sequence: feed.sequence)
            var rendered: [String] = []
            while let animation = coordinator.debugPresentation.current {
                rendered.append(animation.move.target)
                coordinator.debugRender(at: animation.startedAt + animation.duration / 2)
                XCTAssertGreaterThan(abs(coordinator.debugPivotAngle ?? 0), 0.1)
                coordinator.debugRender(at: animation.startedAt + animation.duration + 0.001)
            }
            XCTAssertEqual(rendered, targets, "Ordinary rapid live moves must not be snapped away by lagging snapshots")
            XCTAssertEqual(coordinator.debugPresentation.settled, state)
            XCTAssertTrue(coordinator.debugPresentation.pending.isEmpty)
        }
    }

    func testAuthoritativeBoundaryAndRebindingStillDiscardObsoleteAnimations() throws {
        let coordinator = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed(), attempt = UUID()
        let view = coordinator.makeView(owner: "boundary-animation-regression")
        defer { coordinator.stop(); view.scene = nil }
        let solved = CubeSurface.solved(size: 3)
        func update(_ state: String, sequence: UInt64, owner: UUID) {
            coordinator.update(facelets: state, stateRevision: 1, fixedView: .urf, size: 3,
                events: feed.events, attemptID: owner, trusted: true, tps: 10,
                appearance: .classic, plastic: .black, reflections: false, customColor: .purple,
                canonicalSequence: sequence)
        }
        update(solved, sequence: 0, owner: attempt)
        let turned = try XCTUnwrap(CubeLayerTurn("U")?.applying(to: solved, size: 3))
        feed.send(move: .init(move: "U", serial: nil, face: nil, direction: nil, localTimestamp: .now,
                             cubeTimestampMilliseconds: nil), facelets: turned)
        XCTAssertNotNil(coordinator.debugPresentation.current)
        feed.breakContinuity(.resync, facelets: solved)
        update(turned, sequence: 1, owner: attempt)
        XCTAssertEqual(coordinator.debugPresentation.canonical, solved)
        XCTAssertNil(coordinator.debugPresentation.current)
        update(turned, sequence: 0, owner: UUID())
        XCTAssertEqual(coordinator.debugPresentation.settled, turned, "A genuine new owner still establishes its authoritative starting snapshot")
    }
    func testTwoPhysicalUEventsSurviveLaggingSwiftUIStateUpdate() throws {
        let coordinator = SmartCube3DView.Coordinator(), feed = SmartCubeCanonicalFeed(), attempt = UUID()
        let view = coordinator.makeView(owner: "animation-regression")
        defer { coordinator.stop(); view.scene = nil }
        func update(_ state: String, sequence: UInt64) {
            coordinator.update(facelets: state, stateRevision: 0, fixedView: .urf, size: 3,
                events: feed.events, attemptID: attempt, trusted: true, tps: 10,
                appearance: .classic, plastic: .black, reflections: false, customColor: .purple,
                canonicalSequence: sequence)
        }
        let s0 = CubeSurface.solved(size: 3)
        update(s0, sequence: 0)
        let s1 = try XCTUnwrap(CubeLayerTurn("U")?.applying(to: s0, size: 3))
        feed.send(move: .init(move: "U", serial: 1, face: nil, direction: nil, localTimestamp: .now,
                             cubeTimestampMilliseconds: nil), facelets: s1)
        update(s1, sequence: 1)
        let first = try XCTUnwrap(coordinator.debugPresentation.current)
        let s2 = try XCTUnwrap(CubeLayerTurn("U")?.applying(to: s1, size: 3))
        feed.send(move: .init(move: "U", serial: 2, face: nil, direction: nil, localTimestamp: .now,
                             cubeTimestampMilliseconds: nil), facelets: s2)
        update(s1, sequence: 1) // A body snapshot captured before the second event.
        XCTAssertEqual(coordinator.debugPresentation.canonical, s2)
        XCTAssertEqual(coordinator.debugPresentation.current?.id, first.id)
        XCTAssertEqual(coordinator.debugPresentation.pending.map(\.turn.notation), ["U"])
        update(s2, sequence: 2)
        let active = try XCTUnwrap(coordinator.debugPresentation.current)
        coordinator.debugRender(at: active.startedAt + active.duration + 0.001)
        let second = try XCTUnwrap(coordinator.debugPresentation.current)
        XCTAssertEqual(second.move.target, s2)
        coordinator.debugRender(at: second.startedAt + second.duration / 2)
        XCTAssertGreaterThan(abs(coordinator.debugPivotAngle ?? 0), 0.1)
        coordinator.debugRender(at: second.startedAt + second.duration + 0.001)
        XCTAssertEqual(coordinator.debugPresentation.settled, s2)
        XCTAssertNil(coordinator.debugPresentation.current)
    }
}
#endif
