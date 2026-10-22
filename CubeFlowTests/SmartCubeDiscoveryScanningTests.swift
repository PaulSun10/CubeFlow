#if os(iOS) && DEBUG
import XCTest
import SwiftUI
import Combine
import Vision
@testable import CubeFlow

@MainActor final class SmartCubeDiscoveryScanningTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp()
        suite = "DiscoveryScan." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }
    private func remember(_ id: UUID, store: SavedSmartCubeDevices) {
        let identity = SmartCubeIdentity.resolve(advertisedName: "GAN16ui_Test", protocolFamily: .ganGen4,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        store.remember(id: id, identity: identity, fallbackName: "Nearby Cube")
    }
    private func advertisement(_ id: UUID, rssi: Int = -45) -> SmartCubeDiscoveredDevice {
        .init(id: id, name: "GAN16ui_Test", rssi: rssi, protocolHint: .ganGen4,
            advertisedServices: [], manufacturerDataHex: nil, macAddress: nil)
    }
    private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }
    private func hasAnimatingSpinner(_ root: UIView) -> Bool {
        views(root).compactMap { $0 as? UIActivityIndicatorView }.contains { $0.isAnimating && !$0.isHidden }
    }
    private func mount(_ content: some View) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: content.environment(\.locale, Locale(identifier: "en")))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true; window.rootViewController = nil }
        return window
    }
    private func settle() async throws { try await Task.sleep(nanoseconds: 150_000_000) }

    func testScanOwnersAreContinuousIdempotentAndSuspendWithoutLosingDiscoveries() {
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let driver = SmartCubeScanTestDriver(); manager.debugScanDriver = driver
        var starts = 0, stops = 0
        driver.start = { starts += 1 }; driver.stop = { stops += 1 }
        let first = UUID(), second = UUID(), device = UUID()
        manager.beginDiscoveryScanning(owner: first)
        manager.beginDiscoveryScanning(owner: first)
        manager.beginDiscoveryScanning(owner: second)
        XCTAssertEqual(starts, 1); XCTAssertTrue(manager.isScanningForDevices)
        manager.debugReceiveDiscovery(advertisement(device))
        manager.startScanning(); manager.startScanning(); manager.stopScanning()
        XCTAssertEqual(starts, 1); XCTAssertEqual(stops, 0)
        XCTAssertEqual(manager.discoveredDevices.map(\.id), [device])
        manager.endDiscoveryScanning(owner: first)
        XCTAssertTrue(manager.isScanningForDevices)
        driver.foreground = false
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(manager.isScanningForDevices); XCTAssertEqual(stops, 1)
        driver.foreground = true
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(manager.isScanningForDevices); XCTAssertEqual(starts, 2)
        driver.poweredOn = false; manager.debugUpdateScanEnvironment()
        XCTAssertFalse(manager.isScanningForDevices)
        driver.poweredOn = true; manager.debugUpdateScanEnvironment()
        XCTAssertTrue(manager.isScanningForDevices); XCTAssertEqual(starts, 3)
        XCTAssertEqual(manager.discoveredDevices.map(\.id), [device])
        manager.endDiscoveryScanning(owner: second)
        XCTAssertFalse(manager.isScanningForDevices); XCTAssertEqual(stops, 3)
    }

    func testDiscoveryReleasePreservesAutoDiscoveryAndConnectedActiveSession() {
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let driver = SmartCubeScanTestDriver(); manager.debugScanDriver = driver
        let missing = UUID(), connected = UUID(), owner = UUID()
        remember(missing, store: store); store.setAutoConnect(true, for: missing)
        let session = manager.debugMakeRoutedSession(for: connected)
        session.debugSeedConnectedState(deviceID: connected, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        manager.selectActiveDevice(connected)
        manager.beginDiscoveryScanning(owner: owner)
        manager.endDiscoveryScanning(owner: owner)
        XCTAssertTrue(manager.isScanningForDevices, "Saved auto-connect remains an independent scan reason")
        store.setAutoConnect(false, for: missing); manager.resumeSavedDeviceDiscovery()
        XCTAssertFalse(manager.isScanningForDevices)
        driver.foreground = false
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(session.isConnected); XCTAssertEqual(manager.activeDeviceID, connected)
        XCTAssertEqual(manager.connectedDeviceIDs, [connected])
    }

    func testMountedConnectReusesNativeEditStyleAndSurvivesRepeatedAdvertisements() async throws {
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let driver = SmartCubeScanTestDriver(); manager.debugScanDriver = driver
        let id = UUID(); remember(id, store: store)
        manager.debugReceiveDiscovery(advertisement(id))
        var requests: [UUID] = [], publications = 0
        let token = manager.$discoveredDevices.dropFirst().sink { _ in publications += 1 }
        defer { token.cancel() }
        let window = try mount(CompatibleNavigationContainer {
            List { SmartCubeDiscoverySections(manager: manager, saved: store,
                connect: { requests.append($0) }, manage: { _ in XCTFail("Offline row must remain passive") }) }
        })
        try await settle()
        let identifier = "smart-cube-connect-" + id.uuidString
        func button() -> UIButton? { views(window).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == identifier } }
        let original = try XCTUnwrap(button())
        let reference = SessionNativeActionStyle.configuration(tint: .systemBlue)
        XCTAssertEqual(original.tintColor, .systemBlue)
        XCTAssertEqual(original.configuration?.cornerStyle, reference.cornerStyle)
        XCTAssertEqual(original.configuration?.baseBackgroundColor, reference.baseBackgroundColor)
        XCTAssertEqual(original.configuration?.baseForegroundColor, reference.baseForegroundColor)
        XCTAssertEqual(original.configuration?.contentInsets, reference.contentInsets)
        XCTAssertLessThan(original.bounds.width, 120, "Keep the action content-sized, not full-row")
        original.sendActions(for: .touchUpInside); XCTAssertEqual(requests, [id])
        let owner = UUID(); manager.beginDiscoveryScanning(owner: owner)
        defer { manager.endDiscoveryScanning(owner: owner) }
        for _ in 0..<10 { manager.startScanning(); manager.debugReceiveDiscovery(advertisement(id)) }
        XCTAssertEqual(publications, 0, "Identical advertisements must not republish or remove rows")
        manager.stopScanning()
        manager.debugReceiveDiscovery(advertisement(id, rssi: -60))
        XCTAssertEqual(publications, 1)
        try await settle()
        XCTAssertTrue(button() === original, "The actual native Connect view retains its identity")
        XCTAssertEqual(manager.discoveredDevices.map(\.id), [id])
        XCTAssertEqual(manager.discoveredDevices.first?.rssi, -60)
        XCTAssertTrue(hasAnimatingSpinner(window))
        XCTAssertFalse(views(window).contains { $0.accessibilityIdentifier == "smart-cube-discovery-refresh" })
        let session = manager.debugMakeRoutedSession(for: id)
        session.debugSeedConnectionPhase(.connecting, deviceID: id, attemptID: UUID())
        try await settle(); XCTAssertNil(button(), "Real connecting eligibility still removes the action")
        session.debugSeedConnectionPhase(.disconnected, deviceID: id, attemptID: UUID())
        try await settle(); XCTAssertNotNil(button(), "A failed/disconnected attempt is actionable again")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let spinner = try XCTUnwrap(views(window).compactMap { $0 as? UIActivityIndicatorView }.first { $0.isAnimating })
        let spinnerFrame = spinner.convert(spinner.bounds, to: window)
        let recognition = VNRecognizeTextRequest(); recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
        let header = try XCTUnwrap(recognition.results?.first { $0.topCandidates(1).first?.string.lowercased() == "other devices" })
        let gap = spinnerFrame.minX - header.boundingBox.maxX * window.bounds.width
        XCTAssertGreaterThanOrEqual(gap, 5)
        XCTAssertLessThanOrEqual(gap, 15, "Spinner follows the title, not the trailing section edge")
        XCTAssertGreaterThanOrEqual(spinner.bounds.width, 20)
        let attachment = XCTAttachment(image: image); attachment.name = "Native blue Connect capsule and actual scanning spinner"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testMountedPickerOwnsScanOnlyWhileDiscoveryExistsAndSpinnerTracksRadio() async throws {
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let driver = SmartCubeScanTestDriver(); driver.poweredOn = false; manager.debugScanDriver = driver
        let picker = SmartCubeDevicePickerView(manager: manager, savedDevices: store, manage: { _ in })
        let window = try mount(picker)
        try await settle()
        XCTAssertEqual(manager.debugDiscoveryScanOwnerCount, 1)
        XCTAssertFalse(manager.isScanningForDevices)
        XCTAssertFalse(hasAnimatingSpinner(window))
        driver.poweredOn = true; manager.debugUpdateScanEnvironment()
        try await settle()
        XCTAssertTrue(manager.isScanningForDevices)
        XCTAssertTrue(hasAnimatingSpinner(window))
        driver.poweredOn = false; manager.debugUpdateScanEnvironment()
        try await settle()
        XCTAssertFalse(hasAnimatingSpinner(window))
        driver.poweredOn = true; manager.debugUpdateScanEnvironment()
        window.rootViewController = UIHostingController(rootView: Text("Management"))
        try await settle()
        XCTAssertEqual(manager.debugDiscoveryScanOwnerCount, 0)
        XCTAssertFalse(manager.isScanningForDevices)
    }
}
#endif
