import XCTest
import SwiftUI
import Combine
@testable import CubeFlow

@MainActor final class CompetitionFilterLifecycleFollowupTests: XCTestCase {
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Actual Browser/Filter lifecycle did not reach the expected state")
    }

    func testActualBrowserStatusChangesKeepNativePopoverAliveAndReopenable() async throws {
        let defaults = UserDefaults.standard
        let originalStore = CompetitionDebugStore.shared
        let storeRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FilterFollowup-\(UUID())")
        let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeRoot.lastPathComponent))
        let store = CompetitionDebugStore(defaults: storeDefaults, root: storeRoot)
        CompetitionDebugStore.shared = store
        store.setEnabled(true); store.start(.filter)
        defer {
            store.stop(.filter)
            if let capture = store.captures.first, let metadata = try? store.metadata(capture),
               let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "actual-browser-filter-lifecycle"; attachment.lifetime = .keepAlways; add(attachment)
            }
            CompetitionDebugStore.shared = originalStore
            storeDefaults.removePersistentDomain(forName: storeRoot.lastPathComponent)
            try? FileManager.default.removeItem(at: storeRoot)
        }
        let keys = ["appLanguage", "competition_filter_status", "competition_filter_region",
            "competition_filter_events", "competition_filter_year", "competition_show_top_cubers", "competitionCardStyle"]
        let previous = keys.map { ($0, defaults.object(forKey: $0)) }
        let scope = UUID()
        CompetitionBrowserPublicationAcceptance.scope = scope
        let today = try XCTUnwrap(CompetitionDateWindow(now: Date())).today
        func item(_ days: Int) -> CompetitionSummary {
            let day = today.addingTimeInterval(Double(days) * 86400)
            return CompetitionSummary(id: "lifecycle-\(scope)-\(days)", name: "Lifecycle \(days)", shortDisplayName: nil,
                startDate: day, endDate: day, registrationOpen: nil, registrationClose: nil,
                competitorLimit: nil, venue: "Venue", venueAddress: "Address", venueDetails: nil,
                city: "City", countryISO2: "US", latitude: nil, longitude: nil,
                url: "https://www.worldcubeassociation.org/competitions/fixture", website: nil,
                dateRange: "Fixture", eventIDs: ["333"], championshipTypes: nil,
                localizedRegionLineOverride: nil, localizedAddressLineOverride: nil,
                localizedStatusOverride: nil, localizedRegistrationStartOverride: nil, localizedWaitlistStartOverride: nil)
        }
        let items = [-2, 0, 2].map(item)
        CompetitionBrowserPublicationAcceptance.cache = { query in
            let filtered = items.filter { query.dateWindow?.contains($0, status: query.status) == true }
            return .init(competitions: filtered, totalCount: filtered.count, lastUpdated: Date())
        }
        CompetitionBrowserPublicationAcceptance.page = { _, _ in XCTFail("Fresh fixture must not use network"); return .init(competitions: [], receivedCount: 0, nextPage: nil, totalCount: 0) }
        var displayed: [String] = []
        CompetitionBrowserPublicationAcceptance.displayed = { displayed = $0 }
        defaults.set("en-Lifecycle-\(scope)", forKey: "appLanguage")
        defaults.set("present", forKey: "competition_filter_status")
        defaults.set(CompetitionRegionFilter.all.id, forKey: "competition_filter_region")
        defaults.set("333", forKey: "competition_filter_events")
        defaults.set("all", forKey: "competition_filter_year")
        defaults.set(false, forKey: "competition_show_top_cubers")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: CompatibleNavigationContainer {
            CompetitionBrowserView()
                .environment(\.competitionBrowserPublicationEnabled, true)
                .environment(\.competitionBrowserPublicationScope, scope)
        })
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer {
            host.beginAppearanceTransition(false, animated: false); host.endAppearanceTransition()
            window.isHidden = true; window.rootViewController = nil
            CompetitionBrowserPublicationAcceptance.cache = nil; CompetitionBrowserPublicationAcceptance.page = nil
            CompetitionBrowserPublicationAcceptance.displayed = nil; CompetitionBrowserPublicationAcceptance.filter = nil
            CompetitionBrowserPublicationAcceptance.scope = nil
            for (key, value) in previous { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        }
        try await wait { CompetitionBrowserPublicationAcceptance.filter != nil && !displayed.isEmpty }
        let filter = try XCTUnwrap(CompetitionBrowserPublicationAcceptance.filter)
        for style in ["list", "glass"] {
            defaults.set(style, forKey: "competitionCardStyle")
            for cycle in 0..<3 {
                filter.open()
                try await wait { host.presentedViewController != nil && host.presentedViewController?.isBeingPresented == false }
                let modal = try XCTUnwrap(host.presentedViewController)
                for status in [CompetitionStatusFilter.past, .recent, .present] {
                    defaults.set(status.rawValue, forKey: "competition_filter_status")
                    let expected = items.filter { CompetitionDateWindow(now: Date())?.contains($0, status: status) == true }.map(\.id)
                    try await wait { Set(displayed) == Set(expected) }
                    XCTAssertTrue(host.presentedViewController === modal, "Status update must not discard the presenting anchor")
                    XCTAssertTrue(filter.isPresented)
                    XCTAssertFalse(filter.isDismissing)
                    print("[FilterStatus] style=\(style) cycle=\(cycle) status=\(status) generation=\(filter.generation) presented=\(filter.isPresented) closing=\(filter.isDismissing) source=\(String(describing: modal.popoverPresentationController?.sourceView)) sourceWindow=\(modal.popoverPresentationController?.sourceView?.window != nil) surfaceWindow=\(modal.view.window != nil)")
                }
                filter.close(); filter.open()
                try await wait { host.presentedViewController != nil && host.presentedViewController !== modal && host.presentedViewController?.isBeingPresented == false }
                XCTAssertFalse(filter.isDismissing)
                filter.close()
                try await wait { host.presentedViewController == nil && !filter.isDismissing }
            }
        }
    }
}
