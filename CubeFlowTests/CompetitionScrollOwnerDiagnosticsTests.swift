import XCTest
import SwiftUI
@testable import CubeFlow

@MainActor final class CompetitionScrollOwnerDiagnosticsTests: XCTestCase {
    private func withRecording(_ work: () async throws -> Void) async rethrows {
        let debug = CompetitionDebugStore.shared
        let wasEnabled = debug.enabled
        debug.setEnabled(true)
        defer { debug.setEnabled(wasEnabled) }
        let key = CompetitionScrollOwnerDiagnostics.enabledKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        CompetitionScrollOwnerDiagnostics.clear()
        defer {
            CompetitionScrollOwnerDiagnostics.clear()
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try await work()
    }

    func testExportRetainsOnlyFourCapturesAndSeparateLayoutEvents() async throws {
        try await withRecording {
            CompetitionScrollOwnerDiagnostics.event("preferred-invalidation", details: ["offsetAdjustmentY": 0.0])
            for index in 0..<6 {
                CompetitionScrollOwnerDiagnostics.archive(["index": index,
                    "loadingEvents": CompetitionScrollOwnerDiagnostics.events])
            }
            XCTAssertEqual(CompetitionScrollOwnerDiagnostics.captures.count, 4)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            defer { try? FileManager.default.removeItem(at: url) }
            try CompetitionScrollOwnerDiagnostics.export(to: url)
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(envelope["schema"] as? Int, 2)
            XCTAssertNotNil(envelope["systemVersion"] as? String)
            let captures = try XCTUnwrap(envelope["captures"] as? [[String: Any]])
            XCTAssertEqual(captures.compactMap { $0["index"] as? Int }, [2, 3, 4, 5])
            let events = try XCTUnwrap(captures[0]["loadingEvents"] as? [[String: Any]])
            XCTAssertEqual(events[0]["event"] as? String, "preferred-invalidation")
            XCTAssertEqual(events[0]["offsetAdjustmentY"] as? Double, 0)
        }
    }

    func testActualHostedHierarchyAndSwiftUILayoutAnchorAreRecorded() async throws {
        try await withRecording {
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            let controller = UIViewController()
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            let layout = UICollectionViewFlowLayout(); layout.itemSize = CGSize(width: 390, height: 150)
            let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
            controller.view.addSubview(collection)
            collection.register(CompetitionHostingCollectionViewCell.self, forCellWithReuseIdentifier: "row")
            let source = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, _ in
                let cell = collection.dequeueReusableCell(withReuseIdentifier: "row", for: path) as! CompetitionHostingCollectionViewCell
                cell.setRootView(AnyView(Text("Known SwiftUI content").padding().competitionDisclosureTitleProbe("fixture")))
                return cell
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0]); snapshot.appendItems(["competition:fixture:1"])
            await source.apply(snapshot, animatingDifferences: false)
            collection.layoutIfNeeded()
            // HostingConfiguration may render pure Text without any UIView
            // descendants. Wait for the explicit SwiftUI layout anchor to mount.
            try await Task.sleep(nanoseconds: 100_000_000)
            collection.layoutIfNeeded()
            let beforeOffset = collection.contentOffset
            let sample = try XCTUnwrap(CompetitionScrollOwnerDiagnostics.sample(collection))
            let cells = try XCTUnwrap(sample["cells"] as? [[String: Any]])
            let cell = try XCTUnwrap(cells.first)
            let hierarchy = try XCTUnwrap(cell["hostedHierarchy"] as? [[String: Any]])
            XCTAssertGreaterThan(hierarchy.count, 1, "Observe descendants, not just the stable cell.contentView")
            XCTAssertEqual(hierarchy.first?["path"] as? String, "contentView")
            XCTAssertTrue(hierarchy.dropFirst().allSatisfy { $0["model"] != nil && $0["presented"] != nil })
            XCTAssertNotNil(sample["scrollSurface"])
            let elements = try XCTUnwrap(cell["elements"] as? [[String: Any]])
            XCTAssertTrue(elements.contains { $0["id"] as? String == "fixture" })
            XCTAssertTrue(CompetitionScrollOwnerDiagnostics.events.contains { $0["event"] as? String == "set-root" })
            XCTAssertEqual(collection.contentOffset, beforeOffset, "Sampling must not adjust the scroll offset")
            XCTAssertFalse(ProcessInfo.processInfo.arguments.contains("--competition-scroll-owner-timing"))
            let trace = CompetitionLongScrollTrace()
            trace.begin(collection); trace.finish(collection)
            for _ in 0..<60 where CompetitionScrollOwnerDiagnostics.captures.isEmpty {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let completed = try XCTUnwrap(CompetitionScrollOwnerDiagnostics.captures.first)
            XCTAssertEqual(completed["idleRecordingComplete"] as? Bool, true)
            XCTAssertGreaterThan(try XCTUnwrap(completed["owners"] as? [[String: Any]]).count, 5)
            XCTAssertEqual(collection.accessibilityValue, "Recording", "Manual recording must not serialize the large accessibility JSON")
            XCTAssertEqual(collection.contentOffset, beforeOffset)
        }
    }
}
