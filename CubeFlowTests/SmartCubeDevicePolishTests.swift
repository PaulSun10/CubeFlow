#if DEBUG
import XCTest
import SwiftUI
import CoreBluetooth
import SceneKit
import Combine
import Vision
@testable import CubeFlow

@MainActor final class SmartCubeDevicePolishTests: XCTestCase {
    func testNativeDiscoveryLargeTitleCollapsesWithoutBackgroundNavigationAndEmptyProse() async throws {
        let suite = "DiscoveryNavigation." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: saved)
        let identity = SmartCubeIdentity.resolve(advertisedName: "GAN16ui_Test", protocolFamily: .ganGen4,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        for index in 0..<25 {
            let id = UUID(); saved.remember(id: id, identity: identity, fallbackName: nil)
            saved.rename(id, to: "Offline Cube \(index)")
        }
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: SmartCubeManagementCard(manager: manager, saved: saved,
            selectedID: saved.devices.first?.id, dismiss: {}).environment(\.locale, Locale(identifier: "en")))
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func controllers(_ c: UIViewController) -> [UIViewController] { [c] + c.children.flatMap(controllers) }
        func scrolls(_ v: UIView) -> [UIScrollView] { (v as? UIScrollView).map { [$0] } ?? v.subviews.flatMap(scrolls) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let nav = try XCTUnwrap(controllers(host).compactMap { $0 as? UINavigationController }.first)
        let scroll = try XCTUnwrap(scrolls(window).first { $0.contentSize.height > $0.bounds.height + 100 })
        XCTAssertTrue(nav.navigationBar.prefersLargeTitles)
        XCTAssertEqual(nav.topViewController?.navigationItem.title, "Smart Cube")
        XCTAssertEqual(nav.navigationBar.directionalLayoutMargins.leading, CompetitionResultCardTitleStyle.contentInset)
        XCTAssertEqual(nav.navigationBar.directionalLayoutMargins.trailing, CompetitionResultCardTitleStyle.contentInset)
        let barFrame = nav.navigationBar.convert(nav.navigationBar.bounds, to: window)
        print("[DiscoveryTitleInsets] bar=\(barFrame) margins=\(nav.navigationBar.directionalLayoutMargins) system=\(nav.systemMinimumLayoutMargins) view=\(nav.view.directionalLayoutMargins)")
        let expanded = nav.navigationBar.bounds.height
        func attach(_ name: String) throws -> String {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            if name.hasPrefix("Discovery native large title") {
                let title = try XCTUnwrap(request.results?.first { $0.topCandidates(1).first?.string == "Smart Cube" })
                let leading = title.boundingBox.minX * window.bounds.width - barFrame.minX
                print("[DiscoveryTitleInkInset] leading=\(leading)")
                XCTAssertEqual(leading, CompetitionResultCardTitleStyle.contentInset, accuracy: 1,
                    "The actual native large title must use the existing card content inset")
            }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        XCTAssertTrue(try attach("Discovery native large title and passive saved rows").contains("Smart Cube"))
        scroll.setContentOffset(CGPoint(x: 0, y: 250), animated: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertLessThan(nav.navigationBar.bounds.height, expanded, "The real navigation bar must collapse with its List")
        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertNil(nav.presentedViewController)
        _ = try attach("Discovery native inline title after scrolling")
        for _ in 0..<6 {
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(nanoseconds: 50_000_000)
            window.layoutIfNeeded()
        }
        let empty = try attach("Other Devices empty with refresh header")
        XCTAssertTrue(empty.localizedCaseInsensitiveContains("Other Devices"), empty)
        XCTAssertFalse(empty.localizedCaseInsensitiveContains("Wake the cube"), empty)
        XCTAssertFalse(empty.localizedCaseInsensitiveContains("No smart cubes found"), empty)
        XCTAssertTrue(manager.managementConnectedDeviceIDs.isEmpty)
        XCTAssertEqual(saved.devices.count, 25)
        for _ in 0..<6 {
            // The inline inset excludes the collapsed large-title extent.
            let hiddenTitleHeight = max(0, expanded - nav.navigationBar.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top - hiddenTitleHeight), animated: false)
            try await Task.sleep(nanoseconds: 50_000_000)
            window.layoutIfNeeded()
        }
        print("[DiscoveryTitleReturn] offset=\(scroll.contentOffset) insets=\(scroll.adjustedContentInset) height=\(nav.navigationBar.bounds.height)")
        XCTAssertEqual(nav.navigationBar.bounds.height, expanded, accuracy: 0.5)
        _ = try attach("Discovery native large title restored with inset")
    }

    func testManagementNameUsesTheFormerSpacerWidthWithoutChangingTypography() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let name = "GAN16 MagLev Pro"
        var metrics: [String: CGSize] = [:]
        let cardWidth = CompetitionResultCardGeometry.width(in: window.bounds.size)
        window.rootViewController = UIHostingController(rootView: ZStack {
            Color.gray
            SmartCubeManagementBody(name: AnyView(Text(name)), battery: 76, liveCube: nil, canReset: true,
                canDisconnect: true, reset: {}, disconnect: {}, forget: {})
                .frame(width: cardWidth).competitionResultCardSurface()
                .overlay(alignment: .topTrailing) { CompetitionResultCardCloseButton(label: "Close", action: {}).padding(12) }
        }.environment(\.smartCubeManagementTitleMetrics, { metrics = $0 }))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        let intrinsic = UIHostingController(rootView: Text(name).font(.system(size: 24, weight: .bold)))
            .sizeThatFits(in: CGSize(width: 1000, height: 100)).width
        let nameWidth = try XCTUnwrap(metrics["name"]).width
        let batteryWidth = try XCTUnwrap(metrics["battery"]).width
        let available = cardWidth - 44 - CompetitionResultCardTitleStyle.closeInset - 12 - batteryWidth
        XCTAssertEqual(nameWidth, available, accuracy: 0.5)
        XCTAssertLessThanOrEqual(intrinsic, nameWidth)
        XCTAssertGreaterThan(intrinsic, nameWidth - 16, "This name needs the space previously consumed by the extra spacer")
        let longIntrinsic = UIHostingController(rootView: Text("GAN 16 MagLev Pro").font(.system(size: 24, weight: .bold)))
            .sizeThatFits(in: CGSize(width: 1000, height: 100)).width
        XCTAssertGreaterThan(longIntrinsic, nameWidth, "An actually wider name must still truncate rather than shrink its font")
        print("[TitleActualWidth] intrinsicSwiftUI=\(intrinsic) available=\(available) name=\(nameWidth) battery=\(batteryWidth) longerName=\(longIntrinsic)")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Management name using legitimate title width"; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        XCTAssertTrue(lines.contains { $0.contains(name) }, lines.joined(separator: " | "))
        XCTAssertTrue(lines.contains { $0.contains("76%") })
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Mounted Smart Cube state did not settle")
    }

    func testOneConnectionHUDPerRealAttemptNotDiscoveryNavigationOrDuplicateSuccess() throws {
        let suite = "ConnectionFeedback." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = SavedSmartCubeDevices(defaults: defaults)
        var hud: [String] = []
        let manager = SmartCubeBluetoothManager(testSavedDevices: saved, connectionFeedback: { hud.append($0) })
        let id = UUID(), other = UUID(), attempt = UUID()
        let session = manager.debugMakeRoutedSession(for: id)
        manager.debugReportConnectionSuccess(id)
        session.debugSeedConnectionPhase(.connecting, deviceID: id, attemptID: attempt)
        manager.debugReportConnectionSuccess(id)
        XCTAssertTrue(hud.isEmpty)
        session.debugSeedConnectedState(deviceID: id, attemptID: attempt, facelets: CubeSurface.solved(size: 3))
        manager.debugReportConnectionSuccess(id)
        manager.debugReportConnectionSuccess(id)
        manager.selectActiveDevice(id)
        manager.objectWillChange.send()
        XCTAssertEqual(hud.count, 1, "Rerenders and Active selection are not connection-success events")
        manager.disconnect(deviceID: id)
        manager.debugReportConnectionSuccess(id)
        XCTAssertEqual(hud.count, 1)
        // Automatic reconnect arrives through the same manager didConnect owner,
        // with a fresh attempt rather than through a particular mounted view.
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.debugReportConnectionSuccess(id); manager.debugReportConnectionSuccess(id)
        XCTAssertEqual(hud.count, 2)
        let second = manager.debugMakeRoutedSession(for: other)
        second.debugSeedConnectedState(deviceID: other, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.debugReportConnectionSuccess(other)
        XCTAssertEqual(hud.count, 3)
        XCTAssertTrue(hud.allSatisfy { !$0.isEmpty })
        manager.disconnect(deviceID: id); manager.disconnect(deviceID: other)
    }

    func testMountedSameCardRetainsDiscoveryThroughFailureRetryAndReconnectWithoutNestedPresentation() async throws {
        let suite = "UnifiedCard." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = SavedSmartCubeDevices(defaults: defaults)
        let manager = SmartCubeBluetoothManager(testSavedDevices: saved), id = UUID(), attempt = UUID()
        manager.prepareIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        let session = manager.debugMakeRoutedSession(for: id)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        var displayed: UUID?
        let host = UIHostingController(rootView: SmartCubeManagementCard(manager: manager, saved: saved,
            selectedID: id, dismiss: { XCTFail("Connection state must not dismiss the card") })
            .environment(\.smartCubeManagementSelection, { id, _ in displayed = id }))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: id) }
        func sceneCount(_ view: UIView) -> Int {
            (view is SCNView ? 1 : 0) + view.subviews.reduce(0) { $0 + sceneCount($1) }
        }
        func noNestedPresentation(_ controller: UIViewController) -> Bool {
            controller.presentedViewController == nil && controller.children.allSatisfy(noNestedPresentation)
        }
        func attach(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(displayed); XCTAssertEqual(sceneCount(window), 0)
        attach("Unified card native discovery")
        for phase in [SmartCubeConnectionState.connecting, .failed("Fixture timeout"), .connecting] {
            session.debugSeedConnectionPhase(phase, deviceID: id, attemptID: attempt)
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertNil(displayed); XCTAssertEqual(sceneCount(window), 0)
            XCTAssertTrue(noNestedPresentation(host))
        }
        session.debugSeedConnectedState(deviceID: id, attemptID: attempt, facelets: CubeSurface.solved(size: 3))
        try await wait { displayed == id && sceneCount(window) == 1 }
        XCTAssertTrue(noNestedPresentation(host))
        attach("Same card after connection")
        manager.disconnect(deviceID: id)
        try await wait { displayed == nil && sceneCount(window) == 0 }
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        try await wait { displayed == id && sceneCount(window) == 1 }
        XCTAssertTrue(noNestedPresentation(host))
        XCTAssertTrue(window.rootViewController === host)
    }

    func testBundledPrivacyManifestDeclaresOnlyAuditedRequiredReasons() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url),
            options: [], format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(plist["NSPrivacyTrackingDomains"] as? [String], [])
        let apis = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: try apis.map {
            (try XCTUnwrap($0["NSPrivacyAccessedAPIType"] as? String),
             try XCTUnwrap($0["NSPrivacyAccessedAPITypeReasons"] as? [String]))
        })
        XCTAssertEqual(reasons, ["NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1", "3D61.1"]])
        XCTAssertNil(plist["NSPrivacyCollectedDataTypes"], "Do not invent owner/provider privacy answers")
    }
}
#endif
