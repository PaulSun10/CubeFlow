import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor private final class ScrollRetentionTabs: ObservableObject {
    @Published var selection = 0
    @Published var mountsCompetition = true
    @Published var competitionGeneration = 0
    let disclosure = CompetitionDisclosureAcceptanceState()
}

private struct ScrollRetentionNavigationFixture: View {
    @ObservedObject var tabs: ScrollRetentionTabs
    var body: some View {
        TabView(selection: $tabs.selection) {
            Group {
                if tabs.mountsCompetition {
                    CompetitionDisclosureAcceptanceSurface(state: tabs.disclosure)
                        .id(tabs.competitionGeneration)
                } else { Color.clear }
            }.tabItem { Text("Competitions") }.tag(0)
            CompatibleNavigationContainer { CompetitionScrollDiagnosticsView() }
                .tabItem { Text("Settings") }.tag(1)
        }
    }
}

@MainActor final class CompetitionScrollRetentionTests: XCTestCase {
    private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Expected navigation/capture condition did not arrive")
    }
    func testCompletedGestureSurvivesSettingsReturnAndDisablingBeforeIdleFinalization() async throws {
        try await exercise(detachCompetition: true)
    }
    func testRecordingOffRetainsCompletedGestureWhileCollectionStillMounted() async throws {
        try await exercise(detachCompetition: false)
    }
    func testClearRejectsLateArchiveFromPreviousRecording() {
        let store = CompetitionScrollCaptureStore.shared
        store.clear()
        let generation = store.generation
        store.clear()
        store.archive(["old": true], generation: generation)
        XCTAssertTrue(store.captures.isEmpty)
    }
    private func exercise(detachCompetition: Bool) async throws {
        let debug = CompetitionDebugStore.shared
        let wasEnabled = debug.enabled
        debug.setEnabled(true)
        defer { debug.setEnabled(wasEnabled) }
        let key = CompetitionScrollOwnerDiagnostics.enabledKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        CompetitionScrollOwnerDiagnostics.clear()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let tabs = ScrollRetentionTabs()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: ScrollRetentionNavigationFixture(tabs: tabs))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            CompetitionScrollOwnerDiagnostics.clear()
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        func collection() -> UICollectionView? {
            func controllers(_ controller: UIViewController) -> [UIViewController] {
                [controller] + controller.children.flatMap(controllers)
            }
            guard let root = window.rootViewController,
                  let tab = controllers(root).compactMap({ $0 as? UITabBarController }).first,
                  tab.selectedIndex == 0, let selected = tab.selectedViewController?.view else { return nil }
            return views(selected).compactMap { $0 as? UICollectionView }.first {
                $0.accessibilityIdentifier == "competition-disclosure-list" || $0.accessibilityIdentifier == "competition-long-list"
            }
        }
        try await wait { collection() != nil }
        tabs.selection = 1
        try await Task.sleep(nanoseconds: 100_000_000)
        UserDefaults.standard.set(true, forKey: key)
        tabs.selection = 0
        try await wait { collection()?.window != nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        let list = try XCTUnwrap(collection())
        XCTAssertNotNil(list.delegate)
        // Exercise the REAL production coordinator, not trace.begin/finish directly.
        list.delegate?.scrollViewWillBeginDragging?(list)
        list.setContentOffset(CGPoint(x: 0, y: 180), animated: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        list.delegate?.scrollViewDidEndDragging?(list, willDecelerate: false)
        if detachCompetition {
            tabs.selection = 1
            tabs.mountsCompetition = false
        }
        UserDefaults.standard.set(false, forKey: key)
        try await wait { !CompetitionScrollOwnerDiagnostics.captures.isEmpty }
        let capture = try XCTUnwrap(CompetitionScrollOwnerDiagnostics.captures.first)
        XCTAssertEqual(capture["gestureCompleted"] as? Bool, true)
        XCTAssertEqual(capture["captureFinalized"] as? Bool, true)
        XCTAssertEqual(capture["idleRecordingComplete"] as? Bool, false, "Do not invent missing post-idle coverage")
        let frames = try XCTUnwrap(capture["owners"] as? [[String: Any]])
        XCTAssertFalse(frames.isEmpty)
        XCTAssertNotNil(frames.first?["offset"])
        XCTAssertNotNil(frames.first?["cells"])
        tabs.selection = 1
        tabs.mountsCompetition = false
        try await wait { list.window == nil }
        XCTAssertEqual(CompetitionScrollOwnerDiagnostics.captures.count, 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try CompetitionScrollOwnerDiagnostics.export(to: url)
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((exported["captures"] as? [[String: Any]])?.count, 1)
        // TabView can cache inactive content without evaluating its intermediate
        // false branch. Explicitly request a new owner for the replacement check.
        tabs.competitionGeneration += 1
        tabs.mountsCompetition = true; tabs.selection = 0
        try await wait { collection()?.window != nil }
        XCTAssertFalse(collection() === list, "A replacement collection must not own or clear retained captures")
        XCTAssertEqual(CompetitionScrollOwnerDiagnostics.captures.count, 1)
    }
}
