import XCTest
import SwiftUI
import SceneKit
@testable import CubeFlow

@MainActor final class ConcurrentCubeStabilityTests: XCTestCase {
    func testTwoMountedOnDemandRenderersImmediatelyWakeAnimateAndSleepIndependently() async throws {
        let owners = [SmartCube3DView.Coordinator(), SmartCube3DView.Coordinator()]
        let feeds = [SmartCubeCanonicalFeed(), SmartCubeCanonicalFeed()]
        let views = owners.map { $0.makeView(owner: "concurrent-stress") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.rootViewController = UIViewController()
        let solved = CubeSurface.solved(size: 3)
        for index in owners.indices {
            owners[index].update(facelets: solved, stateRevision: 0, fixedView: .urf, size: 3,
                events: feeds[index].events, attemptID: UUID(), trusted: true, tps: 16,
                appearance: .classic, plastic: .black, reflections: false, customColor: .purple, canonicalSequence: 0)
            views[index].frame = CGRect(x: 0, y: index * 200, width: 190, height: 190)
            window.rootViewController?.view.addSubview(views[index])
        }
        window.makeKeyAndVisible()
        defer { owners.forEach { $0.stop() }; window.isHidden = true; window.rootViewController = nil }
        var states = [solved, solved]
        for turn in 0..<36 {
            for index in owners.indices {
                let notation = index == 0 ? ["R", "U", "F2", "L'"][turn % 4] : ["B'", "D2", "R"][turn % 3]
                states[index] = try XCTUnwrap(CubeLayerTurn(notation)?.applying(to: states[index], size: 3))
                feeds[index].send(move: .init(move: notation, serial: nil, face: nil, direction: nil,
                    localTimestamp: .now, cubeTimestampMilliseconds: nil), facelets: states[index])
                XCTAssertNotNil(owners[index].debugPresentation.current)
                XCTAssertFalse(owners[index].debugClockIsPaused)
            }
        }
        var rendered = [Set<UInt64>(), Set<UInt64>()]
        for _ in 0..<1200 {
            for index in owners.indices { if let current = owners[index].debugPresentation.current { rendered[index].insert(current.id) } }
            if owners.allSatisfy({ $0.debugPresentation.current == nil }) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        for index in owners.indices {
            XCTAssertEqual(owners[index].debugPresentation.settled, states[index])
            XCTAssertTrue(owners[index].debugPresentation.pending.isEmpty)
            XCTAssertGreaterThan(rendered[index].count, 3, "Native clock must render intermediate animations")
            XCTAssertTrue(owners[index].debugClockIsPaused)
        }
        let ticks = owners.map(\.debugDisplayLinkTicks)
        try await Task.sleep(nanoseconds: 75_000_000)
        XCTAssertEqual(owners.map(\.debugDisplayLinkTicks), ticks)
    }

    func testIndependentGuidanceOwnersRejectRapidOldSourcesTargetsAndAttempts() async throws {
        let owners = [GuidanceStateTestHarness(), GuidanceStateTestHarness()]
        let ids = [UUID(), UUID()], attempts = [UUID(), UUID()], solved = CubeSurface.solved(size: 3)
        defer { owners.forEach { $0.cancel() } }
        owners[0].setScramble("R U"); owners[1].setScramble("F L")
        for turn in 0..<100 {
            for index in owners.indices {
                let state = try XCTUnwrap(CubeLayerTurn(turn % 2 == 0 ? "B" : "U")?.applying(to: solved, size: 3))
                owners[index].update(facelets: state, trusted: true, deviceID: ids[index], attemptID: attempts[index], sequence: UInt64(turn))
            }
        }
        owners[0].setScramble("D"); owners[1].setScramble("B2")
        for index in owners.indices {
            owners[index].update(facelets: solved, trusted: true, deviceID: ids[index], attemptID: UUID(), sequence: 101)
        }
        for _ in 0..<600 where owners.contains(where: { $0.route == nil }) { try await Task.sleep(nanoseconds: 5_000_000) }
        for index in owners.indices {
            let route = try XCTUnwrap(owners[index].route)
            let target = try route.tokens.reduce(solved) { try XCTUnwrap(CubeLayerTurn($1)?.applying(to: $0, size: 3)) }
            XCTAssertEqual(target, owners[index].target)
        }
        owners[0].update(facelets: solved, trusted: false, deviceID: ids[0], attemptID: attempts[0], sequence: 102)
        XCTAssertNil(owners[0].route); XCTAssertNotNil(owners[1].route)
    }
}
