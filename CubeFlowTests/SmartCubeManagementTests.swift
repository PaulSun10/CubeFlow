import XCTest
import SwiftUI
import CoreBluetooth
import SceneKit
import Vision
@testable import CubeFlow

@MainActor final class SmartCubeManagementTests: XCTestCase {
    func testActualMultiDeviceMenuTitleRetainsResultsTypographyAndBalancedBattery() async throws {
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let a = UUID(), b = UUID()
        for id in [a, b] {
            let session = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
            session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3),
                                           name: "GAN CUBE", battery: 76)
            manager.debugInstallSession(session, for: id)
        }
        manager.selectActiveDevice(a)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: SmartCubeManagementCard(manager: manager,
            saved: store, selectedID: a, dismiss: {}))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: a); manager.disconnect(deviceID: b) }
        try await Task.sleep(nanoseconds: 150_000_000)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Actual multi-device Menu title and battery"; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
        let title = try XCTUnwrap(request.results?.first { $0.topCandidates(1).first?.string.contains("GAN CUBE") == true })
        let battery = try XCTUnwrap(request.results?.first { $0.topCandidates(1).first?.string.contains("76%") == true })
        // Vision's typographic boxes differ for percent signs and capitals.
        // Compare the actual rendered dark ink, not OCR ascender estimates.
        func inkHeight(_ observation: VNRecognizedTextObservation) throws -> CGFloat {
            let cg = try XCTUnwrap(image.cgImage)
            let rect = CGRect(x: observation.boundingBox.minX * CGFloat(cg.width),
                              y: (1 - observation.boundingBox.maxY) * CGFloat(cg.height),
                              width: observation.boundingBox.width * CGFloat(cg.width),
                              height: observation.boundingBox.height * CGFloat(cg.height))
                .insetBy(dx: -6, dy: -6).integral
            let crop = try XCTUnwrap(cg.cropping(to: rect))
            var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            let rows = (0..<crop.height).filter { y in
                (0..<crop.width).contains { x in
                    let i = (y * crop.width + x) * 4
                    return bytes[i] < 90 && bytes[i + 1] < 90 && bytes[i + 2] < 90
                }
            }
            return CGFloat(try XCTUnwrap(rows.last) - XCTUnwrap(rows.first) + 1) / image.scale
        }
        let titleHeight = try inkHeight(title), batteryHeight = try inkHeight(battery)
        print("[ManagementMenuTypography] title-ink-height=\(titleHeight) battery-ink-height=\(batteryHeight)")
        XCTAssertGreaterThan(titleHeight, 16, "The native Menu must not replace the 24pt Results title with its default body font")
        XCTAssertGreaterThanOrEqual(batteryHeight / titleHeight, 0.8)
        XCTAssertLessThanOrEqual(batteryHeight / titleHeight, 1.1)
        XCTAssertLessThan(abs(title.boundingBox.midY - battery.boundingBox.midY) * window.bounds.height, 4)
    }
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp()
        suite = "SmartCubeManagementTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); super.tearDown() }

    private func saved(_ id: UUID, store: SavedSmartCubeDevices, size: Int = 3) {
        let identity = SmartCubeIdentity.resolve(advertisedName: size == 2 ? "WCU_MY22" : "GAN16ui_Test",
            protocolFamily: size == 2 ? .moyu : .ganGen4, protocolConfirmed: true,
            protocolInfo: nil, serviceIdentifiers: [])
        store.remember(id: id, identity: identity, fallbackName: nil)
        store.setAutoConnect(true, for: id)
        store.rename(id, to: "Practice cube")
        store.rememberTransport(id: id, salt: [1, 2, 3, 4, 5, 6], manufacturerDataHex: "ABC", macAddress: "AA")
    }
    private func session(_ id: UUID, size: Int = 3) -> SmartCubePeripheralSession {
        let value = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
        value.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: size))
        return value
    }

    func testForgetRemovesOnlySelectedAssociationAndDeviceSpecificPreferencesAcrossRestart() throws {
        let a = UUID(), b = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(a, store: store); saved(b, store: store, size: 2)
        store.markActive(a); store.markActive(b)
        defaults.set("historical solve fixture", forKey: "unrelated-historical-solves")
        store.forget(a)
        let restarted = SavedSmartCubeDevices(defaults: defaults)
        XCTAssertNil(restarted.device(a)); XCTAssertNil(restarted.lastActiveID(puzzleSize: 3))
        XCTAssertEqual(restarted.device(b), store.device(b))
        XCTAssertEqual(restarted.lastActiveDeviceID, b)
        XCTAssertEqual(restarted.lastActiveID(puzzleSize: 2), b)
        XCTAssertEqual(defaults.string(forKey: "unrelated-historical-solves"), "historical solve fixture")
        saved(a, store: restarted)
        XCTAssertNotNil(restarted.device(a), "An explicit new association remains supported")
    }

    func testNoKnownDeviceKeepsOriginalConnectionEntryInsteadOfEmptyManagementCard() {
        let store = SavedSmartCubeDevices(defaults: defaults)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        XCTAssertFalse(manager.hasManageableDevices)
        let id = UUID()
        saved(id, store: store)
        XCTAssertTrue(manager.hasManageableDevices)
        store.forget(id)
        XCTAssertFalse(manager.hasManageableDevices)
        manager.debugInstallSession(session(id), for: id)
        XCTAssertTrue(manager.hasManageableDevices)
        manager.forgetDevice(id)
        XCTAssertFalse(manager.hasManageableDevices)
    }

    func testDisconnectAndForgetSelectedInactiveDeviceLeaveActiveConnectionUntouched() {
        let a = UUID(), b = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(a, store: store); saved(b, store: store)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let first = session(a), second = session(b)
        manager.debugInstallSession(first, for: a); manager.debugInstallSession(second, for: b)
        manager.selectActiveDevice(a)
        manager.disconnect(deviceID: b)
        XCTAssertEqual(manager.activeDeviceID, a)
        XCTAssertTrue(first.isConnected); XCTAssertFalse(second.isConnected)
        XCTAssertNotNil(store.device(b), "Disconnect retains association")
        manager.forgetDevice(b)
        XCTAssertNil(store.device(b)); XCTAssertNil(manager.session(for: b))
        XCTAssertTrue(first.isConnected); XCTAssertEqual(manager.activeDeviceID, a)
        manager.disconnect(deviceID: a)
    }

    func testForgettingActiveDeviceUsesExistingSoleCompatibleCandidateRule() {
        let a = UUID(), b = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(a, store: store); saved(b, store: store)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let first = session(a), second = session(b)
        manager.debugInstallSession(first, for: a); manager.debugInstallSession(second, for: b)
        manager.selectActiveDevice(a)
        manager.forgetDevice(a)
        XCTAssertEqual(manager.activeDeviceID, b)
        XCTAssertTrue(second.isConnected); XCTAssertFalse(first.isConnected)
        XCTAssertNil(store.device(a)); XCTAssertEqual(store.lastActiveDeviceID, b)
        manager.disconnect(deviceID: b)
    }

    func testStaleOrMismatchedResetAttemptNeverFallsBackToNewActiveDevice() throws {
        let a = UUID(), b = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(a, store: store); saved(b, store: store)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let first = session(a), second = session(b)
        manager.debugInstallSession(first, for: a); manager.debugInstallSession(second, for: b)
        manager.selectActiveDevice(a)
        var requested: [UUID?] = []
        manager.debugResetRequested = { requested.append($0) }
        manager.resetCubeStateToSolved(deviceID: a, attemptID: UUID())
        manager.resetCubeStateToSolved(deviceID: a, attemptID: second.connectionAttemptID)
        XCTAssertTrue(requested.isEmpty)
        manager.resetCubeStateToSolved(deviceID: b, attemptID: second.connectionAttemptID)
        XCTAssertEqual(requested, [b])
        XCTAssertEqual(manager.activeDeviceID, a)
        XCTAssertEqual(first.facelets, CubeSurface.solved(size: 3))
        XCTAssertTrue(first.isConnected); XCTAssertTrue(second.isConnected)
        manager.disconnect(deviceID: a); manager.disconnect(deviceID: b)
    }

    func testForgottenTransportRejectsLateConnectAndDoesNotRecreateRecord() {
        let id = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(id, store: store)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        manager.debugInstallSession(session(id), for: id)
        manager.debugRetireDevice(id)
        manager.forgetDevice(id)
        XCTAssertFalse(manager.debugCanAcceptConnection(id))
        manager.debugFinishRetirement(id)
        XCTAssertFalse(manager.debugCanAcceptConnection(id), "A late callback is not an explicit reconnect")
        XCTAssertNil(store.device(id)); XCTAssertNil(manager.session(for: id))
        store.rememberTransport(id: id, salt: [9], manufacturerDataHex: "late", macAddress: "late")
        XCTAssertNil(store.device(id), "Rediscovery metadata cannot recreate a saved association")
    }

    func testMountedCardViewingInactiveDeviceDoesNotChangeTimerSelection() async throws {
        let a = UUID(), b = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(a, store: store); saved(b, store: store, size: 2)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        manager.debugInstallSession(session(a), for: a); manager.debugInstallSession(session(b, size: 2), for: b)
        manager.selectActiveDevice(a)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: SmartCubeManagementCard(manager: manager,
            saved: store, selectedID: b, dismiss: {}))
        window.makeKeyAndVisible(); window.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: a); manager.disconnect(deviceID: b) }
        try await Task.sleep(nanoseconds: 250_000_000)
        window.layoutIfNeeded()
        XCTAssertEqual(manager.activeDeviceID, a)
        XCTAssertEqual(manager.session(for: b)?.puzzleSize, 2)
        XCTAssertEqual(manager.session(for: b)?.facelets?.count, 24)
        func sceneViews(_ view: UIView) -> [SCNView] {
            (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(sceneViews)
        }
        let sceneView = try XCTUnwrap(sceneViews(window).first)
        XCTAssertGreaterThan(sceneView.bounds.width, 100)
        XCTAssertEqual(sceneView.bounds.height, 190, accuracy: 0.5)
        XCTAssertNotNil(sceneView.scene)
        let cubeAttachment = XCTAttachment(image: sceneView.snapshot())
        cubeAttachment.name = "Management live 2x2 native SceneKit surface"
        cubeAttachment.lifetime = .keepAlways; add(cubeAttachment)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "Management card viewing inactive 2x2"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testMountedCardDisconnectShowsDiscoveryWithoutSwitchingToAnotherConnectedDevice() async throws {
        let a = UUID(), b = UUID(), offline = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        for id in [a, b, offline] { saved(id, store: store) }
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        manager.debugInstallSession(session(a), for: a); manager.debugInstallSession(session(b, size: 2), for: b)
        manager.selectActiveDevice(a)
        var selection: UUID?, available: [UUID] = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView:
            SmartCubeManagementCard(manager: manager, saved: store, selectedID: b, dismiss: {})
                .environment(\.smartCubeManagementSelection, { id, ids in selection = id; available = ids }))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: a); manager.disconnect(deviceID: b) }
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<150 {
                window.layoutIfNeeded()
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Mounted management selection did not update")
        }
        try await waitFor { selection == b }
        XCTAssertEqual(Set(available), [a, b]); XCTAssertEqual(manager.activeDeviceID, a)
        manager.disconnect(deviceID: b)
        try await waitFor { selection == nil }
        XCTAssertEqual(available, [a]); XCTAssertEqual(manager.activeDeviceID, a)
        manager.disconnect(deviceID: a)
        try await waitFor { manager.managementConnectedDeviceIDs.isEmpty }
        XCTAssertTrue(manager.managementConnectedDeviceIDs.isEmpty)
        XCTAssertEqual(Set(store.devices.map(\.id)), [a, b, offline], "Disconnect must retain saved associations")
        func scenes(_ view: UIView) -> [SCNView] { (view as? SCNView).map { [$0] } ?? view.subviews.flatMap(scenes) }
        try await waitFor { scenes(window).isEmpty }
    }

    func testMountedCardDefaultsToActiveOnlyWithoutAnExplicitManagedIdentity() async throws {
        let a = UUID(), offline = UUID(), store = SavedSmartCubeDevices(defaults: defaults)
        saved(a, store: store); saved(offline, store: store)
        let manager = SmartCubeBluetoothManager(testSavedDevices: store)
        manager.prepareIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        manager.debugInstallSession(session(a), for: a); manager.selectActiveDevice(a)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer { window.isHidden = true; window.rootViewController = nil; manager.disconnect(deviceID: a) }
        for initial in [UUID?.none, offline] {
            var selection: UUID?
            var available: [UUID] = []
            window.rootViewController = UIHostingController(rootView:
                SmartCubeManagementCard(manager: manager, saved: store, selectedID: initial, dismiss: {})
                    .environment(\.smartCubeManagementSelection, { selection = $0; available = $1 }))
            window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(selection, initial == nil ? a : nil)
            XCTAssertEqual(available, [a]); XCTAssertEqual(manager.activeDeviceID, a)
        }
        window.rootViewController = nil
        manager.disconnect(deviceID: a)
        let b = UUID()
        manager.debugInstallSession(session(b, size: 2), for: b)
        defer { manager.disconnect(deviceID: b) }
        XCTAssertNil(manager.activeDeviceID, "A connected 2x2 is inspectable without becoming Active for Timer's 3x3")
        var fallback: UUID?
        window.rootViewController = UIHostingController(rootView:
            SmartCubeManagementCard(manager: manager, saved: store, selectedID: offline, dismiss: {})
                .environment(\.smartCubeManagementSelection, { id, _ in fallback = id }))
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(fallback, "An explicit offline identity opens discovery, not a different connected cube")
        XCTAssertNil(manager.activeDeviceID)
    }

    func testSharedCardGeometryAndDisconnectedBodyHaveNoLiveStateOrEnabledReset() {
        for width in [CGFloat(320), 402, 800] {
            let size = CGSize(width: width, height: 874)
            XCTAssertEqual(CompetitionResultCardGeometry.width(in: size), min(max(width - 32, 280), 430))
            XCTAssertEqual(CompetitionResultCardGeometry.maximumHeight(in: size), 680)
        }
        let body = SmartCubeManagementBody(name: AnyView(Text("Saved WeiPo")), battery: nil,
            liveCube: nil, canReset: false, canDisconnect: false, reset: {}, disconnect: {}, forget: {})
        XCTAssertNil(body.liveCube); XCTAssertNil(body.battery)
        XCTAssertFalse(body.canReset); XCTAssertFalse(body.canDisconnect)
        let host = UIHostingController(rootView: body)
        let size = host.sizeThatFits(in: CGSize(width: 370, height: 680))
        XCTAssertGreaterThan(size.height, 250); XCTAssertLessThan(size.height, 680)
        let fitted = UIHostingController(rootView: SmartCubeManagementFittedContent(maximumHeight: 680) { body })
        XCTAssertEqual(fitted.sizeThatFits(in: CGSize(width: 370, height: 874)).height, size.height, accuracy: 0.5)
        let legacy = UIHostingController(rootView: SmartCubeManagementLegacyFit(maximumHeight: 680) { body })
        XCTAssertEqual(legacy.sizeThatFits(in: CGSize(width: 370, height: 874)).height, size.height, accuracy: 0.5)
    }
    func testMountedSharedResultsTitleAndBatteryWithNativeTintedGlassInBothThemes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for dark in [false, true] {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let body = SmartCubeManagementBody(name: AnyView(Text("GAN 16 MagLev")), battery: 76, liveCube: nil,
                canReset: true, canDisconnect: true, reset: {}, disconnect: {}, forget: {})
            window.rootViewController = UIHostingController(rootView: ZStack {
                Color.gray
                body.frame(width: 361).competitionResultCardSurface()
                    .overlay(alignment: .topTrailing) { CompetitionResultCardCloseButton(label: "Close", action: {}).padding(12) }
                    .competitionResultCardShadow()
            }.environment(\.colorScheme, dark ? .dark : .light))
            window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(nanoseconds: 100_000_000); window.layoutIfNeeded()
            func buttons(_ view: UIView) -> [UIButton] {
                (view as? UIButton).map { [$0] } ?? view.subviews.flatMap(buttons)
            }
            let mounted = buttons(window)
            let reset = try XCTUnwrap(mounted.first { $0.accessibilityIdentifier == "smart-cube-management-reset" })
            let disconnect = try XCTUnwrap(mounted.first { $0.accessibilityIdentifier == "smart-cube-management-disconnect" })
            let forget = try XCTUnwrap(mounted.first { $0.accessibilityIdentifier == "smart-cube-management-forget" })
            let edit = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
            SessionNativeActionStyle.apply(to: edit, tint: .systemBlue)
            XCTAssertEqual(reset.tintColor, edit.tintColor)
            XCTAssertEqual(forget.tintColor, .systemRed)
            XCTAssertEqual(disconnect.bounds.width, forget.bounds.width, accuracy: 0.5)
            XCTAssertEqual(reset.bounds.width, 317, accuracy: 0.5)
            XCTAssertEqual(reset.bounds.width, disconnect.bounds.width + 12 + forget.bounds.width, accuracy: 0.5)
            var expected = SessionNativeActionStyle.configuration(tint: .systemBlue)
            expected.buttonSize = .large
            XCTAssertEqual(reset.configuration?.buttonSize, expected.buttonSize)
            XCTAssertEqual(reset.configuration?.cornerStyle, expected.cornerStyle)
            XCTAssertEqual(reset.configuration?.baseForegroundColor, expected.baseForegroundColor)
            XCTAssertEqual(reset.configuration?.baseBackgroundColor, expected.baseBackgroundColor)
            XCTAssertGreaterThanOrEqual(reset.bounds.height, 44)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "shared-results-title-battery-native-glass-\(dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways; add(attachment)
            let fit = UIHostingController(rootView: body).sizeThatFits(in: .init(width: 361, height: 680))
            XCTAssertGreaterThan(fit.height, 250); XCTAssertLessThan(fit.height, 680)
        }
    }

    func testRendererRetainsNativePanAndAddsOnlyADisabledOptionalManagementTap() {
        let coordinator = SmartCube3DView.Coordinator()
        let view = coordinator.makeView(owner: "management-gesture-test")
        defer { coordinator.stop() }
        // SCNView also installs its own private camera recognizers, including
        // when camera control is off. Assert the application's existing owner.
        let pans = view.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
            .filter { $0.name == "CubeFlow.SmartCube.Drag" } ?? []
        XCTAssertEqual(pans.count, 1)
        XCTAssertEqual(pans.first?.maximumNumberOfTouches, 1)
        XCTAssertEqual(coordinator.managementTap?.isEnabled, false)
        XCTAssertNil(coordinator.onTap)
        var calls = 0
        coordinator.onTap = { calls += 1 }
        coordinator.onTap?()
        XCTAssertEqual(calls, 1)
        coordinator.stop()
        XCTAssertNil(coordinator.onTap)
    }

    func testOversizedManagementContentUsesVerticalScrollInsteadOfClippedNaturalContent() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: SmartCubeManagementFittedContent(maximumHeight: 680) {
            Color.blue.frame(width: 370, height: 900)
        })
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func scrolls(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        for _ in 0..<20 where scrolls(window).isEmpty {
            window.layoutIfNeeded(); try await Task.sleep(nanoseconds: 10_000_000)
        }
        let scroll = try XCTUnwrap(scrolls(window).first, "Oversized contents must be reachable, not clipped")
        XCTAssertEqual(scroll.bounds.height, 680, accuracy: 1)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
    }
}
