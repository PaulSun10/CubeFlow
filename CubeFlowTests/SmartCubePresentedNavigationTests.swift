#if os(iOS) && DEBUG
import XCTest
import SwiftUI
import CoreData
import Vision
@testable import CubeFlow

@MainActor final class SmartCubePresentedNavigationTests: XCTestCase {
    private enum Failure: Error { case timeout }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Real card presentation did not settle", file: file, line: line)
        throw Failure.timeout
    }
    private func controllers(_ root: UIViewController) -> [UIViewController] {
        [root] + root.children.flatMap(controllers)
    }
    private func scrolls(_ view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
    }
    private func image(_ window: UIWindow, name: String) -> UIImage {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return image
    }
    func testActualTimerPresentationShowsDiscoveryTitleAndSurvivesConnectionTransitions() async throws {
        try await exercise(settings: false)
    }
    func testActualSettingsManagementDisconnectShowsDiscoveryInSamePresentation() async throws {
        try await exercise(settings: true)
    }

    private func exercise(settings: Bool) async throws {
        let persistence = PersistenceController(inMemory: true)
        let selected = Session(name: "Presented navigation", selectedTimingMethodRawValue: "smartCube",
            context: persistence.container.viewContext)
        try persistence.container.viewContext.save()
        let defaults = UserDefaults.standard
        let keys = ["selectedSessionID", "enteringTimesWith", "appLanguage"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defaults.set(selected.id.uuidString, forKey: keys[0])
        defaults.set("smartCube", forKey: keys[1]); defaults.set("en", forKey: keys[2])
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        let manager = SmartCubeBluetoothManager.shared, saved = SavedSmartCubeDevices.shared
        let previousDriver = manager.debugScanDriver
        manager.debugScanDriver = SmartCubeScanTestDriver()
        let initialScanOwners = manager.debugDiscoveryScanOwnerCount
        defer { manager.debugScanDriver = previousDriver; manager.debugUpdateScanEnvironment() }
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let device = UUID(), probe = SmartCubeCardEntryProbe()
        let session = manager.debugMakeRoutedSession(for: device)
        var temporaryIDs: [UUID] = []
        defer {
            probe.openTimer = nil; probe.openSettingsDevice = nil
            manager.disconnect(deviceID: device)
            for id in temporaryIDs { manager.forgetDevice(id) }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let content = settings ? AnyView(SettingsTabView()) : AnyView(CompatibleNavigationContainer { TimerTabView() })
        let host = UIHostingController(rootView: content
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .environment(\.smartCubeCardEntryProbe, probe))
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { self.controllers(host).contains { $0 is UINavigationController } }
        let underlying = try XCTUnwrap(controllers(host).compactMap { $0 as? UINavigationController }.first)
        if settings {
            // Mount the production Settings destinations in its real native
            // navigation owner; the card below uses the Lab's actual presenter.
            underlying.pushViewController(UIHostingController(rootView: ConnectedDevicesView()), animated: false)
            underlying.pushViewController(UIHostingController(rootView: SmartCubeLabView()
                .environment(\.smartCubeCardEntryProbe, probe)), animated: false)
            try await wait { probe.openSettingsDevice != nil }
            session.debugSeedConnectedState(deviceID: device, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
            manager.selectActiveDevice(device)
            probe.openSettingsDevice?(device)
        } else {
            try await wait { probe.openTimer != nil }
            probe.openTimer?()
        }
        let underlyingCount = underlying.viewControllers.count
        try await wait { host.presentedViewController != nil && host.presentedViewController?.isBeingPresented == false }
        let modal = try XCTUnwrap(host.presentedViewController)
        XCTAssertTrue(modal is CompetitionResultsNavigationController, "Use the real custom card presenter, not an isolated hosting root")
        if settings {
            manager.disconnect(deviceID: device)
        }
        try await wait {
            self.controllers(modal).contains { ($0 as? UINavigationController)?.topViewController?.navigationItem.title == "Smart Cube" }
        }
        let navigation = try XCTUnwrap(controllers(modal).compactMap { $0 as? UINavigationController }
            .first { $0.topViewController?.navigationItem.title == "Smart Cube" })
        let before = image(window, name: "Actual \(settings ? "Settings disconnect" : "Timer") discovery card")
        let visibleBars = controllers(modal).compactMap { $0 as? UINavigationController }
            .filter { !$0.isNavigationBarHidden && !$0.navigationBar.isHidden && $0.navigationBar.alpha > 0 }
        print("[PresentedNavigation] source=\(settings ? "settings" : "timer") owners=\(controllers(modal).compactMap { $0 as? UINavigationController }.map { "\(type(of: $0)):hidden=\($0.isNavigationBarHidden):title=\($0.topViewController?.navigationItem.title ?? "nil")" })")
        XCTAssertFalse(navigation.isNavigationBarHidden)
        XCTAssertFalse(navigation.navigationBar.isHidden)
        XCTAssertEqual(visibleBars.count, 1)
        let frame = navigation.view.convert(navigation.view.bounds, to: window).intersection(window.bounds)
        let crop = CGRect(x: frame.minX * before.scale, y: frame.minY * before.scale,
            width: frame.width * before.scale, height: frame.height * before.scale)
        let cardImage = try XCTUnwrap(before.cgImage?.cropping(to: crop))
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: cardImage).perform([request])
        let titleInk = try XCTUnwrap(request.results?.first { $0.topCandidates(1).first?.string == "Smart Cube" })
        XCTAssertEqual(titleInk.boundingBox.minX * frame.width, 22, accuracy: 1.5)
        XCTAssertGreaterThan(titleInk.boundingBox.height * frame.height, 20, "The visible card must start with its large, not inline, title")
        XCTAssertNil(modal.presentedViewController)
        XCTAssertEqual(underlying.viewControllers.count, underlyingCount)
        XCTAssertEqual(manager.debugDiscoveryScanOwnerCount, initialScanOwners + 1)
        XCTAssertTrue(manager.isScanningForDevices)

        let identity = SmartCubeIdentity.resolve(advertisedName: "GAN16ui_Test", protocolFamily: .ganGen4,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        for index in 0..<24 {
            let id = UUID(); temporaryIDs.append(id)
            saved.remember(id: id, identity: identity, fallbackName: nil)
            saved.rename(id, to: "Offline \(index)")
        }
        try await wait { self.scrolls(navigation.view).contains { $0.contentSize.height > $0.bounds.height + 100 } }
        let scroll = try XCTUnwrap(scrolls(navigation.view).first { $0.contentSize.height > $0.bounds.height + 100 })
        let expanded = navigation.navigationBar.bounds.height
        scroll.setContentOffset(CGPoint(x: 0, y: 250), animated: false)
        try await wait { navigation.navigationBar.bounds.height < expanded }
        _ = image(window, name: "Actual card inline title")
        for _ in 0..<6 {
            let hidden = max(0, expanded - navigation.navigationBar.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top - hidden), animated: false)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(navigation.navigationBar.bounds.height, expanded, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(navigation.navigationBar.directionalLayoutMargins.leading, 22)
        session.debugSeedConnectedState(deviceID: device, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        try await wait { !self.controllers(modal).contains { ($0 as? UINavigationController)?.topViewController?.navigationItem.title == "Smart Cube" } }
        try await wait { manager.debugDiscoveryScanOwnerCount == initialScanOwners }
        XCTAssertTrue(host.presentedViewController === modal)
        XCTAssertNil(modal.presentedViewController)
        manager.disconnect(deviceID: device)
        try await wait { self.controllers(modal).contains { ($0 as? UINavigationController)?.topViewController?.navigationItem.title == "Smart Cube" } }
        XCTAssertTrue(host.presentedViewController === modal)
        XCTAssertEqual(underlying.viewControllers.count, underlyingCount)
        let returned = try XCTUnwrap(controllers(modal).compactMap { $0 as? UINavigationController }
            .first { $0.topViewController?.navigationItem.title == "Smart Cube" })
        XCTAssertFalse(returned.isNavigationBarHidden)
        _ = image(window, name: "Same real card after reconnect and disconnect")
        await withCheckedContinuation { continuation in modal.dismiss(animated: false) { continuation.resume() } }
        try await wait { manager.debugDiscoveryScanOwnerCount == initialScanOwners }
    }
}
#endif
