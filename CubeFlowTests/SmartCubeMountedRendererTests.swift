#if DEBUG
import XCTest
import SwiftUI
import SceneKit
import CoreData
import Combine
@testable import CubeFlow

@MainActor final class SmartCubeMountedRendererTests: XCTestCase {
    func testActualSettingsTimerAndManagementRenderSlowMovesThroughParentUpdates() async throws {
        let persistence = PersistenceController(inMemory: true)
        let selected = Session(name: "Mounted renderers", selectedTimingMethodRawValue: "smartCube",
            context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let defaults = UserDefaults.standard
        let keys = ["selectedSessionID", "enteringTimesWith", "smartCubeShowVirtualCube", "smartCubeAnimationTPS"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defaults.set(selected.id.uuidString, forKey: keys[0]); defaults.set("smartCube", forKey: keys[1])
        defaults.set(true, forKey: keys[2]); defaults.set(4, forKey: keys[3])
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, id = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let session = manager.debugMakeRoutedSession(for: id)
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3), name: "GAN16 MagLev", battery: 76)
        manager.selectActiveDevice(id)
        defer { manager.disconnect(deviceID: id) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func cubes(_ view: UIView) -> [SCNView] { (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(cubes) }
        for surface in ["settings", "timer", "management"] {
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let probe = SmartCubeTimerGuidanceProbe()
            let content: AnyView
            if surface == "settings" { content = AnyView(CompatibleNavigationContainer { SmartCubeLabView() }) }
            else if surface == "timer" { content = AnyView(TimerTabView().environment(\.managedObjectContext, persistence.container.viewContext).environment(\.smartCubeTimerGuidanceProbe, probe)) }
            else { content = AnyView(SmartCubeManagementCard(selectedID: id, dismiss: {})) }
            window.rootViewController = UIHostingController(rootView: content)
            window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
            for _ in 0..<100 where cubes(window).isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
            let view = try XCTUnwrap(cubes(window).first), owner = try XCTUnwrap(SmartCube3DView.debugCoordinator(of: view))
            XCTAssertTrue(owner.debugClockIsActive, surface)
            if surface == "timer" {
                for _ in 0..<100 where probe.prepare == nil { try await Task.sleep(nanoseconds: 10_000_000) }
                probe.prepare?("R U2 F B R B2 R U2 L B2 R2 D F2 L2 U' B2 U2 L2 D F2")
            }
            for move in ["U", "U", "U2", "R", "F'", "L2"] {
                print("[MountedSlow] surface=\(surface) before=\(move) \(owner.debugLifecycle) sessionSequence=\(session.canonicalSequence) managerSequence=\(manager.canonicalSequence) trusted=\(session.hasTrustedCanonicalState)")
                session.debugEmitPhysicalMove(move)
                print("[MountedSlow] surface=\(surface) after=\(move) \(owner.debugLifecycle)")
                let current = try XCTUnwrap(owner.debugPresentation.current, "\(surface) must enqueue even isolated slow \(move)")
                let identity = current.id
                manager.objectWillChange.send()
                try await Task.sleep(nanoseconds: 60_000_000)
                XCTAssertTrue(cubes(window).first === view, "\(surface) must retain its renderer on unrelated publication")
                XCTAssertEqual(owner.debugPresentation.current?.id, identity, surface)
                XCTAssertGreaterThan(abs(owner.debugPivotAngle ?? 0), 0.05, "\(surface) must render an intermediate angle")
                XCTAssertLessThan(abs(owner.debugPivotAngle ?? 0), abs(Float(current.move.turn.angle)), surface)
                try await Task.sleep(nanoseconds: 320_000_000)
                XCTAssertEqual(owner.debugPresentation.settled, session.facelets, surface)
                XCTAssertNil(owner.debugPresentation.current, surface)
            }
            window.isHidden = true; window.rootViewController = nil
        }
    }
}
#endif
