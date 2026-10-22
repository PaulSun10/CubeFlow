#if os(iOS) && DEBUG
import XCTest
import SwiftUI
import CoreData
import WebKit
@testable import CubeFlow

@MainActor final class TimerRefreshInteractionTests: XCTestCase {
    private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Production Timer did not settle")
        throw NSError(domain: "TimerRefreshFixture", code: 1)
    }
    func testMountedTimerInstantNextPreservesNativeButtonAndHighlightedOwnership() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native Liquid Glass requires iOS 26") }
        let persistence = PersistenceController(inMemory: true)
        let session = Session(name: "Refresh interaction", context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "timer",
            "timerArrangement": "cards", "scrambleDisplayMode": "shrinkFont", "showNextScrambleButton": true, "appLanguage": "en"]
        let defaults = UserDefaults.standard, previous = settings.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        let probe = SmartCubeTimerGuidanceProbe()
        var pending: [(TimerScrambleGenerationContext, String, @MainActor (TimerScrambleGenerationPayload) -> Void)] = []
        probe.generate = { pending.append(($0, $1, $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeTimerGuidanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { !pending.isEmpty && probe.snapshot != nil }
        let first = pending.removeFirst(); first.2(.init(context: first.0, scrambles: ["R U F2"]))
        try await wait { pending.contains { $0.1 == "prefetch" } }
        let next = pending.remove(at: pending.firstIndex { $0.1 == "prefetch" }!)
        next.2(.init(context: next.0, scrambles: ["L D B2"]))
        try await wait { probe.snapshot?().prefetchIsReady == true }
        func button() -> UIButton? { views(window).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "timer-next-scramble" } }
        let original = try XCTUnwrap(button()), configuration = original.configuration
        original.isHighlighted = true
        original.sendActions(for: .touchUpInside)
        XCTAssertEqual(probe.snapshot?().scramble, "L D B2", "Prefetched replacement stays immediate in the action turn")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(button() === original)
        XCTAssertTrue(original.isHighlighted, "A SwiftUI scramble update must not reset UIKit's tracking state")
        XCTAssertEqual(original.configuration?.contentInsets, configuration?.contentInsets)
        XCTAssertEqual(original.configuration?.cornerStyle, configuration?.cornerStyle)
        XCTAssertEqual(original.configuration?.image, configuration?.image)
        original.isHighlighted = false
        XCTAssertFalse(original.isHighlighted)
        probe.start?()
        XCTAssertEqual(probe.snapshot?().assignment?.scramble, "L D B2")
    }

    func testCardsRetainCompletePresentationAcrossRapidNextAndCommitPreparedPair() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native Glass requires iOS 26") }
        let persistence = PersistenceController(inMemory: true)
        let session = Session(name: "Cards retention", context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let settings: [String: Any] = ["selectedSessionID": session.id.uuidString, "enteringTimesWith": "timer",
            "timerArrangement": "cards", "scrambleDisplayMode": "shrinkFont", "showNextScrambleButton": true,
            "timerMinimalMode": false, "appLanguage": "en"]
        let defaults = UserDefaults.standard, previous = settings.keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        let probe = SmartCubeTimerGuidanceProbe()
        var pending: [(TimerScrambleGenerationContext, String, @MainActor (TimerScrambleGenerationPayload) -> Void)] = []
        probe.generate = { pending.append(($0, $1, $2)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: TimerTabView()
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeTimerGuidanceProbe, probe))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; probe.reset() }
        try await wait { !pending.isEmpty && probe.snapshot != nil }
        XCTAssertEqual(probe.snapshot?().scramble, "…", "Initial loading has no previous content to retain")
        let first = pending.removeFirst()
        first.2(.init(context: first.0, scrambles: ["R U F2"]))
        try await wait { probe.snapshot?().scramble == "R U F2" }
        let old = try XCTUnwrap(probe.snapshot?().diagram)
        XCTAssertEqual(old.scramble, "R U F2")
        XCTAssertNotNil(UIImage(data: old.pngData))
        XCTAssertFalse(views(window).contains { $0 is WKWebView }, "Cards displays the prepared image, not a reloading Web page")
        let original = try XCTUnwrap(views(window).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "timer-next-scramble" })
        try await wait { pending.contains { $0.1 == "prefetch" } }
        let replacement = pending.remove(at: pending.firstIndex { $0.1 == "prefetch" }!)
        for _ in 0..<12 {
            original.sendActions(for: .touchUpInside)
            try await Task.sleep(nanoseconds: 20_000_000)
            window.layoutIfNeeded()
            XCTAssertEqual(probe.snapshot?().scramble, old.scramble)
            XCTAssertEqual(probe.snapshot?().diagram, old)
            XCTAssertTrue(views(window).contains { $0 === original })
        }
        XCTAssertTrue(pending.isEmpty, "Repeated Next must keep waiting for the same in-flight prefetch")
        replacement.2(.init(context: replacement.0, scrambles: ["L D B2"]))
        try await wait { probe.snapshot?().scramble == "L D B2" }
        let next = try XCTUnwrap(probe.snapshot?().diagram)
        XCTAssertEqual(next.scramble, "L D B2")
        XCTAssertNotEqual(next.pngData, old.pngData)
        XCTAssertNotNil(UIImage(data: next.pngData))
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Cards prepared text and diagram after rapid Next"
        attachment.lifetime = .keepAlways; add(attachment)

        // The same pending-generation state in the other arrangements keeps
        // its existing loading behavior; retention is scoped to Cards.
        for arrangement in ["classic", "split"] {
            defaults.set(arrangement, forKey: "timerArrangement")
            try await Task.sleep(nanoseconds: 100_000_000)
            probe.next?()
            XCTAssertEqual(probe.snapshot?().scramble, "…")
        }
    }
}
#endif
