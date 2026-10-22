import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor private final class TopMotionFixture {
    let state = CompetitionDisclosureAcceptanceState()
    let window: UIWindow
    let glass: Bool
    let reduceMotion: Bool
    var root: some View {
        CompetitionDisclosureAcceptanceSurface(state: state, controlled: true, boundary: false, edge: false, glass: glass)
    }
    init(glass: Bool, reduceMotion: Bool = false, width: CGFloat = 390) throws {
        self.glass = glass; self.reduceMotion = reduceMotion
        state.reduceMotionForAcceptance = reduceMotion
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
        window.rootViewController = UIHostingController(rootView: root)
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
    }
    func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
    var collection: UICollectionView { get throws { try XCTUnwrap(views(window).compactMap { $0 as? UICollectionView }.first) } }
    var anchor: CompetitionTopCubersMotionAnchor { get throws {
        try XCTUnwrap(views(window).compactMap { $0 as? CompetitionTopCubersMotionAnchor }.first)
    } }
    func tap() throws { try anchor.acceptanceTap?() }
    func close() { window.isHidden = true; window.rootViewController = nil }
    func snapshot() throws -> TopMotionFrame {
        let cell = try XCTUnwrap(try collection.cellForItem(at: IndexPath(item: 1, section: 0)))
        let elements = CompetitionDisclosureViewportProbe.shared.ownerFrames(identity: "fixture", cell: cell, window: window)
        let button = try XCTUnwrap(elements.first { $0["id"] as? String == "fixture|disclosure" })
        let rect = try XCTUnwrap(button["presented"] as? [Double])
        let origin = try XCTUnwrap(CompetitionDisclosureViewportProbe.shared.projectedOrigin(cell.layer, in: window.layer))
        let title = try XCTUnwrap(elements.first { $0["id"] as? String == "fixture" }?["presented"] as? [Double])
        let glassRect = (button["glassAncestors"] as? [[String: Any]])?.first?["presented"] as? [Double]
        return TopMotionFrame(height: cell.layer.presentation()?.bounds.height ?? cell.bounds.height,
            buttonY: rect[1] - origin.y, titleY: title[1] - origin.y, glassHeight: (glassRect?[3]).map { CGFloat($0) },
            offset: try collection.contentOffset.y, fraction: try anchor.motion?.fraction,
            masks: state.revealHeights)
    }
}

private struct TopMotionFrame {
    let height: CGFloat
    let buttonY: CGFloat
    let titleY: CGFloat
    let glassHeight: CGFloat?
    let offset: CGFloat
    let fraction: CGFloat?
    let masks: [String: CGFloat]
}

@MainActor final class CompetitionTopCubersAnimationTests: XCTestCase {
    private func settle() async throws { try await Task.sleep(nanoseconds: 650_000_000) }

    func testNativeCardDisclosureAndProgressiveRevealShareTimelineInBothAppearances() async throws {
        for glass in [false, true] {
            let fixture = try TopMotionFixture(glass: glass)
            defer { fixture.close() }
            try await settle()
            let initial = try fixture.snapshot()
            XCTAssertNil(initial.fraction, "Mounting must not start a disclosure animation")
            for expanding in [true, false] {
                let before = try fixture.snapshot()
                try fixture.tap()
                XCTAssertEqual(fixture.state.expanded, expanding)
                var frames: [TopMotionFrame] = []
                for _ in 0..<50 {
                    frames.append(try fixture.snapshot())
                    try await Task.sleep(nanoseconds: 14_000_000)
                }
                let after = try fixture.snapshot()
                let distance = after.height - before.height
                XCTAssertGreaterThan(abs(distance), 50)
                XCTAssertNil(after.fraction, "Tracking must terminate with the native animation")
                XCTAssertTrue(after.masks.isEmpty)
                let middle = frames.filter { frame in
                    let p = ((frame.glassHeight ?? frame.height) - (before.glassHeight ?? before.height))
                        / ((after.glassHeight ?? after.height) - (before.glassHeight ?? before.height))
                    return p > 0.15 && p < 0.9
                }
                XCTAssertGreaterThan(middle.count, 2, "Must exercise intermediate native presentation frames")
                for frame in frames {
                    XCTAssertEqual(frame.offset, initial.offset, accuracy: 1, "No viewport compensation")
                    XCTAssertEqual(frame.titleY, initial.titleY, accuracy: 1, "Existing content stays fixed")
                    XCTAssertGreaterThanOrEqual(frame.height, min(before.height, after.height) - 1)
                }
                for frame in middle {
                    let cardProgress = ((frame.glassHeight ?? frame.height) - (before.glassHeight ?? before.height))
                        / ((after.glassHeight ?? after.height) - (before.glassHeight ?? before.height))
                    let buttonProgress = (frame.buttonY - before.buttonY) / (after.buttonY - before.buttonY)
                    // Presentation sampling/SwiftUI commits can differ by one
                    // display frame, but not by a second independent easing curve.
                    XCTAssertEqual(buttonProgress, cardProgress, accuracy: 0.22)
                }
                XCTAssertTrue(frames.contains { $0.masks.values.contains { $0 > 1 && $0 < 30 } },
                    "Additional entries must reveal progressively, not arrive fully visible")
                XCTAssertTrue(frames.contains { $0.masks["23"] == 0 }, "The last row waits for available space")
                if !expanding {
                    XCTAssertEqual(after.height, initial.height, accuracy: 1)
                    XCTAssertEqual(after.buttonY, initial.buttonY, accuracy: 1)
                }
            }
        }
    }

    func testRapidTapsAndHostingReplacementCancelLocalMotionWithoutChangingFinalState() async throws {
        for glass in [false, true] {
            let fixture = try TopMotionFixture(glass: glass)
            defer { fixture.close() }
            try await settle()
            let initial = try fixture.snapshot()
            for _ in 0..<3 {
                try fixture.tap()
                try await Task.sleep(nanoseconds: 55_000_000)
            }
            try await settle()
            XCTAssertTrue(fixture.state.expanded)
            let currentMotion = try fixture.anchor.motion
            XCTAssertNil(currentMotion?.fraction, "glass=\(glass), \(currentMotion?.acceptanceState ?? "")")
            let expanded = try fixture.snapshot()
            try fixture.tap()
            try await Task.sleep(nanoseconds: 75_000_000)
            let oldMotion = try XCTUnwrap(fixture.anchor.motion)
            fixture.window.rootViewController = UIHostingController(rootView: fixture.root)
            try await settle()
            XCTAssertNil(oldMotion.fraction)
            XCTAssertNil(try fixture.anchor.motion?.fraction, "Recreated content must not animate on mount")
            XCTAssertFalse(fixture.state.expanded)
            XCTAssertEqual(try fixture.snapshot().height, initial.height, accuracy: 1)
            try fixture.tap(); try await settle()
            XCTAssertEqual(try fixture.snapshot().height, expanded.height, accuracy: 1)
        }
    }

    func testReduceMotionDoesNotStartRevealTrackingAndKeepsBothFinalLayouts() async throws {
        for glass in [false, true] {
            let fixture = try TopMotionFixture(glass: glass, reduceMotion: true)
            defer { fixture.close() }
            try await settle()
            let initial = try fixture.snapshot()
            try fixture.tap()
            XCTAssertNil(try fixture.anchor.motion?.fraction)
            try await settle()
            XCTAssertGreaterThan(try fixture.snapshot().height, initial.height)
            XCTAssertTrue(fixture.state.revealHeights.isEmpty)
            try fixture.tap(); try await settle()
            XCTAssertEqual(try fixture.snapshot().height, initial.height, accuracy: 1)
        }
    }
    func testFractionalIntrinsicHeightsFinishWithoutWaitingForCleanupDeadline() async throws {
        for glass in [false, true] {
            let fixture = try TopMotionFixture(glass: glass, width: 280)
            defer { fixture.close() }
            try await settle()
            let initial = try fixture.snapshot()
            for _ in 0..<2 {
                try fixture.tap(); try await settle()
                XCTAssertNil(try fixture.anchor.motion?.fraction)
                try fixture.tap(); try await settle()
                XCTAssertNil(try fixture.anchor.motion?.fraction)
                XCTAssertEqual(try fixture.snapshot().height, initial.height, accuracy: 1)
            }
        }
    }
}
