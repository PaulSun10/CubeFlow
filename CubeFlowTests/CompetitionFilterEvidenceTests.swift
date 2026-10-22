import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CompetitionFilterEvidenceTests: XCTestCase {
    private struct Surface: View {
        @ObservedObject var filter: CompetitionFilterPresentation
        var body: some View {
            Button("Filter") { filter.open() }.competitionFilterPopover(presentation: filter) { visible in
                Button("Close") { visible.wrappedValue = false }.padding().frame(width: 290)
                    .compatiblePopoverCompactAdaptation()
            }
        }
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Native lifecycle did not complete")
    }
    func testCapturedRepeatedOpenIntentPublishesOnceImmediatelyAfterAcknowledgement() {
        let filter = CompetitionFilterPresentation()
        filter.open(); let original = filter.generation
        filter.contentMounted(generation: original); filter.close()
        // E7871F72 records three delivered reopens while this epoch dismisses.
        for _ in 0..<3 { filter.open() }
        XCTAssertTrue(filter.isDismissing); XCTAssertFalse(filter.isPresented)
        XCTAssertEqual(filter.generation, original)
        filter.dismissalFinished(generation: original)
        XCTAssertTrue(filter.isPresented)
        XCTAssertFalse(filter.isDismissing)
        XCTAssertEqual(filter.generation, original + 1)
        filter.dismissalFinished(generation: original)
        filter.frameworkChanged(false, generation: original)
        XCTAssertTrue(filter.isPresented)
        XCTAssertEqual(filter.generation, original + 1)
    }
    func testCaptureDistinguishesObserverAndNativeCoordinatorWithoutChangingNativeLifecycle() async throws {
        let previous = CompetitionDebugStore.shared
        let suite = "FilterEvidence-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let store = CompetitionDebugStore(defaults: defaults, root: root)
        CompetitionDebugStore.shared = store
        store.setEnabled(true); store.start(.filter)
        let filter = CompetitionFilterPresentation()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: Surface(filter: filter))
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            store.stop(.filter); CompetitionDebugStore.shared = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        filter.open()
        try await wait { host.presentedViewController != nil && !(host.presentedViewController?.isBeingPresented ?? true) }
        let first = try XCTUnwrap(host.presentedViewController)
        XCTAssertNotNil(first.popoverPresentationController)
        filter.close(); filter.open()
        try await wait { host.presentedViewController != nil && host.presentedViewController !== first && !(host.presentedViewController?.isBeingPresented ?? true) }
        XCTAssertNil(host.presentedViewController?.presentedViewController)
        filter.close()
        try await wait { host.presentedViewController == nil && !filter.isDismissing }
        store.stop(.filter)
        let capture = try XCTUnwrap(store.captures.first)
        let events = try XCTUnwrap(try store.metadata(capture)["events"] as? [[String: Any]])
        let names = events.compactMap { $0["event"] as? String }
        for name in ["native-did-disappear", "completion-registration", "transition-completion", "completion-accepted"] {
            XCTAssertTrue(names.contains(name), name)
        }
        let surface = try XCTUnwrap(events.first { $0["event"] as? String == "dismissal-native-surface" })
        XCTAssertNotNil(surface["elapsed"] as? Double)
        XCTAssertNotNil(surface["surfaceBounds"] as? [Double])
        XCTAssertNotNil(surface["surfaceTransform"] as? [Double])
        XCTAssertNotNil(surface["surfaceOwner"] as? String)
        let ancestors = try XCTUnwrap(surface["surfaceAncestors"] as? [[String: Any]])
        XCTAssertFalse(ancestors.isEmpty)
        XCTAssertLessThanOrEqual(ancestors.count, 16)
        XCTAssertNotNil(ancestors.first?["animationKeys"] as? [String])
        let registration = try XCTUnwrap(events.first { $0["event"] as? String == "completion-registration" })
        XCTAssertNotNil(registration["observer"])
        XCTAssertNotNil(registration["nativeContainer"])
        XCTAssertNotNil(registration["observerCoordinator"] as? [String: Any])
        XCTAssertNotNil(registration["nativeCoordinator"] as? [String: Any])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(events))
    }
}
