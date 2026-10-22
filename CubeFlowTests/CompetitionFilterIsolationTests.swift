import XCTest
import SwiftUI
@testable import CubeFlow

/// Test-only isolation: the production popover binding, completion observer,
/// presenter and selection controls remain the owners in every variant.
@MainActor final class CompetitionFilterIsolationTests: XCTestCase {
    private struct Surface: View {
        @ObservedObject var filter: CompetitionFilterPresentation
        let variant: String
        @State private var region = CompetitionRegionFilter.all
        @State private var events = Set(CompetitionEventFilter.selectableCases)
        @State private var year = CompetitionYearFilter.all
        @State private var status = CompetitionStatusFilter.present
        @State private var top = true
        var body: some View {
            NavigationView {
                Text("Competition Browser").toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Filter") { filter.open() }
                            .competitionFilterPopover(presentation: filter) { visible in
                                Group {
                                    if variant == "B-minimal" {
                                        Button("Close") { visible.wrappedValue = false }.frame(width: 290, height: 348)
                                    } else {
                                        CompetitionFiltersPopover(selectedRegion: $region, selectedEvents: $events,
                                            selectedYear: $year, selectedStatus: $status, availablePastYears: [2025, 2024],
                                            showsTopCubers: $top, appLanguage: "en", showsFilterPopover: visible)
                                            .environment(\.competitionFilterIsolation,
                                                variant == "C-no-decoration" ? ["visual-layers"] :
                                                variant == "D-no-supplementary" ? ["supplementary-animation"] : [])
                                            .transaction { if variant == "D-no-supplementary" { $0.animation = nil } }
                                    }
                                }
                                .compatibleClearPresentationBackground()
                                .compatiblePopoverCompactAdaptation()
                            }
                    }
                }
            }.navigationViewStyle(.stack)
        }
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Native presentation boundary did not finish")
    }
    func testFourVariantsRepeatSameNativeDismissalAndQueuedReopenBoundaries() async throws {
        let previous = CompetitionDebugStore.shared
        let suite = "FilterIsolation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let store = CompetitionDebugStore(defaults: defaults, root: root)
        CompetitionDebugStore.shared = store; store.setEnabled(true)
        defer {
            CompetitionDebugStore.shared = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var results: [[String: Any]] = []
        for variant in ["A-full", "B-minimal", "C-no-decoration", "D-no-supplementary"] {
            store.start(.filter)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let filter = CompetitionFilterPresentation()
            let host = UIHostingController(rootView: Surface(filter: filter, variant: variant))
            window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            filter.open()
            try await wait { host.presentedViewController != nil && host.presentedViewController?.isBeingPresented == false }
            for cycle in 0..<3 {
                let first = try XCTUnwrap(host.presentedViewController)
                XCTAssertNotNil(first.popoverPresentationController)
                let generation = filter.generation
                let start = CACurrentMediaTime()
                filter.close(); filter.open()
                var previousTime = start, largestPollGap = 0.0
                for _ in 0..<400 {
                    let now = CACurrentMediaTime()
                    largestPollGap = max(largestPollGap, now - previousTime); previousTime = now
                    if filter.generation > generation { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                XCTAssertEqual(filter.generation, generation + 1)
                XCTAssertTrue(filter.isPresented)
                XCTAssertFalse(filter.isDismissing)
                let eligible = CACurrentMediaTime()
                try await wait { host.presentedViewController != nil && host.presentedViewController !== first && host.presentedViewController?.isBeingPresented == false }
                results.append(["variant": variant, "cycle": cycle + 1, "dismissIntent": start,
                    "observedReopenEligible": eligible, "mainActorMaxPollGapMS": largestPollGap * 1000])
            }
            filter.close()
            try await wait { host.presentedViewController == nil && !filter.isDismissing }
            store.stop(.filter)
            let capture = try XCTUnwrap(store.captures.first)
            let metadata = try store.metadata(capture)
            let events = try XCTUnwrap(metadata["events"] as? [[String: Any]])
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "filter-isolation-\(variant)"; attachment.lifetime = .keepAlways; add(attachment)
            let disappearances = events.filter { $0["event"] as? String == "native-will-disappear" }
            for entry in disappearances {
                let start = try XCTUnwrap(entry["time"] as? Double)
                func next(_ name: String) -> Double? {
                    events.first { $0["event"] as? String == name && ($0["time"] as? Double ?? 0) >= start }?["time"] as? Double
                }
                let complete = try XCTUnwrap(next("completion-accepted"))
                XCTAssertNotNil(next("transition-completion"))
                XCTAssertNotNil(next("native-did-disappear"))
                print("[FilterIsolation] variant=\(variant) nativeDismissMS=\((complete-start)*1000) coordinatorMS=\(((next("transition-completion") ?? complete)-start)*1000)")
            }
            XCTAssertGreaterThanOrEqual(disappearances.count, 4)
            window.isHidden = true; window.rootViewController = nil
        }
        let result = XCTAttachment(data: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        result.name = "filter-isolation-comparison"; result.lifetime = .keepAlways; add(result)
        XCTAssertEqual(results.count, 12)
    }
}
