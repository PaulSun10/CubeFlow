#if DEBUG && os(iOS)
import XCTest
import SwiftUI
import CoreData
@testable import CubeFlow

@MainActor final class BattleEventSelectorTests: XCTestCase {
    func testOrderingCoverageAndTruePanelOrientation() {
        XCTAssertEqual(BattleEventSelectorPolicy.events, PuzzleEvent.regularCases + PuzzleEvent.blindfoldedCases)
        XCTAssertEqual(Set(BattleEventSelectorPolicy.events), Set(PuzzleEvent.allCases))
        XCTAssertEqual(BattleEventSelectorPolicy.events.count, PuzzleEvent.allCases.count)
        XCTAssertEqual(BattleEventSelectorPolicy.rotation(player: .second, mode: .headToHead), 180)
        XCTAssertEqual(BattleEventSelectorPolicy.rotation(player: .first, mode: .headToHead), 0)
        for player in LocalBattlePlayer.allCases { XCTAssertEqual(BattleEventSelectorPolicy.rotation(player: player, mode: .sideBySide), 0) }
    }

    func testMountedSelectorSelectionReopeningAndNativeContactIsolation() async throws {
        let persistence = PersistenceController(inMemory: true), context = persistence.container.viewContext
        let session = Session(name: "Selector fixture", context: context); try context.save()
        let defaults = UserDefaults.standard
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "timer",
            "appLanguage": "en", "smartCubeReadySound": false, "wcaInspectionEnabled": false, "timerArrangement": "cards"]
        let previous = settings.map { ($0.key, defaults.object(forKey: $0.key)) }
        settings.forEach { defaults.set($0.value, forKey: $0.key) }
        defer { previous.forEach { defaults.set($0.1, forKey: $0.0) }; AppOrientationManager.reset() }
        let probe = LocalBattleTestProbe(), generation = SmartCubeTimerGuidanceProbe()
        var requests: [PuzzleEvent] = []
        var textOnlyDeliveries = 0
        generation.generate = { context, reason, complete in
            requests.append(context.event); complete(.init(context: context, scrambles: ["R U"]))
            if reason == "battle" {
                textOnlyDeliveries += 1
                XCTAssertFalse(probe.snapshot?().scrambles.requests.values.contains { $0.event == context.event } ?? true,
                    "Text-only Battle delivery must not wait on Cards diagram rendering")
            }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        // Timer intentionally uses Color.clear in System appearance. Give this
        // extra test window an opaque backing so the real app's Timer window
        // cannot bleed into material/screenshot sampling below the fixture.
        window.backgroundColor = .systemBackground
        window.isOpaque = true
        window.rootViewController = UIHostingController(rootView: TimerTabView().environment(\.managedObjectContext, context)
            .environment(\.smartCubeTimerGuidanceProbe, generation).environment(\.localBattleTestProbe, probe))
        window.rootViewController?.view.backgroundColor = .systemBackground
        window.windowLevel = .alert + 2; window.makeKeyAndVisible()
        defer {
            probe.mode?(.solo); probe.mode = nil; probe.press = nil; probe.release = nil; probe.cancel = nil; probe.snapshot = nil
            probe.selectorOpen = nil; probe.selectorChoose = nil; probe.selectorDismiss = nil; probe.selectorSnapshot = nil
            probe.selectorCanOpen = nil
            generation.reset(); window.isHidden = true; window.rootViewController = nil
        }
        try await wait { probe.mode != nil }
        for mode in [LocalBattleMode.headToHead, .sideBySide] {
            // Follow the actual UI route: exit to Solo before choosing another
            // battle layout, rather than replacing two active scene rotations.
            probe.mode?(.solo)
            try await wait("exit previous battle") { self.contacts(window).isEmpty }
            probe.mode?(mode)
            try await wait { probe.selectorOpen != nil && probe.snapshot?().scrambles.displayed.count == 2 }
            try await wait("settled native panels for \(mode.rawValue)") {
                window.layoutIfNeeded()
                let views = self.contacts(window)
                return views.count == 2 && views.allSatisfy { view in
                    let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
                    return view.bounds.width > 0 && window.hitTest(point, with: nil) === view
                }
            }
            let original = probe.snapshot?().scrambles.displayed[.first]
            for event in [PuzzleEvent.pyraminx, .fourByFourFast, .threeByThreeFM, .threeByThreeBLD] {
                probe.selectorOpen?(.second)
                XCTAssertEqual(probe.selectorSnapshot?() ?? nil, .second)
                XCTAssertNil(probe.snapshot?().firstStart); XCTAssertNil(probe.snapshot?().secondStart)
                XCTAssertFalse(probe.snapshot?().firstPressing ?? true); XCTAssertFalse(probe.snapshot?().secondPressing ?? true)
                probe.selectorChoose?(event)
                XCTAssertEqual(probe.selectorSnapshot?() ?? nil, .second)
                XCTAssertEqual(probe.snapshot?().scrambles.displayed[.second]?.request.event, event)
                XCTAssertEqual(requests.last, event)
                XCTAssertEqual(probe.snapshot?().scrambles.displayed[.first], original)
                probe.selectorDismiss?()
            }
            for _ in 0..<5 {
                probe.selectorOpen?(.second); probe.selectorDismiss?()
                XCTAssertNil(probe.selectorSnapshot?() ?? nil)
            }
            probe.selectorOpen?(.second)
            try await wait("selector contact layout for \(mode.rawValue)") {
                window.layoutIfNeeded()
                let views = self.contacts(window)
                let reachable = views.filter { view in
                    window.hitTest(view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window), with: nil) === view
                }.count
                return views.count == 2 && reachable == 1
            }
            window.layoutIfNeeded()
            let surfaces = contacts(window)
            XCTAssertEqual(surfaces.count, 2)
            var blocked = 0, reachable = 0
            for view in surfaces {
                let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
                if window.hitTest(point, with: nil) === view { reachable += 1 } else { blocked += 1 }
            }
            XCTAssertEqual(blocked, 1, "Only the owner panel is covered by the selector")
            XCTAssertEqual(reachable, 1, "Opponent must still be able to stop")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "battle-selector-\(mode.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("build/fmc-battle-performance-nov02/selector-\(mode.rawValue).png")
            try image.pngData()?.write(to: output)
            probe.selectorDismiss?()
            XCTAssertEqual(probe.snapshot?().scrambles.displayed[.second]?.request.event, .threeByThreeBLD)
            probe.press?(.first); probe.press?(.second); probe.release?(.first)
            try await wait("active event guard for \(mode.rawValue)") { probe.snapshot?().firstStart != nil && probe.selectorCanOpen?(.first) == false }
            probe.selectorOpen?(.first)
            XCTAssertNil(probe.selectorSnapshot?() ?? nil, "An active player's event cannot be changed")
            probe.cancel?(.second)
            try await Task.sleep(nanoseconds: 30_000_000)
            probe.selectorOpen?(.second)
            XCTAssertEqual(probe.selectorSnapshot?() ?? nil, .second, "Idle player can select without pausing opponent")
            XCTAssertNotNil(probe.snapshot?().firstStart)
            probe.selectorDismiss?(); probe.release?(.first)
        }
        XCTAssertGreaterThanOrEqual(textOnlyDeliveries, 12)
    }
    private func contacts(_ view: UIView) -> [BattleContactSurface.ContactView] {
        (view as? BattleContactSurface.ContactView).map { [$0] } ?? view.subviews.flatMap(contacts)
    }
    private func wait(_ label: String = #function, _ condition: () -> Bool) async throws {
        for _ in 0..<400 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("Selector lifecycle timeout: \(label)"); throw CancellationError()
    }
}
#endif
