import XCTest
import SwiftUI
import Combine
import SceneKit
@testable import CubeFlow

private actor OwnershipGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    func pause() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class SmartCubeOwnershipAuditTests: XCTestCase {
    private func request() -> SmartCubeGuidanceController.Request {
        .init(identity: .init(scrambleEpochID: UUID(), stateVersion: 1),
            sourceFacelets: CubeSurface.solved(size: 3), targetFacelets: CubeSurface.solved(size: 3), generation: 0, knownPath: [])
    }
    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Ownership boundary not reached")
    }
    func testSuspendedSettleDoesNotRetainRemovedGuidanceOwner() async throws {
        let gate = OwnershipGate()
        var owner: SmartCubeGuidanceController? = SmartCubeGuidanceController(settle: { await gate.pause() })
        weak var observed = owner
        owner?.submit(request())
        try await wait { await gate.entered }
        owner = nil
        XCTAssertNil(observed, "A retained StateObject can be removed while settling")
        await gate.release()
    }
    func testInFlightWorkerDoesNotRetainRemovedOwnerOrPublishIntoNewOwner() async throws {
        let gate = OwnershipGate()
        var owner: SmartCubeGuidanceController? = SmartCubeGuidanceController(settle: {}, search: { request in
            await gate.pause()
            return await SmartCubeReplacementPlanner.currentStateDecision(identity: request.identity,
                sourceFacelets: request.sourceFacelets, targetFacelets: request.targetFacelets, currentGeneration: request.generation, knownPath: [])
        })
        weak var observed = owner
        owner?.submit(request())
        try await wait { await gate.entered }
        owner = nil
        XCTAssertNil(observed)
        let replacement = SmartCubeGuidanceController()
        await gate.release()
        await Task.yield()
        XCTAssertNil(replacement.publication)
        XCTAssertFalse(replacement.isUpdating)
    }
    func testRendererStopCancelsObservationAndReleasesCoordinatorAcrossRemounts() async throws {
        for size in [2, 3, 2, 3] {
            let feed = SmartCubeCanonicalFeed()
            var subscriptions = 0
            let events = feed.events.handleEvents(receiveSubscription: { _ in subscriptions += 1 }, receiveCancel: { subscriptions -= 1 }).eraseToAnyPublisher()
            weak var weakCoordinator: SmartCube3DView.Coordinator?
            weak var weakView: SCNView?
            autoreleasepool {
                let coordinator = SmartCube3DView.Coordinator()
                weakCoordinator = coordinator
                let view = coordinator.makeView(owner: "ownership-audit")
                weakView = view
                let attempt = UUID()
                for revision in [1, 2] {
                    coordinator.update(facelets: CubeSurface.solved(size: size), stateRevision: revision, fixedView: .urf,
                        size: size, events: events, attemptID: attempt, trusted: true, tps: 10,
                        appearance: .classic, plastic: .black, reflections: false, customColor: .purple)
                }
                XCTAssertEqual(subscriptions, 1, "Same session must not subscribe again on redraw")
                SmartCube3DView.dismantleUIView(view, coordinator: coordinator)
                XCTAssertEqual(subscriptions, 0)
            }
            try await wait { autoreleasepool { weakCoordinator == nil } }
            XCTAssertNil(weakCoordinator)
            // Even a plain native SCNView survives this test boundary; do not
            // mistake framework retention for a retained CubeFlow coordinator.
            print("[SceneKitTeardown] componentViewReleased=\(autoreleasepool { weakView == nil })")
        }
    }
    func testSceneKitTeardownIsolation() async throws {
        for mode in ["existing", "pause", "detach"] {
            weak var remaining: SCNView?
            autoreleasepool {
                let coordinator = SmartCube3DView.Coordinator()
                let view = coordinator.makeView(owner: "teardown-" + mode)
                remaining = view
                SmartCube3DView.dismantleUIView(view, coordinator: coordinator)
                if mode != "existing" { view.isPlaying = false; view.rendersContinuously = false }
                if mode == "detach" { view.scene = nil }
            }
            for _ in 0..<40 {
                if autoreleasepool(invoking: { remaining == nil }) { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            print("[SceneKitTeardown] mode=\(mode) released=\(autoreleasepool(invoking: { remaining == nil }))")
        }
        for kind in ["UIView", "SCNView"] {
            weak var remaining: UIView?
            autoreleasepool {
                let view: UIView = kind == "UIView" ? UIView() : SCNView()
                remaining = view
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            let released = autoreleasepool { remaining == nil }
            print("[SceneKitTeardown] mode=plain-\(kind) released=\(released)")
            if kind == "UIView" { XCTAssertTrue(released) }
        }
    }
    func testMountedFittedCardOwnsOnlyOneSubscriptionAndReleasesItOnRemoval() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let feed = SmartCubeCanonicalFeed()
        var subscriptions = 0
        let events = feed.events.handleEvents(receiveSubscription: { _ in subscriptions += 1 }, receiveCancel: { subscriptions -= 1 }).eraseToAnyPublisher()
        for (size, overflow) in [(2, false), (3, true), (2, false)] {
            let attempt = UUID()
            host.rootView = AnyView(SmartCubeManagementFittedContent(maximumHeight: 680) {
                VStack {
                    SmartCube3DView(facelets: CubeSurface.solved(size: size), stateRevision: 1, fixedView: .urf,
                        cubeSize: size, events: events, connectionAttemptID: attempt, diagnosticOwner: "mounted-ownership")
                        .id(attempt).frame(height: 190)
                    if overflow { Color.clear.frame(height: 800) }
                }
            }.frame(width: 350))
            try await wait { window.layoutIfNeeded(); return subscriptions == 1 }
            try await Task.sleep(nanoseconds: 60_000_000)
            XCTAssertEqual(subscriptions, 1)
            host.rootView = AnyView(Color.clear)
            try await wait { window.layoutIfNeeded(); return subscriptions == 0 }
            XCTAssertEqual(subscriptions, 0)
        }
    }
}
